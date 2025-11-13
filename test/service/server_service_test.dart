import 'package:opentool_daemon/src/service/exception.dart';
import 'package:opentool_daemon/src/service/server_service.dart';
import 'package:opentool_daemon/src/storage/dao.dart';
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
  });
}
