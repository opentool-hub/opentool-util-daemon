import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:opentool_daemon/src/service/artifact_downloader.dart';
import 'package:opentool_daemon/src/service/exception.dart';
import 'package:opentool_daemon/src/service/install_cancellation.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('cancels an in-flight download and removes the partial file', () async {
    final stopwatch = Stopwatch()..start();
    final temp = await Directory.systemTemp.createTemp('downloader_cancel_');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = server.listen((request) async {
      request.response.bufferOutput = false;
      request.response.add([1]);
      await request.response.flush();
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        try {
          request.response.add([2]);
          await request.response.flush();
        } catch (_) {
          return;
        }
      }
      await request.response.close();
    });
    final cancellation = InstallCancellationToken();
    try {
      await expectLater(
        ArtifactDownloader(dataDir: temp.path).download(
          downloadUrl: 'http://${server.address.host}:${server.port}/artifact',
          expectedSize: 100,
          expectedDigest: 'sha256:${List.filled(64, '0').join()}',
          onProgress: (_, _) => cancellation.cancel(),
          onVerifying: () {},
          cancellation: cancellation,
        ),
        throwsA(
          isA<InstallException>().having(
            (error) => error.code,
            'code',
            'INSTALL_CANCELLED',
          ),
        ),
      );
      final downloads = Directory(p.join(temp.path, 'downloads'));
      expect(await downloads.list().toList(), isEmpty);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    } finally {
      await server.close(force: true);
      await serving.cancel();
      await temp.delete(recursive: true);
    }
  });

  test(
    'downloads through a safe redirect and verifies size and digest',
    () async {
      final temp = await Directory.systemTemp.createTemp('downloader_test_');
      final bytes = [1, 2, 3, 4];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serving = server.listen((request) async {
        if (request.uri.path == '/redirect') {
          request.response.statusCode = HttpStatus.temporaryRedirect;
          request.response.headers.set(HttpHeaders.locationHeader, '/artifact');
        } else {
          request.response.add(bytes);
        }
        await request.response.close();
      });
      try {
        final progress = <int>[];
        var verifying = false;
        final result = await ArtifactDownloader(dataDir: temp.path).download(
          downloadUrl: 'http://${server.address.host}:${server.port}/redirect',
          expectedSize: bytes.length,
          expectedDigest: 'sha256:${sha256.convert(bytes)}',
          onProgress: (downloaded, _) => progress.add(downloaded),
          onVerifying: () => verifying = true,
        );

        expect(await File(result).readAsBytes(), bytes);
        expect(progress.last, bytes.length);
        expect(verifying, isTrue);
      } finally {
        await server.close(force: true);
        await serving.cancel();
        await temp.delete(recursive: true);
      }
    },
  );

  for (final mismatch in [
    (
      name: 'digest mismatch',
      expectedSize: 4,
      digest: 'sha256:${List.filled(64, '0').join()}',
      code: 'ARTIFACT_DIGEST_MISMATCH',
    ),
    (
      name: 'oversized response',
      expectedSize: 3,
      digest: 'sha256:${sha256.convert([1, 2, 3, 4])}',
      code: 'ARTIFACT_SIZE_MISMATCH',
    ),
    (
      name: 'truncated response',
      expectedSize: 5,
      digest: 'sha256:${sha256.convert([1, 2, 3, 4])}',
      code: 'ARTIFACT_SIZE_MISMATCH',
    ),
  ]) {
    test('${mismatch.name} removes the partial download', () async {
      final temp = await Directory.systemTemp.createTemp('downloader_test_');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serving = server.listen((request) async {
        request.response.add([1, 2, 3, 4]);
        await request.response.close();
      });
      try {
        final downloader = ArtifactDownloader(dataDir: temp.path);
        await expectLater(
          downloader.download(
            downloadUrl:
                'http://${server.address.host}:${server.port}/artifact',
            expectedSize: mismatch.expectedSize,
            expectedDigest: mismatch.digest,
            onProgress: (_, _) {},
            onVerifying: () {},
          ),
          throwsA(
            isA<InstallException>().having(
              (error) => error.code,
              'code',
              mismatch.code,
            ),
          ),
        );
        final downloads = Directory(p.join(temp.path, 'downloads'));
        expect(await downloads.list().toList(), isEmpty);
      } finally {
        await server.close(force: true);
        await serving.cancel();
        await temp.delete(recursive: true);
      }
    });
  }

  test('rejects URLs containing credentials', () async {
    final temp = await Directory.systemTemp.createTemp('downloader_test_');
    try {
      await expectLater(
        ArtifactDownloader(dataDir: temp.path).download(
          downloadUrl: 'https://user:secret@objects.example/artifact.ots',
          expectedSize: 1,
          expectedDigest: 'sha256:${List.filled(64, '0').join()}',
          onProgress: (_, _) {},
          onVerifying: () {},
        ),
        throwsA(
          isA<InstallException>().having(
            (error) => error.code,
            'code',
            'ARTIFACT_DOWNLOAD_FAILED',
          ),
        ),
      );
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('maps an interrupted response and removes the partial file', () async {
    final temp = await Directory.systemTemp.createTemp('downloader_test_');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = server.listen((request) async {
      request.response.contentLength = 8;
      final socket = await request.response.detachSocket();
      socket.add([1, 2, 3, 4]);
      await socket.flush();
      socket.destroy();
    });
    try {
      await expectLater(
        ArtifactDownloader(dataDir: temp.path).download(
          downloadUrl: 'http://${server.address.host}:${server.port}/artifact',
          expectedSize: 8,
          expectedDigest: 'sha256:${List.filled(64, '0').join()}',
          onProgress: (_, _) {},
          onVerifying: () {},
        ),
        throwsA(
          isA<InstallException>().having(
            (error) => error.code,
            'code',
            anyOf('ARTIFACT_DOWNLOAD_FAILED', 'ARTIFACT_SIZE_MISMATCH'),
          ),
        ),
      );
      final downloads = Directory(p.join(temp.path, 'downloads'));
      expect(await downloads.list().toList(), isEmpty);
    } finally {
      await server.close(force: true);
      await serving.cancel();
      await temp.delete(recursive: true);
    }
  });

  test('maps an unwritable download directory to DISK_WRITE_FAILED', () async {
    final temp = await Directory.systemTemp.createTemp('downloader_test_');
    final dataFile = File(p.join(temp.path, 'not-a-directory'));
    await dataFile.writeAsString('occupied');
    try {
      await expectLater(
        ArtifactDownloader(dataDir: dataFile.path).download(
          downloadUrl: 'http://127.0.0.1:1/artifact',
          expectedSize: 1,
          expectedDigest: 'sha256:${List.filled(64, '0').join()}',
          onProgress: (_, _) {},
          onVerifying: () {},
        ),
        throwsA(
          isA<InstallException>().having(
            (error) => error.code,
            'code',
            'DISK_WRITE_FAILED',
          ),
        ),
      );
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
