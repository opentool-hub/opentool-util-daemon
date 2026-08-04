import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:opentool_daemon/src/constants.dart';
import 'package:opentool_daemon/src/hub/hub_client.dart';
import 'package:opentool_daemon/src/service/artifact_downloader.dart';
import 'package:opentool_daemon/src/service/exception.dart';
import 'package:opentool_daemon/src/service/hub_install_service.dart';
import 'package:opentool_daemon/src/service/model.dart';
import 'package:opentool_daemon/src/service/server_service.dart';
import 'package:opentool_daemon/src/service/tool_service.dart';
import 'package:opentool_daemon/src/storage/dao.dart';
import 'package:opentool_daemon/src/utils/platform_detector.dart';
import 'package:opentool_daemon/src/utils/zip_util.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:opentool_dart/opentool_client.dart';

import '../test_doubles.dart';

void main() {
  group('Hub install acceptance', () {
    for (final target in const [
      (os: 'macos', arch: 'arm64', abi: 'native'),
      (os: 'linux', arch: 'arm64', abi: 'glibc'),
    ]) {
      test(
        '${target.os}/${target.arch}/${target.abi} pull persists and survives reconciliation',
        () async {
          final fixture = await _HubFixture.start(target: target);
          try {
            final serverStorage = StubHiveServerStorage();
            final internalStorage = StubHiveInternalServerStorage();
            final service = fixture.installService(
              serverStorage,
              internalStorage,
            );
            final events = <HubInstallEvent>[];

            final installed = await service.install(
              fixture.request,
              onEvent: events.add,
            );

            expect(installed.registry, fixture.registry);
            expect(installed.namespace, 'litevar');
            expect(installed.version, '1.2.3');
            expect(installed.artifactDigest, fixture.artifactDigest);
            expect(installed.platform?.os, target.os);
            expect(installed.platform?.arch, target.arch);
            expect(installed.platform?.abi, target.abi);
            expect(
              events.map((event) => event.data['stage']),
              containsAllInOrder([
                'resolving',
                'downloading',
                'verifying',
                'importing',
                'installed',
              ]),
            );

            final internal = await internalStorage.get(installed.internalId);
            expect(internal, isNotNull);
            expect(await File(internal!.file).exists(), isTrue);
            expect(
              (await ZipUtil.inspect(internal.file)).files,
              contains('tool'),
            );

            final restarted = ServerService(serverStorage, internalStorage);
            await restarted.reconcileInstallations();
            final afterRestart = await restarted.list();
            expect(afterRestart, hasLength(1));
            expect(afterRestart.single.id, installed.id);
            expect(afterRestart.single.artifactDigest, fixture.artifactDigest);
          } finally {
            await fixture.dispose();
          }
        },
      );
    }

    test('invalid entrypoint leaves no artifact or database record', () async {
      final fixture = await _HubFixture.start(
        target: const (os: 'linux', arch: 'arm64', abi: 'glibc'),
        includeEntrypoint: false,
      );
      final serverStorage = StubHiveServerStorage();
      final internalStorage = StubHiveInternalServerStorage();
      try {
        await expectLater(
          fixture
              .installService(serverStorage, internalStorage)
              .install(fixture.request, onEvent: (_) {}),
          throwsA(
            isA<InstallException>().having(
              (error) => error.code,
              'code',
              'ARTIFACT_INVALID',
            ),
          ),
        );

        expect(await serverStorage.list(), isEmpty);
        expect(await internalStorage.list(), isEmpty);
        expect(await _managedFiles(fixture.dataDir), isEmpty);
      } finally {
        await fixture.dispose();
      }
    });

    test('database failure rolls back the copied artifact', () async {
      final fixture = await _HubFixture.start(
        target: const (os: 'linux', arch: 'arm64', abi: 'glibc'),
      );
      final serverStorage = _FailingServerStorage();
      final internalStorage = StubHiveInternalServerStorage();
      try {
        await expectLater(
          fixture
              .installService(serverStorage, internalStorage)
              .install(fixture.request, onEvent: (_) {}),
          throwsA(
            isA<InstallException>().having(
              (error) => error.code,
              'code',
              'DISK_WRITE_FAILED',
            ),
          ),
        );

        expect(await serverStorage.list(), isEmpty);
        expect(await internalStorage.list(), isEmpty);
        expect(await _managedFiles(fixture.dataDir), isEmpty);
      } finally {
        await fixture.dispose();
      }
    });

    test(
      'current platform completes pull, list, run, load, call, stop, and restart list',
      () async {
        final detected = await PlatformDetector().detect();
        final target = (
          os: detected.os,
          arch: detected.arch,
          abi: detected.abi,
        );
        final fixture = await _HubFixture.start(
          target: target,
          toolContent: _runtimeToolSource,
        );
        final serverStorage = StubHiveServerStorage();
        final internalStorage = StubHiveInternalServerStorage();
        final toolStorage = StubHiveToolStorage();
        ToolService? toolService;
        String? toolId;
        try {
          final serverService = ServerService(serverStorage, internalStorage);
          final installed = await fixture
              .installService(serverStorage, internalStorage)
              .install(fixture.request, onEvent: (_) {});
          expect(await serverService.list(), hasLength(1));

          toolService = ToolService(
            toolStorage,
            serverGetter: serverService.get,
            serverLister: serverService.list,
            readyCheckInterval: const Duration(milliseconds: 20),
            readyCheckTimeout: const Duration(seconds: 5),
          );
          final tool = await toolService.runServer(
            installed,
            HostType.LOCALHOST,
            printStd: false,
          );
          toolId = tool.id;
          expect(tool.status, ToolStatusType.RUNNING);

          final definition = await toolService.load(tool.id);
          expect(definition?.info.title, 'Acceptance Tool');
          final result = await toolService.call(
            tool.id,
            FunctionCall(id: 'call-1', name: 'echo', arguments: {'value': 42}),
          );
          expect(result.result, {
            'method': 'echo',
            'params': {'value': 42},
          });

          await toolService.stop(tool.id);
          expect(
            (await toolService.get(tool.id)).status,
            ToolStatusType.NOT_RUNNING,
          );

          final restarted = ServerService(serverStorage, internalStorage);
          await restarted.reconcileInstallations();
          expect(await restarted.list(), hasLength(1));
          expect((await restarted.list()).single.id, installed.id);
        } finally {
          if (toolService != null && toolId != null) {
            try {
              if ((await toolService.get(toolId)).status !=
                  ToolStatusType.NOT_RUNNING) {
                await toolService.stop(toolId);
              }
            } catch (_) {}
          }
          await fixture.dispose();
        }
      },
      skip: Platform.isWindows
          ? 'The generated acceptance executable uses a POSIX shebang'
          : false,
    );
  });
}

class _HubFixture {
  final Directory root;
  final String originalOpenToolPath;
  final String dataDir;
  final HttpServer server;
  final StreamSubscription<HttpRequest> subscription;
  final ({String os, String arch, String abi}) target;
  final List<int> artifactBytes;
  final String artifactDigest;

  _HubFixture({
    required this.root,
    required this.originalOpenToolPath,
    required this.dataDir,
    required this.server,
    required this.subscription,
    required this.target,
    required this.artifactBytes,
    required this.artifactDigest,
  });

  static Future<_HubFixture> start({
    required ({String os, String arch, String abi}) target,
    bool includeEntrypoint = true,
    String toolContent = 'executable',
  }) async {
    final root = await Directory.systemTemp.createTemp('hub_acceptance_');
    final originalOpenToolPath = OPENTOOL_PATH;
    final dataDir = p.join(root.path, '.opentool');
    OPENTOOL_PATH = dataDir;
    final bundle = Directory(p.join(root.path, 'bundle'));
    await bundle.create(recursive: true);
    if (includeEntrypoint) {
      await File(p.join(bundle.path, 'tool')).writeAsString(toolContent);
    }
    await File(p.join(bundle.path, OPENTOOL_FILE_JSON_NAME)).writeAsString(
      jsonEncode({
        'name': 'demo',
        'tag': '1.2.3',
        'os': target.os,
        'cpuArch': target.arch,
        'build': {'args': <String, String>{}, 'runs': <String>[]},
        'run': {
          'envs': <String, String>{},
          'workdir': '.',
          'entrypoint': 'tool',
          'cmds': <String>[],
        },
      }),
    );
    final artifactPath = p.join(root.path, 'demo.ots');
    await ZipUtil.zipDirectory(bundle.path, artifactPath);
    final artifactBytes = await File(artifactPath).readAsBytes();
    final artifactDigest = 'sha256:${sha256.convert(artifactBytes)}';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    late final StreamSubscription<HttpRequest> subscription;
    subscription = server.listen((request) async {
      if (request.uri.path.endsWith('/resolve')) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'tool': {'namespace': 'litevar', 'name': 'demo'},
            'version': '1.2.3',
            'versionDigest': 'sha256:${List.filled(64, 'b').join()}',
            'artifact': {
              'id': 'artifact-${target.os}-${target.arch}-${target.abi}',
              'os': target.os,
              'arch': target.arch,
              'abi': target.abi,
              'fileName': 'demo.ots',
              'mediaType': 'application/vnd.opentool.ots',
              'size': artifactBytes.length,
              'digest': artifactDigest,
              'downloadUrl':
                  'http://${server.address.host}:${server.port}/artifact',
              'downloadUrlExpiresAt': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 5))
                  .toIso8601String(),
            },
          }),
        );
      } else if (request.uri.path == '/artifact') {
        request.response.add(artifactBytes);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    return _HubFixture(
      root: root,
      originalOpenToolPath: originalOpenToolPath,
      dataDir: dataDir,
      server: server,
      subscription: subscription,
      target: target,
      artifactBytes: artifactBytes,
      artifactDigest: artifactDigest,
    );
  }

  String get registry => 'http://${server.address.host}:${server.port}';

  HubInstallRequest get request => HubInstallRequest.validate(
    registry: registry,
    namespace: 'litevar',
    name: 'demo',
    version: '1.2.3',
    client: 'embedded',
  );

  HubInstallService installService(
    StubHiveServerStorage serverStorage,
    StubHiveInternalServerStorage internalStorage,
  ) {
    final serverService = ServerService(serverStorage, internalStorage);
    return HubInstallService(
      serverService: serverService,
      daemonVersion: 'test',
      platformDetector: PlatformDetector(
        operatingSystem: target.os,
        abiName: '${target.os}_${target.arch}',
        environment: target.os == 'linux'
            ? {'OPENTOOL_LINUX_ABI': target.abi}
            : const {},
      ),
      downloader: ArtifactDownloader(dataDir: dataDir),
      hubClientFactory: (baseUrl) => HubClient(baseUrl),
    );
  }

  Future<void> dispose() async {
    await server.close(force: true);
    await subscription.cancel();
    OPENTOOL_PATH = originalOpenToolPath;
    if (await root.exists()) await root.delete(recursive: true);
  }
}

class _FailingServerStorage extends StubHiveServerStorage {
  @override
  Future<void> add(ServerDao serverDao) {
    throw const FileSystemException('simulated database write failure');
  }
}

Future<List<FileSystemEntity>> _managedFiles(String dataDir) async {
  final serverDir = Directory(p.join(dataDir, SERVER_FOLDER));
  final downloadDir = Directory(p.join(dataDir, 'downloads'));
  final files = <FileSystemEntity>[];
  if (await serverDir.exists()) files.addAll(await serverDir.list().toList());
  if (await downloadDir.exists()) {
    files.addAll(await downloadDir.list().toList());
  }
  return files;
}

const _runtimeToolSource = r'''#!/usr/bin/env dart
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  String option(String name, String fallback) {
    final index = args.indexOf('--$name');
    return index >= 0 && index + 1 < args.length ? args[index + 1] : fallback;
  }

  final host = option('opentoolServerHost', '127.0.0.1');
  final port = int.parse(option('opentoolServerPort', '17001'));
  final server = await HttpServer.bind(host, port);
  server.listen((request) async {
    request.response.headers.contentType = ContentType.json;
    final path = request.uri.path;
    if (request.method == 'GET' && path == '/opentool/version') {
      request.response.write(jsonEncode({'version': '1.0.0'}));
    } else if (request.method == 'GET' && path == '/opentool/load') {
      request.response.write(jsonEncode({
        'opentool': '2.0.0',
        'info': {'title': 'Acceptance Tool', 'version': '1.0.0'},
        'functions': <Object>[],
      }));
    } else if (request.method == 'POST' && path == '/opentool/call') {
      final body = jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>;
      request.response.write(jsonEncode({
        'jsonrpc': '2.0',
        'result': {
          'method': body['method'],
          'params': body['params'] ?? <String, dynamic>{},
        },
        'id': body['id'],
      }));
    } else if (request.method == 'POST' && path == '/opentool/stop') {
      request.response.write(jsonEncode({'status': 'stopped'}));
      await request.response.close();
      await server.close(force: true);
      return;
    } else {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write(jsonEncode({'error': 'not found'}));
    }
    await request.response.close();
  });
}
''';
