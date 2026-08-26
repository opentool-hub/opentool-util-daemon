import 'dart:convert';
import 'dart:io';

import 'package:opentool_daemon/src/constants.dart';
import 'package:opentool_daemon/src/service/artifact_registry_service.dart';
import 'package:opentool_daemon/src/service/config.dart';
import 'package:opentool_daemon/src/service/exception.dart';
import 'package:opentool_daemon/src/service/server_service.dart';
import 'package:opentool_daemon/src/storage/artifact_storage.dart';
import 'package:opentool_daemon/src/storage/dao.dart';
import 'package:opentool_daemon/src/utils/platform_detector.dart';
import 'package:opentool_daemon/src/utils/system_util.dart';
import 'package:opentool_daemon/src/utils/zip_util.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_doubles.dart';

void main() {
  group('ServerService', () {
    late Directory root;
    late MemoryStorage<ArtifactDao> artifacts;
    late MemoryStorage<ServerDao> servers;
    late MemoryStorage<ArtifactOperationDao> operations;
    late ArtifactRegistryService registry;
    late ServerService service;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('server_service_test_');
      artifacts = MemoryStorage((value) => value.digest);
      servers = MemoryStorage((value) => value.id);
      operations = MemoryStorage((value) => value.id);
      registry = ArtifactRegistryService(
        content: ArtifactStorage(root.path),
        artifacts: artifacts,
        servers: servers,
        operations: operations,
      );
      service = ServerService(servers, artifactRegistry: registry);
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('list joins canonical Server and Artifact records', () async {
      final file = File(p.join(root.path, 'artifact.ots'));
      await file.writeAsString('artifact');
      final createdAt = DateTime.utc(2026, 8, 3);
      await artifacts.add(
        ArtifactDao(
          digest: _digestA,
          size: 8,
          mediaType: 'application/vnd.opentool.ots',
          platformOs: 'linux',
          platformArch: 'arm64',
          platformAbi: 'glibc',
          filePath: file.path,
          manifestName: 'demo-server',
          manifestVersion: '1.0.0',
          verifiedAt: createdAt,
          createdAt: createdAt,
        ),
      );
      await servers.add(_server(createdAt: createdAt));

      final result = await service.list();

      expect(result, hasLength(1));
      expect(result.single.namespace, 'org/project');
      expect(result.single.version, '1.0.0');
      expect(result.single.artifactSize, 8);
      expect(result.single.platform?.abi, 'glibc');
      expect(result.single.artifactFilePath, file.path);
      expect(result.single.canRun, isTrue);
    });

    test('get throws when the Server does not exist', () async {
      await expectLater(
        service.get('missing'),
        throwsA(isA<ServerNotFoundException>()),
      );
    });

    test('setAlias persists the canonical Server row', () async {
      await servers.add(_server());

      await service.setAlias('srv-1', 'web');

      expect((await servers.get('srv-1'))?.alias, 'web');
    });

    test('import writes only canonical registry records', () async {
      final bundle = await _createTestOtsBundle('import-demo');
      addTearDown(bundle.dispose);

      final imported = await service.import(bundle.zipPath);

      expect(imported.name, 'import-demo');
      expect(imported.namespace, LOCAL_NAMESPACE);
      expect(await servers.list(), hasLength(1));
      expect(await artifacts.list(), hasLength(1));
      expect(await File(imported.artifactFilePath!).exists(), isTrue);
    });

    test('import rejects a platform mismatch before registration', () async {
      final bundle = await _createTestOtsBundle(
        'platform-mismatch',
        os: 'not-${SystemUtil.getOS()}',
      );
      addTearDown(bundle.dispose);

      await expectLater(
        service.import(bundle.zipPath),
        throwsA(
          isA<SystemMismatchException>()
              .having((error) => error.code, 'code', 'PLATFORM_MISMATCH')
              .having((error) => error.retryable, 'retryable', isFalse)
              .having(
                (error) => error.message,
                'message',
                allOf(
                  contains('not-${SystemUtil.getOS()}'),
                  contains(SystemUtil.getOS()),
                  contains('Import an .ots file built for'),
                ),
              ),
        ),
      );
      expect(await servers.list(), isEmpty);
      expect(await artifacts.list(), isEmpty);
    });

    test('build embeds the detected ABI in the artifact manifest', () async {
      final source = Directory(p.join(root.path, 'build-source'));
      final dist = Directory(p.join(source.path, 'dist'));
      await dist.create(recursive: true);
      await File(p.join(source.path, 'Opentoolfile')).writeAsString('''
WORKDIR dist
ENTRYPOINT ["run.sh"]
''');
      await File(p.join(dist.path, 'run.sh')).writeAsString('#!/bin/sh\n');
      final buildService = ServerService(
        servers,
        artifactRegistry: registry,
        platformDetector: PlatformDetector(
          operatingSystem: 'linux',
          abiName: 'linux_arm64',
          environment: const {'OPENTOOL_LINUX_ABI': 'musl'},
        ),
      );

      await buildService.buildServer(
        p.join(source.path, 'Opentoolfile'),
        'abi-demo',
        '1.0.0',
        (_, _) {},
        () {},
      );

      final stored = (await artifacts.list()).single;
      final inspection = await ZipUtil.inspect(stored.filePath);
      expect(inspection.manifest['os'], 'linux');
      expect(inspection.manifest['cpuArch'], 'arm64');
      expect(inspection.manifest['abi'], 'musl');
      expect(stored.platformAbi, 'musl');

      final built = (await buildService.list()).single;
      final exportDirectory = Directory(p.join(root.path, 'exports'));
      await exportDirectory.create();
      await buildService.export(built.id, exportDirectory.path);
      expect(
        await File(
          p.join(
            exportDirectory.path,
            'local-abi-demo-1.0.0-linux-arm64-musl.ots',
          ),
        ).exists(),
        isTrue,
      );
    });

    test('treats a legacy Linux manifest as glibc', () async {
      final bundle = await _createTestOtsBundle(
        'legacy-glibc',
        os: 'linux',
        cpuArch: 'arm64',
      );
      addTearDown(bundle.dispose);
      final importService = ServerService(
        servers,
        artifactRegistry: registry,
        platformDetector: PlatformDetector(
          operatingSystem: 'linux',
          abiName: 'linux_arm64',
          environment: const {'OPENTOOL_LINUX_ABI': 'glibc'},
        ),
      );

      final imported = await importService.import(bundle.zipPath);

      expect(imported.platform?.abi, 'glibc');
      expect((await artifacts.list()).single.platformAbi, 'glibc');
    });

    test('does not reinterpret a legacy Linux manifest as musl', () async {
      final bundle = await _createTestOtsBundle(
        'legacy-musl',
        os: 'linux',
        cpuArch: 'arm64',
      );
      addTearDown(bundle.dispose);
      final importService = ServerService(
        servers,
        artifactRegistry: registry,
        platformDetector: PlatformDetector(
          operatingSystem: 'linux',
          abiName: 'linux_arm64',
          environment: const {'OPENTOOL_LINUX_ABI': 'musl'},
        ),
      );

      await expectLater(
        importService.import(bundle.zipPath),
        throwsA(isA<SystemMismatchException>()),
      );
    });

    test('delete removes the last Artifact reference and content', () async {
      final bundle = await _createTestOtsBundle('delete-demo');
      addTearDown(bundle.dispose);
      final imported = await service.import(bundle.zipPath);
      final contentPath = imported.artifactFilePath!;

      await service.delete(imported.id);

      expect(await servers.list(), isEmpty);
      expect(await artifacts.list(), isEmpty);
      expect(await File(contentPath).exists(), isFalse);
    });
  });
}

const _digestA =
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

ServerDao _server({DateTime? createdAt}) => ServerDao(
  id: 'srv-1',
  alias: 'alpha',
  namespace: 'org/project',
  name: 'demo-server',
  version: '1.0.0',
  artifactDigest: _digestA,
  sourceKind: 'hub',
  sourceKey: 'hub.local/org/project/demo-server:1.0.0',
  registry: 'hub.local',
  protected: false,
  managedBy: 'user',
  state: 'available',
  createdAt: createdAt ?? DateTime.utc(2026, 8, 3),
);

Future<_TestOtsBundle> _createTestOtsBundle(
  String name, {
  String? tag,
  String? os,
  String? cpuArch,
}) async {
  final rootDir = await Directory.systemTemp.createTemp('ots_bundle_');
  final contentDir = Directory(p.join(rootDir.path, 'content'));
  await contentDir.create(recursive: true);
  final config = OpentoolfileConfig(
    name: name,
    tag: tag,
    os: os ?? SystemUtil.getOS(),
    cpuArch: cpuArch ?? SystemUtil.getCpuArch(),
    build: OpenToolBuild(args: const {}, runs: const []),
    run: OpenToolRun(
      envs: const {},
      workdir: '.',
      entrypoint: 'run.sh',
      cmds: const [],
    ),
  );
  await File(
    p.join(contentDir.path, OPENTOOL_FILE_JSON_NAME),
  ).writeAsString(jsonEncode(config.toJson()));
  await File(p.join(contentDir.path, 'run.sh')).writeAsString('#!/bin/sh');
  final zipPath = p.join(rootDir.path, 'bundle.ots');
  await ZipUtil.zipDirectory(contentDir.path, zipPath);
  return _TestOtsBundle(zipPath, rootDir);
}

class _TestOtsBundle {
  final String zipPath;
  final Directory rootDir;

  _TestOtsBundle(this.zipPath, this.rootDir);

  Future<void> dispose() async {
    if (await rootDir.exists()) await rootDir.delete(recursive: true);
  }
}
