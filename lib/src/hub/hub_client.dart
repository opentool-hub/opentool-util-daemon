import 'package:dio/dio.dart';

import 'dto.dart';
import 'exception.dart';
import '../service/pull_cancellation.dart';

class HubClient {
  final Dio _dio;
  final Uri _baseUri;
  final String daemonVersion;

  HubClient(String baseUrl, {this.daemonVersion = 'unknown', Dio? dio})
    : _baseUri = canonicalizeRegistry(baseUrl),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 30),
              headers: {"Content-Type": "application/json"},
            ),
          );

  static Uri canonicalizeRegistry(String value) {
    final parsed = Uri.tryParse(value.trim());
    if (parsed == null ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.query.isNotEmpty ||
        parsed.fragment.isNotEmpty ||
        (parsed.scheme != 'https' && parsed.scheme != 'http')) {
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

  String get canonicalRegistry => _baseUri.toString();

  Future<ResolveResult> resolve({
    required String namespace,
    required String name,
    required String version,
    required String os,
    required String arch,
    required String abi,
    required String client,
    PullCancellationToken? cancellation,
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
    cancellation?.throwIfCancelled();
    final cancelToken = CancelToken();
    final removeCancelListener = cancellation?.onCancel(
      () => cancelToken.cancel('Installation was cancelled'),
    );
    try {
      final response = await _dio.getUri<Map<String, dynamic>>(
        uri,
        cancelToken: cancelToken,
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
    } on PullCancelledException {
      throw const HubApiException(
        code: 'INSTALL_CANCELLED',
        message: 'Installation was cancelled',
        retryable: false,
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        throw const HubApiException(
          code: 'INSTALL_CANCELLED',
          message: 'Installation was cancelled',
          retryable: false,
        );
      }
      throw _mapDioException(error);
    } on HubApiException {
      rethrow;
    } on Object catch (error) {
      throw HubApiException(
        code: 'HUB_INVALID_RESPONSE',
        message: 'Hub resolve response is invalid: $error',
        retryable: true,
      );
    } finally {
      removeCancelListener?.call();
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
