import 'dart:convert';
import 'dart:io';
import 'package:opentool_daemon/src/constants.dart';
import 'package:opentool_daemon/src/service/exception.dart';
import 'package:opentool_daemon/src/service/config.dart';
import 'package:opentool_daemon/src/service/server_service.dart';
import 'package:opentool_daemon/src/storage/dao.dart';
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

    test('tag reuses existing tagged server when tag already exists', () async {
      await service.list(); // warm cache with every server entry
      final server = await service.tag('srv-1', 'stable');

      expect(server.id, equals('srv-dup'));
      expect(server.tag, equals('stable'));
    });

    test('tag creates a new tagged server when tag is missing', () async {
      final serversBefore = await service.list();
      final server = await service.tag('srv-1', 'beta');
      final serversAfter = await service.list();

      expect(server.tag, equals('beta'));
      expect(serversAfter.length, equals(serversBefore.length + 1));
      expect(serversAfter.where((s) => s.tag == 'beta'), isNotEmpty);
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

    test('import overrides existing server with same name/tag', () async {
      hiveServerStorage = StubHiveServerStorage();
      internalStorage = StubHiveInternalServerStorage();
      final existingServer = ServerDao(
        id: 'srv-old',
        alias: 'old',
        registry: 'hub.local',
        repo: 'org/project',
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
      expect(matching.single.id, equals(imported.id));
      expect(await hiveServerStorage.get(existingServer.id), isNull);
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
  });
}

String _serverOtsFilePath(String name, String internalId) {
  return '$OPENTOOL_PATH${Platform.pathSeparator}$SERVER_FOLDER${Platform.pathSeparator}$name-$internalId.ots';
}

Future<_TestOtsBundle> _createTestOtsBundle(String name) async {
  final rootDir = await Directory.systemTemp.createTemp('ots_bundle_');
  final contentDir = Directory(p.join(rootDir.path, 'content'));
  await contentDir.create(recursive: true);

  final config = OpentoolfileConfig(
    name: name,
    os: SystemUtil.getOS(),
    cpuArch: SystemUtil.getCpuArch(),
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
