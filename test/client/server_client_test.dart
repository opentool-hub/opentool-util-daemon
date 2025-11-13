import 'package:dio/dio.dart';
import 'package:opentool_daemon/opentool_daemon_client.dart';
import 'package:test/test.dart';
import 'dio_stub.dart';

void main() {
  group('DaemonClient server APIs', () {
    test('listServer fetches and parses server DTOs', () async {
      RequestOptions? captured;
      final stub = createStubDio({
        'GET /list': (options) {
          captured = options;
          return [
            {
              'id': 'srv-1',
              'alias': 'alpha',
              'registry': 'hub.local',
              'repo': 'hub/opentool',
              'name': 'demo',
              'tag': 'latest',
            },
          ];
        },
      });

      final client = DaemonClient();
      client.serverDio = stub;

      final servers = await client.listServer();

      expect(captured?.method, equals('GET'));
      expect(servers, hasLength(1));
      expect(servers.first.name, equals('demo'));
    });

    test('tagServer posts query parameters for the new tag', () async {
      RequestOptions? captured;
      final stub = createStubDio({
        'POST /srv-1/tag': (options) {
          captured = options;
          return {
            'id': 'srv-1',
            'alias': 'alpha',
            'registry': 'hub.local',
            'repo': 'hub/opentool',
            'name': 'demo',
            'tag': options.queryParameters['tag'],
          };
        },
      });

      final client = DaemonClient();
      client.serverDio = stub;

      final dto = await client.tagServer('srv-1', 'stable');

      expect(captured?.queryParameters['tag'], equals('stable'));
      expect(dto.tag, equals('stable'));
    });

    test(
      'deleteServer issues a DELETE request and returns the id DTO',
      () async {
        RequestOptions? captured;
        final stub = createStubDio({
          'DELETE /srv-1': (options) {
            captured = options;
            return {'id': 'srv-1'};
          },
        });

        final client = DaemonClient();
        client.serverDio = stub;

        final dto = await client.deleteServer('srv-1');

        expect(captured?.method, equals('DELETE'));
        expect(dto.id, equals('srv-1'));
      },
    );
  });
}
