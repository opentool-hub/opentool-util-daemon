import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:unique_id_dart/unique_id_dart.dart';

import 'exception.dart';
import 'pull_cancellation.dart';

class ArtifactDownloader {
  final Dio? _providedDio;
  final String dataDir;

  ArtifactDownloader({required this.dataDir, Dio? dio}) : _providedDio = dio;

  Future<String> download({
    required String downloadUrl,
    required int expectedSize,
    required String expectedDigest,
    required void Function(int downloadedBytes, int totalBytes) onProgress,
    required void Function() onVerifying,
    PullCancellationToken? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final uri = Uri.tryParse(downloadUrl);
    if (uri == null || !_isAllowedUri(uri)) {
      throw const ArtifactOperationException(
        code: 'ARTIFACT_DOWNLOAD_FAILED',
        message: 'Hub returned an invalid artifact download URL',
        retryable: true,
      );
    }
    if (expectedSize <= 0 ||
        !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(expectedDigest)) {
      throw const ArtifactOperationException(
        code: 'HUB_INVALID_RESPONSE',
        message: 'Hub returned invalid artifact integrity metadata',
        retryable: true,
      );
    }

    final downloadDirectory = Directory(p.join(dataDir, 'downloads'));
    final partFile = File(p.join(downloadDirectory.path, '${uniqueId()}.part'));
    IOSink? sink;
    var completed = false;
    final dio =
        _providedDio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(minutes: 5),
          ),
        );
    final cancelToken = CancelToken();
    final removeCancelListener = cancellation?.onCancel(() {
      cancelToken.cancel('Installation was cancelled');
      dio.close(force: true);
    });
    try {
      await downloadDirectory.create(recursive: true);
      cancellation?.throwIfCancelled();
      final response = await _getFollowingSafeRedirects(dio, uri, cancelToken);
      final body = response.data;
      if (body == null) {
        throw const ArtifactOperationException(
          code: 'ARTIFACT_DOWNLOAD_FAILED',
          message: 'Artifact response body is empty',
          retryable: true,
        );
      }
      sink = partFile.openWrite(mode: FileMode.writeOnly);
      var downloaded = 0;
      final iterator = StreamIterator<List<int>>(body.stream);
      final removeBodyCancelListener = cancellation?.onCancel(
        () => unawaited(iterator.cancel()),
      );
      try {
        while (await iterator.moveNext()) {
          cancellation?.throwIfCancelled();
          final chunk = iterator.current;
          downloaded += chunk.length;
          if (downloaded > expectedSize) {
            throw ArtifactOperationException(
              code: 'ARTIFACT_SIZE_MISMATCH',
              message:
                  'Downloaded artifact is larger than the Hub metadata ($expectedSize bytes)',
              retryable: true,
            );
          }
          sink.add(chunk);
          onProgress(downloaded, expectedSize);
          cancellation?.throwIfCancelled();
        }
        cancellation?.throwIfCancelled();
      } finally {
        removeBodyCancelListener?.call();
        if (cancellation?.isCancelled ?? false) {
          unawaited(iterator.cancel());
        } else {
          await iterator.cancel();
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (downloaded != expectedSize) {
        throw ArtifactOperationException(
          code: 'ARTIFACT_SIZE_MISMATCH',
          message:
              'Downloaded artifact size $downloaded does not match Hub metadata $expectedSize',
          retryable: true,
        );
      }
      onVerifying();
      cancellation?.throwIfCancelled();
      final digest = await sha256.bind(partFile.openRead()).first;
      cancellation?.throwIfCancelled();
      final actualDigest = 'sha256:$digest';
      if (actualDigest != expectedDigest) {
        throw const ArtifactOperationException(
          code: 'ARTIFACT_DIGEST_MISMATCH',
          message: 'Downloaded artifact digest does not match Hub metadata',
          retryable: true,
        );
      }
      completed = true;
      return partFile.path;
    } on PullCancelledException {
      throw const ArtifactOperationException(
        code: 'INSTALL_CANCELLED',
        message: 'Installation was cancelled',
        retryable: false,
      );
    } on ArtifactOperationException {
      rethrow;
    } on FileSystemException catch (error) {
      throw ArtifactOperationException(
        code: 'DISK_WRITE_FAILED',
        message: 'Unable to write the artifact: ${error.message}',
        retryable: true,
      );
    } on IOException {
      if (cancellation?.isCancelled ?? false) {
        throw const ArtifactOperationException(
          code: 'INSTALL_CANCELLED',
          message: 'Installation was cancelled',
          retryable: false,
        );
      }
      throw const ArtifactOperationException(
        code: 'ARTIFACT_DOWNLOAD_FAILED',
        message: 'Artifact download was interrupted',
        retryable: true,
      );
    } on DioException catch (error) {
      if ((cancellation?.isCancelled ?? false) || CancelToken.isCancel(error)) {
        throw const ArtifactOperationException(
          code: 'INSTALL_CANCELLED',
          message: 'Installation was cancelled',
          retryable: false,
        );
      }
      throw ArtifactOperationException(
        code: 'ARTIFACT_DOWNLOAD_FAILED',
        message: error.response?.statusCode == null
            ? 'Artifact download failed'
            : 'Artifact download failed with status ${error.response?.statusCode}',
        retryable: true,
      );
    } finally {
      removeCancelListener?.call();
      if (_providedDio == null && !(cancellation?.isCancelled ?? false)) {
        dio.close();
      }
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
      (uri.scheme == 'https' || uri.scheme == 'http');

  Future<Response<ResponseBody>> _getFollowingSafeRedirects(
    Dio dio,
    Uri initial,
    CancelToken cancelToken,
  ) async {
    var current = initial;
    for (var redirects = 0; redirects <= 5; redirects++) {
      final response = await dio.getUri<ResponseBody>(
        current,
        cancelToken: cancelToken,
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
        throw const ArtifactOperationException(
          code: 'ARTIFACT_DOWNLOAD_FAILED',
          message: 'Artifact download returned an invalid redirect',
          retryable: true,
        );
      }
      final redirected = current.resolve(location);
      if (!_isAllowedUri(redirected)) {
        throw const ArtifactOperationException(
          code: 'ARTIFACT_DOWNLOAD_FAILED',
          message: 'Artifact download redirect is invalid',
          retryable: true,
        );
      }
      current = redirected;
    }
    throw const ArtifactOperationException(
      code: 'ARTIFACT_DOWNLOAD_FAILED',
      message: 'Artifact download exceeded the redirect limit',
      retryable: true,
    );
  }
}
