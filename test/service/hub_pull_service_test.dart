import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:opentool_daemon/src/constants.dart';
import 'package:opentool_daemon/src/hub/hub_client.dart';
import 'package:opentool_daemon/src/service/artifact_downloader.dart';
import 'package:opentool_daemon/src/service/exception.dart';
import 'package:opentool_daemon/src/service/hub_pull_service.dart';
import 'package:opentool_daemon/src/utils/platform_detector.dart';
import 'package:opentool_daemon/src/utils/zip_util.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_doubles.dart';

void main() {
  test('maps deprecated Hub versions to a stable pull error', () async {
    final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final registry = 'http://${httpServer.address.host}:${httpServer.port}';
    final serving = httpServer.listen((request) async {
      request.response.statusCode = HttpStatus.conflict;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'error': {
            'code': 'VERSION_DEPRECATED',
            'message': 'Version is deprecated and cannot be installed',
            'requestId': 'req-deprecated',
          },
        }),
      );
      await request.response.close();
    });
    try {
      final harness = await TestRegistryHarness.create();
      addTearDown(harness.dispose);
      final service = HubPullService(
        serverService: harness.serverService,
        daemonVersion: 'test',
      );
      await expectLater(
        service.pull(
          HubPullRequest.validate(
            registry: registry,
            namespace: 'litevar',
            name: 'deprecated-demo',
            version: '1.0.0',
            client: 'embedded',
          ),
          onEvent: (_) {},
        ),
        throwsA(
          isA<ArtifactOperationException>()
              .having((error) => error.code, 'code', 'TOOL_VERSION_DEPRECATED')
              .having((error) => error.retryable, 'retryable', isFalse),
        ),
      );
    } finally {
      await httpServer.close(force: true);
      await serving.cancel();
    }
  });

  test('pull resolves, verifies, registers, and reuses one artifact', () async {
    final originalOpenToolPath = OPENTOOL_PATH;
    final temp = await Directory.systemTemp.createTemp('hub_pull_test_');
    OPENTOOL_PATH = p.join(temp.path, '.opentool');
    final platform = await PlatformDetector().detect();
    final bundle = Directory(p.join(temp.path, 'bundle'));
    await bundle.create(recursive: true);
    await File(p.join(bundle.path, 'tool')).writeAsString('executable');
    await File(p.join(bundle.path, OPENTOOL_FILE_JSON_NAME)).writeAsString(
      jsonEncode({
        'name': 'demo',
        'tag': '1.2.3',
        'os': platform.os,
        'cpuArch': platform.arch,
        'build': {'args': <String, String>{}, 'runs': <String>[]},
        'run': {
          'envs': <String, String>{},
          'workdir': '.',
          'entrypoint': 'tool',
          'cmds': <String>[],
        },
      }),
    );
    final bundlePath = p.join(temp.path, 'demo.ots');
    await ZipUtil.zipDirectory(bundle.path, bundlePath);
    final bytes = await File(bundlePath).readAsBytes();
    final artifactDigest = 'sha256:${sha256.convert(bytes)}';
    final versionDigest = 'sha256:${List.filled(64, 'b').join()}';
    var advertisedDigest = artifactDigest;
    var resolveCount = 0;
    var downloadCount = 0;
    final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final registry = 'http://${httpServer.address.host}:${httpServer.port}';
    final serving = httpServer.listen((request) async {
      if (request.uri.path.endsWith('/resolve')) {
        resolveCount++;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'tool': {'namespace': 'litevar', 'name': 'demo'},
            'version': '1.2.3',
            'versionDigest': versionDigest,
            'artifact': {
              'id': 'artifact_demo',
              'os': platform.os,
              'arch': platform.arch,
              'abi': platform.abi,
              'fileName': 'demo.ots',
              'mediaType': 'application/vnd.opentool.ots',
              'size': bytes.length,
              'digest': advertisedDigest,
              'downloadUrl': '$registry/artifact',
              'downloadUrlExpiresAt': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 5))
                  .toIso8601String(),
            },
          }),
        );
      } else if (request.uri.path == '/artifact') {
        downloadCount++;
        request.response.add(bytes);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    try {
      final harness = await TestRegistryHarness.create(
        root: Directory(OPENTOOL_PATH),
      );
      final serverService = harness.serverService;
      final pullService = HubPullService(
        serverService: serverService,
        daemonVersion: 'test',
        downloader: ArtifactDownloader(dataDir: OPENTOOL_PATH),
        hubClientFactory: (baseUrl) =>
            HubClient(baseUrl, daemonVersion: 'test'),
      );
      final pullRequest = HubPullRequest.validate(
        registry: registry,
        namespace: 'litevar',
        name: 'demo',
        version: '1.2.3',
        client: 'embedded',
      );
      final firstEvents = <PullEvent>[];
      final secondEvents = <PullEvent>[];
      final first = await pullService.pull(
        pullRequest,
        onEvent: firstEvents.add,
      );
      final second = await pullService.pull(
        pullRequest,
        onEvent: secondEvents.add,
      );
      final third = await pullService.pull(pullRequest, onEvent: (_) {});
      advertisedDigest = 'sha256:${List.filled(64, 'c').join()}';
      await expectLater(
        pullService.pull(pullRequest, onEvent: (_) {}),
        throwsA(
          isA<ArtifactOperationException>().having(
            (error) => error.code,
            'code',
            'ARTIFACT_SOURCE_CONFLICT',
          ),
        ),
      );

      expect(second.id, first.id);
      expect(third.id, first.id);
      expect(first.versionDigest, versionDigest);
      expect(first.artifactDigest, artifactDigest);
      expect(first.platform?.abi, platform.abi);
      expect(await serverService.list(), hasLength(1));
      expect(
        firstEvents.map((event) => event.data['stage']),
        containsAllInOrder([
          'resolving',
          'downloading',
          'verifying',
          'registering',
          'ready',
        ]),
      );
      expect(
        secondEvents.map((event) => event.data['stage']),
        containsAllInOrder(['resolving', 'ready']),
      );
      expect(resolveCount, 4);
      expect(downloadCount, 1);
    } finally {
      await httpServer.close(force: true);
      await serving.cancel();
      OPENTOOL_PATH = originalOpenToolPath;
      await temp.delete(recursive: true);
    }
  });
}
