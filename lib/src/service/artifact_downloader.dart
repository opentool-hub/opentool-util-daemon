import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:unique_id_dart/unique_id_dart.dart';

import 'exception.dart';

class ArtifactDownloader {
  final Dio _dio;
  final String dataDir;
  final bool allowInsecureDownload;

  ArtifactDownloader({
    required this.dataDir,
    Dio? dio,
    this.allowInsecureDownload = false,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(minutes: 5),
             ),
           );

  Future<String> download({
    required String downloadUrl,
    required int expectedSize,
    required String expectedDigest,
    required void Function(int downloadedBytes, int totalBytes) onProgress,
    required void Function() onVerifying,
  }) async {
    final uri = Uri.tryParse(downloadUrl);
    if (uri == null || !_isAllowedUri(uri)) {
      throw const InstallException(
        code: 'ARTIFACT_DOWNLOAD_FAILED',
        message: 'Hub returned an invalid artifact download URL',
        retryable: true,
      );
    }
    if (expectedSize <= 0 ||
        !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(expectedDigest)) {
      throw const InstallException(
        code: 'HUB_INVALID_RESPONSE',
        message: 'Hub returned invalid artifact integrity metadata',
        retryable: true,
      );
    }

    final downloadDirectory = Directory(p.join(dataDir, 'downloads'));
    final partFile = File(p.join(downloadDirectory.path, '${uniqueId()}.part'));
    IOSink? sink;
    var completed = false;
    try {
      await downloadDirectory.create(recursive: true);
      final response = await _getFollowingSafeRedirects(uri);
      final body = response.data;
      if (body == null) {
        throw const InstallException(
          code: 'ARTIFACT_DOWNLOAD_FAILED',
          message: 'Artifact response body is empty',
          retryable: true,
        );
      }
      sink = partFile.openWrite(mode: FileMode.writeOnly);
      var downloaded = 0;
      await for (final chunk in body.stream) {
        downloaded += chunk.length;
        if (downloaded > expectedSize) {
          throw InstallException(
            code: 'ARTIFACT_SIZE_MISMATCH',
            message:
                'Downloaded artifact is larger than the Hub metadata ($expectedSize bytes)',
            retryable: true,
          );
        }
        sink.add(chunk);
        onProgress(downloaded, expectedSize);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (downloaded != expectedSize) {
        throw InstallException(
          code: 'ARTIFACT_SIZE_MISMATCH',
          message:
              'Downloaded artifact size $downloaded does not match Hub metadata $expectedSize',
          retryable: true,
        );
      }
      onVerifying();
      final digest = await sha256.bind(partFile.openRead()).first;
      final actualDigest = 'sha256:$digest';
      if (actualDigest != expectedDigest) {
        throw const InstallException(
          code: 'ARTIFACT_DIGEST_MISMATCH',
          message: 'Downloaded artifact digest does not match Hub metadata',
          retryable: true,
        );
      }
      completed = true;
      return partFile.path;
    } on InstallException {
      rethrow;
    } on FileSystemException catch (error) {
      throw InstallException(
        code: 'DISK_WRITE_FAILED',
        message: 'Unable to write the artifact: ${error.message}',
        retryable: true,
      );
    } on IOException {
      throw const InstallException(
        code: 'ARTIFACT_DOWNLOAD_FAILED',
        message: 'Artifact download was interrupted',
        retryable: true,
      );
    } on DioException catch (error) {
      throw InstallException(
        code: 'ARTIFACT_DOWNLOAD_FAILED',
        message: error.response?.statusCode == null
            ? 'Artifact download failed'
            : 'Artifact download failed with status ${error.response?.statusCode}',
        retryable: true,
      );
    } finally {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      if (!completed && await partFile.exists()) await partFile.delete();
    }
  }

  bool _isAllowedUri(Uri uri) =>
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      uri.fragment.isEmpty &&
      (uri.scheme == 'https' ||
          (uri.scheme == 'http' &&
              (allowInsecureDownload || _isLoopbackHost(uri.host))));

  bool _isLoopbackHost(String host) {
    final normalized = host.toLowerCase();
    return normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '::1' ||
        normalized.endsWith('.localhost');
  }

  Future<Response<ResponseBody>> _getFollowingSafeRedirects(Uri initial) async {
    var current = initial;
    for (var redirects = 0; redirects <= 5; redirects++) {
      final response = await _dio.getUri<ResponseBody>(
        current,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
          headers: const {'Accept': 'application/vnd.opentool.ots'},
        ),
      );
      final status = response.statusCode ?? 0;
      if (status < 300) return response;

      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.data?.stream.drain<void>();
      if (location == null || redirects == 5) {
        throw const InstallException(
          code: 'ARTIFACT_DOWNLOAD_FAILED',
          message: 'Artifact download returned an invalid redirect',
          retryable: true,
        );
      }
      final redirected = current.resolve(location);
      if (!_isAllowedUri(redirected) ||
          (current.scheme == 'https' && redirected.scheme != 'https')) {
        throw const InstallException(
          code: 'ARTIFACT_DOWNLOAD_FAILED',
          message: 'Artifact download redirect is not secure',
          retryable: true,
        );
      }
      current = redirected;
    }
    throw const InstallException(
      code: 'ARTIFACT_DOWNLOAD_FAILED',
      message: 'Artifact download exceeded the redirect limit',
      retryable: true,
    );
  }
}
