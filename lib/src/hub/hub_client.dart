import 'package:dio/dio.dart';

import 'dto.dart';
import 'exception.dart';

class HubClient {
  final Dio _dio;
  final Uri _baseUri;
  final String daemonVersion;
  final bool allowInsecureHub;

  HubClient(
    String baseUrl, {
    this.daemonVersion = 'unknown',
    this.allowInsecureHub = false,
    Dio? dio,
  }) : _baseUri = canonicalizeRegistry(
         baseUrl,
         allowInsecure: allowInsecureHub,
       ),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 5),
               receiveTimeout: const Duration(seconds: 30),
               headers: {"Content-Type": "application/json"},
             ),
           );

  static Uri canonicalizeRegistry(String value, {bool allowInsecure = false}) {
    final parsed = Uri.tryParse(value.trim());
    final loopback = parsed != null && _isLoopbackHost(parsed.host);
    if (parsed == null ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.query.isNotEmpty ||
        parsed.fragment.isNotEmpty ||
        (parsed.scheme != 'https' &&
            !(parsed.scheme == 'http' && (allowInsecure || loopback)))) {
      throw const FormatException('Registry URL is invalid');
    }
    final normalizedPath = parsed.pathSegments
        .where((segment) => segment.isNotEmpty)
        .join('/');
    final defaultPort = parsed.scheme == 'https' ? 443 : 80;
    return Uri(
      scheme: parsed.scheme.toLowerCase(),
      host: parsed.host.toLowerCase(),
      port: parsed.hasPort && parsed.port != defaultPort ? parsed.port : null,
      path: normalizedPath.isEmpty ? '' : '/$normalizedPath',
    );
  }

  static bool _isLoopbackHost(String host) {
    final normalized = host.toLowerCase();
    return normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '::1' ||
        normalized.endsWith('.localhost');
  }

  String get canonicalRegistry => _baseUri.toString();

  Future<ResolveResult> resolve({
    required String namespace,
    required String name,
    required String version,
    required String os,
    required String arch,
    required String abi,
    required String client,
  }) async {
    final segments = <String>[
      ..._baseUri.pathSegments.where((segment) => segment.isNotEmpty),
      'v1',
      'tools',
      namespace,
      name,
      'versions',
      version,
      'resolve',
    ];
    final uri = _baseUri.replace(
      path: '/${segments.map(Uri.encodeComponent).join('/')}',
      queryParameters: {'os': os, 'arch': arch, 'abi': abi},
    );
    try {
      final response = await _dio.getUri<Map<String, dynamic>>(
        uri,
        options: Options(
          headers: {
            'User-Agent': 'opentool-daemon/$daemonVersion',
            'X-AgentOS-Client': client,
          },
        ),
      );
      final data = response.data;
      if (data == null) {
        throw const HubApiException(
          code: 'HUB_INVALID_RESPONSE',
          message: 'Hub returned an empty resolve response',
          retryable: true,
        );
      }
      return ResolveResult.fromJson(data);
    } on DioException catch (error) {
      throw _mapDioException(error);
    } on HubApiException {
      rethrow;
    } on Object catch (error) {
      throw HubApiException(
        code: 'HUB_INVALID_RESPONSE',
        message: 'Hub resolve response is invalid: $error',
        retryable: true,
      );
    }
  }

  HubApiException _mapDioException(DioException error) {
    final status = error.response?.statusCode;
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      try {
        final body = HubErrorEnvelope.fromJson(data).error;
        return HubApiException(
          code: body.code,
          message: body.message,
          statusCode: status,
          retryable:
              status == null || status == 408 || status == 429 || status >= 500,
          requestId: body.requestId,
        );
      } catch (_) {}
    }
    return HubApiException(
      code: 'HUB_UNAVAILABLE',
      message: status == null
          ? 'Unable to reach OpenTool Hub'
          : 'OpenTool Hub request failed with status $status',
      statusCode: status,
      retryable:
          status == null || status == 408 || status == 429 || status >= 500,
    );
  }
}
