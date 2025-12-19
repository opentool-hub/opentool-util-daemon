import 'dart:io';

import 'package:hive/hive.dart';
import 'package:opentool_daemon/src/service/server_service.dart';
import 'package:opentool_daemon/src/storage/dao.dart';
import 'package:opentool_daemon/src/storage/hive_storage.dart';
import 'package:test/test.dart';

import '../test_doubles.dart';

void main() {
  group('HiveServerStorage migration', () {
    late String originalDbPath;
    late Directory tempDir;
    late HiveServerStorage hiveServerStorage;
    late StubHiveInternalServerStorage internalStorage;

    setUp(() async {
      originalDbPath = DB_PATH;
      tempDir = await Directory.systemTemp.createTemp('hive_server_migration_');
      DB_PATH = tempDir.path;

      hiveServerStorage = HiveServerStorage();
      await hiveServerStorage.init();
      internalStorage = StubHiveInternalServerStorage();
    });

    tearDown(() async {
      await Hive.close();
      DB_PATH = originalDbPath;
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('repairs mismatched Hive key/id to avoid alias update errors', () async {
      final box = Hive.box<ServerDao>('servers');

      // Simulate corrupted data: record stored under key "A" but containing id "B".
      await box.put(
        'A',
        ServerDao(
          id: 'B',
          alias: 'alpha',
          registry: 'hub.local',
          repo: 'org/project',
          name: 'demo-server',
          tag: 'latest',
          internalId: 'int-1',
        ),
      );

      final service = ServerService(hiveServerStorage, internalStorage);

      // Warm cache and trigger migration.
      final servers = await service.list();
      expect(servers, hasLength(1));
      expect(servers.single.id, equals('B'));

      expect(box.get('A'), isNull);
      expect(box.get('B'), isNotNull);

      // Should not throw HiveError (same instance stored under different keys).
      await service.setAlias('B', '0009');
      final updated = await service.get('B');
      expect(updated.alias, equals('0009'));

      final stored = box.get('B');
      expect(stored, isNotNull);
      expect(stored!.alias, equals('0009'));
    });
  });
}
