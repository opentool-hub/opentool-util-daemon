import 'dart:convert';
import 'package:opentool_daemon/src/controller/server_controller.dart';
import 'package:opentool_daemon/src/service/model.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import '../test_doubles.dart';

void main() {
  group('ServerController', () {
    late FakeServerService serverService;
    late ServerController controller;

    setUp(() {
      serverService = FakeServerService(
        initialServers: [
          ServerModel(
            id: 'srv-1',
            alias: 'srv-1',
            registry: 'hub.local',
            repo: 'hub/opentool',
            name: 'demo-server',
            tag: 'latest',
            internalId: 'int-1',
          ),
        ],
      );
      controller = ServerController(serverService, NoopManageService());
    });

    test('listServers returns DTOs derived from the service models', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/opentool-daemon/servers/list'),
      );

      final response = await controller.listServers(request);
      final decoded =
          jsonDecode(await response.readAsString()) as List<dynamic>;

      expect(decoded, hasLength(1));
      expect(decoded.first['name'], equals('demo-server'));
      expect(decoded.first['tag'], equals('latest'));
    });

    test('setAlias updates the server and returns the updated DTO', () async {
      final request = Request(
        'POST',
        Uri.parse(
          'http://localhost/opentool-daemon/servers/srv-1/alias?alias=web',
        ),
      );

      final response = await controller.setAlias(request, 'srv-1');
      final decoded =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;

      expect(decoded['alias'], equals('web'));
      final updated = await serverService.get('srv-1');
      expect(updated.alias, equals('web'));
    });

    test('deleteServer delegates to the service and echoes the id', () async {
      final request = Request(
        'DELETE',
        Uri.parse('http://localhost/opentool-daemon/servers/srv-1'),
      );

      final response = await controller.deleteServer(request, 'srv-1');
      final payload =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;

      expect(payload['id'], equals('srv-1'));
      expect(serverService.lastDeletedId, equals('srv-1'));
      expect(serverService.list(), completion(isEmpty));
    });
  });
}
