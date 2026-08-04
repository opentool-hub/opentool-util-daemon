import 'dart:convert';
import 'dart:io';
import 'package:opentool_daemon/src/constants.dart';
import 'package:opentool_daemon/src/service/exception.dart';
import 'package:opentool_daemon/src/service/config.dart';
import 'package:opentool_daemon/src/service/model.dart';
import 'package:opentool_daemon/src/service/server_service.dart';
import 'package:opentool_daemon/src/storage/dao.dart';
import 'package:opentool_daemon/src/storage/cache_storage.dart';
import 'package:opentool_daemon/src/utils/system_util.dart';
import 'package:opentool_daemon/src/utils/zip_util.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import '../test_doubles.dart';

void main() {
  group('ServerService', () {
    late StubHiveServerStorage hiveServerStorage;
    late StubHiveInternalServerStorage internalStorage;
    late ServerService service;

    setUp(() {
      hiveServerStorage = StubHiveServerStorage();
      internalStorage = StubHiveInternalServerStorage();
      hiveServerStorage.seed([
        ServerDao(
          id: 'srv-1',
          alias: 'alpha',
          registry: 'hub.local',
          repo: 'org/project',
          name: 'demo-server',
          tag: 'latest',
          internalId: 'int-1',
          artifactDigest: 'sha256:${List.filled(64, 'a').join()}',
          artifactMediaType: 'application/vnd.opentool.ots',
          artifactSize: 1234,
          platformOs: 'linux',
          platformArch: 'arm64',
          platformAbi: 'glibc',
          installedAt: DateTime.utc(2026, 8, 3),
        ),
        ServerDao(
          id: 'srv-dup',
          alias: 'gamma',
          registry: 'hub.local',
          repo: 'org/project',
          name: 'demo-server',
          tag: 'stable',
          internalId: 'int-1',
        ),
        ServerDao(
          id: 'srv-2',
          alias: 'beta',
          registry: 'hub.local',
          repo: 'org/project',
          name: 'demo-server',
          tag: 'dev',
          internalId: 'int-2',
        ),
      ]);
      service = ServerService(hiveServerStorage, internalStorage);
    });

    test('list returns server models populated from storage', () async {
      final servers = await service.list();

      expect(servers, hasLength(3));
      expect(servers.first.name, equals('demo-server'));
      expect(servers.first.tag, equals('latest'));
    });

    test('get returns a single server model', () async {
      final server = await service.get('srv-1');

      expect(server.id, equals('srv-1'));
      expect(server.alias, equals('alpha'));
    });

    test('get throws when the server does not exist', () async {
      expect(
        () => service.get('missing'),
        throwsA(isA<ServerNotFoundException>()),
      );
    });

    test('setAlias persists the alias change', () async {
      await service.setAlias('srv-1', 'web');
      final updated = await service.get('srv-1');

      expect(updated.alias, equals('web'));
    });

    test('tag returns existing version without retagging the source', () async {
      await service.list(); // warm cache with every server entry
      final server = await service.tag('srv-1', 'stable');

      expect(server.id, equals('srv-dup'));
      expect(server.tag, equals('stable'));
      expect(server.artifactDigest, serviceMetadataDigest);
      expect(server.artifactMediaType, 'application/vnd.opentool.ots');
      expect(server.artifactSize, 1234);
      expect(server.platform?.abi, 'glibc');
      expect(server.installedAt, DateTime.utc(2026, 8, 3));

      final servers = await service.list();
      expect(servers.where((s) => s.tag == 'stable'), hasLength(1));
      expect(servers.firstWhere((s) => s.id == 'srv-1').tag, equals('latest'));
    });

    test('tag creates a new version without retagging the source', () async {
      final serversBefore = await service.list();
      final server = await service.tag('srv-1', 'beta');
      final serversAfter = await service.list();

      expect(server.id, isNot(equals('srv-1')));
      expect(server.tag, equals('beta'));
      expect(server.artifactDigest, serviceMetadataDigest);
      expect(server.artifactMediaType, 'application/vnd.opentool.ots');
      expect(server.artifactSize, 1234);
      expect(server.platform?.abi, 'glibc');
      expect(server.installedAt, DateTime.utc(2026, 8, 3));
      expect(serversAfter.length, equals(serversBefore.length + 1));
      expect(serversAfter.where((s) => s.tag == 'beta'), hasLength(1));
      expect(serversAfter.firstWhere((s) => s.id == 'srv-1').tag, 'latest');
    });

    test(
      'removeServersByNameAndTagForTest drops duplicates and artifacts',
      () async {
        final keepServer = ServerDao(
          id: 'srv-keep',
          alias: 'keep',
          registry: 'hub.local',
          repo: 'org/project',
          name: 'demo-server',
          tag: 'latest',
          internalId: 'int-keep',
        );
        final duplicate = ServerDao(
          id: 'srv-old',
          alias: 'old',
          registry: 'hub.local',
          repo: 'org/project',
          name: 'demo-server',
          tag: 'latest',
          internalId: 'int-old',
        );
        hiveServerStorage.seed([keepServer, duplicate]);
        internalStorage.seed([
          InternalServerDao(id: 'int-keep', file: '/tmp/keep.ots'),
          InternalServerDao(id: 'int-old', file: '/tmp/old.ots'),
        ]);

        final duplicateFile = File(
          '$OPENTOOL_PATH${Platform.pathSeparator}$SERVER_FOLDER${Platform.pathSeparator}${duplicate.name}-${duplicate.internalId}.ots',
        );
        await duplicateFile.create(recursive: true);

        final service = ServerService(hiveServerStorage, internalStorage);
        await service.list(); // warm cache

        await service.removeServersByNameAndTagForTest(
          'demo-server',
          'latest',
          excludeServerId: 'srv-keep',
        );

        final servers = await service.list();
        expect(servers.where((s) => s.tag == 'latest'), hasLength(1));
        expect(await duplicateFile.exists(), isFalse);
        expect(await internalStorage.get('int-old'), isNull);
      },
    );

    test('import preserves native server id for the same identity', () async {
      hiveServerStorage = StubHiveServerStorage();
      internalStorage = StubHiveInternalServerStorage();
      final existingServer = ServerDao(
        id: 'srv-old',
        alias: 'old',
        registry: NULL_REGISTRY,
        repo: NULL_REPO,
        name: 'import-demo',
        tag: NULL_TAG,
        internalId: 'int-old',
      );
      hiveServerStorage.seed([existingServer]);
      final oldFilePath = _serverOtsFilePath(
        existingServer.name,
        existingServer.internalId,
      );
      await File(oldFilePath).parent.create(recursive: true);
      await File(oldFilePath).writeAsString('old');
      internalStorage.seed([
        InternalServerDao(id: existingServer.internalId, file: oldFilePath),
      ]);

      final service = ServerService(hiveServerStorage, internalStorage);
      final bundle = await _createTestOtsBundle(existingServer.name);

      final imported = await service.import(bundle.zipPath);
      final servers = await service.list();
      final matching = servers
          .where((s) => s.name == existingServer.name && s.tag == NULL_TAG)
          .toList();

      expect(matching, hasLength(1));
      expect(imported.id, equals(existingServer.id));
      expect(matching.single.id, equals(existingServer.id));
      expect(await hiveServerStorage.get(existingServer.id), isNotNull);
      expect(await internalStorage.get(existingServer.internalId), isNull);
      expect(await File(oldFilePath).exists(), isFalse);

      final newFilePath = _serverOtsFilePath(
        imported.name,
        imported.internalId,
      );
      expect(await File(newFilePath).exists(), isTrue);

      await bundle.dispose();
      await File(newFilePath).delete();
    });

    test('identity consolidation migrates ToolDao server references', () async {
      hiveServerStorage = StubHiveServerStorage();
      internalStorage = StubHiveInternalServerStorage();
      final toolHive = StubHiveToolStorage();
      final toolStorage = CacheToolStorage(toolHive);
      hiveServerStorage.seed([
        ServerDao(
          id: 'srv-a',
          alias: 'srv-a',
          registry: NULL_REGISTRY,
          repo: NULL_REPO,
          name: 'identity-demo',
          tag: '1.0.0',
          internalId: 'int-a',
        ),
        ServerDao(
          id: 'srv-b',
          alias: 'srv-b',
          registry: NULL_REGISTRY,
          repo: NULL_REPO,
          name: 'identity-demo',
          tag: '1.0.0',
          internalId: 'int-b',
        ),
      ]);
      internalStorage.seed([
        InternalServerDao(id: 'int-a', file: '/tmp/int-a.ots'),
        InternalServerDao(id: 'int-b', file: '/tmp/int-b.ots'),
      ]);
      toolHive.seed([
        ToolDao(
          id: 'tool-b',
          alias: 'tool-b',
          tag: '1.0.0',
          host: '127.0.0.1',
          port: 9010,
          apiKey: 'key',
          status: ToolStatusType.RUNNING,
          serverId: 'srv-b',
        ),
      ]);
      final service = ServerService(
        hiveServerStorage,
        internalStorage,
        toolStorage: toolStorage,
      );
      final bundle = await _createTestOtsBundle('identity-demo', tag: '1.0.0');

      final imported = await service.import(bundle.zipPath);

      expect(imported.id, 'srv-a');
      expect((await toolHive.get('tool-b'))!.serverId, 'srv-a');
      expect((await toolHive.get('tool-b'))!.serverName, 'identity-demo');
      expect(await hiveServerStorage.get('srv-b'), isNull);

      final importedFile = File(
        _serverOtsFilePath(imported.name, imported.internalId),
      );
      await bundle.dispose();
      if (await importedFile.exists()) await importedFile.delete();
    });

    test('import picks tag from Opentoolfile.json when present', () async {
      hiveServerStorage = StubHiveServerStorage();
      internalStorage = StubHiveInternalServerStorage();
      final service = ServerService(hiveServerStorage, internalStorage);

      final bundle = await _createTestOtsBundle(
        'import-tag-demo',
        tag: '1.2.3',
      );

      final imported = await service.import(bundle.zipPath);
      expect(imported.tag, equals('1.2.3'));

      final servers = await service.list();
      expect(
        servers.where((s) => s.name == 'import-tag-demo' && s.tag == '1.2.3'),
        hasLength(1),
      );

      final newFilePath = _serverOtsFilePath(
        imported.name,
        imported.internalId,
      );
      expect(await File(newFilePath).exists(), isTrue);

      await bundle.dispose();
      await File(newFilePath).delete();
    });

    group('import platform matching', () {
      final nativeOs = SystemUtil.getOS();
      final nativeCpuArch = SystemUtil.getCpuArch();
      const otherOs = 'test-os';
      const otherCpuArch = 'test-cpu';

      test('allows import when os and cpuArch match', () async {
        hiveServerStorage = StubHiveServerStorage();
        internalStorage = StubHiveInternalServerStorage();
        final service = ServerService(hiveServerStorage, internalStorage);
        final bundle = await _createTestOtsBundle(
          'platform-match-demo',
          os: nativeOs,
          cpuArch: nativeCpuArch,
        );

        final imported = await service.import(bundle.zipPath);

        expect(imported.name, equals('platform-match-demo'));

        final newFilePath = _serverOtsFilePath(
          imported.name,
          imported.internalId,
        );
        expect(await File(newFilePath).exists(), isTrue);

        await bundle.dispose();
        await File(newFilePath).delete();
      });

      test('rejects import when os differs and cpuArch matches', () async {
        hiveServerStorage = StubHiveServerStorage();
        internalStorage = StubHiveInternalServerStorage();
        final service = ServerService(hiveServerStorage, internalStorage);
        final bundle = await _createTestOtsBundle(
          'platform-os-mismatch-demo',
          os: otherOs,
          cpuArch: nativeCpuArch,
        );

        await expectLater(
          () => service.import(bundle.zipPath),
          throwsA(isA<SystemMismatchException>()),
        );

        await bundle.dispose();
      });

      test('rejects import when os matches and cpuArch differs', () async {
        hiveServerStorage = StubHiveServerStorage();
        internalStorage = StubHiveInternalServerStorage();
        final service = ServerService(hiveServerStorage, internalStorage);
        final bundle = await _createTestOtsBundle(
          'platform-cpu-mismatch-demo',
          os: nativeOs,
          cpuArch: otherCpuArch,
        );

        await expectLater(
          () => service.import(bundle.zipPath),
          throwsA(isA<SystemMismatchException>()),
        );

        await bundle.dispose();
      });

      test('rejects import when both os and cpuArch differ', () async {
        hiveServerStorage = StubHiveServerStorage();
        internalStorage = StubHiveInternalServerStorage();
        final service = ServerService(hiveServerStorage, internalStorage);
        final bundle = await _createTestOtsBundle(
          'platform-full-mismatch-demo',
          os: otherOs,
          cpuArch: otherCpuArch,
        );

        await expectLater(
          () => service.import(bundle.zipPath),
          throwsA(isA<SystemMismatchException>()),
        );

        await bundle.dispose();
      });
    });
  });
}

final serviceMetadataDigest = 'sha256:${List.filled(64, 'a').join()}';

String _serverOtsFilePath(String name, String internalId) {
  return '$OPENTOOL_PATH${Platform.pathSeparator}$SERVER_FOLDER${Platform.pathSeparator}$name-$internalId.ots';
}

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
  final configFile = File(p.join(contentDir.path, OPENTOOL_FILE_JSON_NAME));
  await configFile.writeAsString(jsonEncode(config.toJson()));
  final scriptFile = File(p.join(contentDir.path, 'run.sh'));
  await scriptFile.writeAsString('#!/bin/bash\necho test');

  final zipPath = p.join(rootDir.path, 'bundle.ots');
  await ZipUtil.zipDirectory(contentDir.path, zipPath);
  return _TestOtsBundle(zipPath, rootDir);
}

class _TestOtsBundle {
  final String zipPath;
  final Directory rootDir;

  _TestOtsBundle(this.zipPath, this.rootDir);

  Future<void> dispose() async {
    if (await rootDir.exists()) {
      await rootDir.delete(recursive: true);
    }
  }
}
