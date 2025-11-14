import 'package:dio/dio.dart';
import 'package:opentool_daemon/opentool_daemon_client.dart';
import 'package:test/test.dart';
import 'dio_stub.dart';

void main() {
  group('DaemonClient tool APIs', () {
    test('listTool forwards the `all` query flag', () async {
      RequestOptions? captured;
      final stub = createStubDio({
        'GET /list': (options) {
          captured = options;
          return [
            {
              'id': 'tool-1',
              'alias': 'alpha',
              'tag': '1.0.0',
              'host': '127.0.0.1',
              'port': 9000,
              'apiKey': 'key-1',
              'status': 'running',
            },
          ];
        },
      });

      final client = DaemonClient();
      client.toolDio = stub;

      final tools = await client.listTool('1');

      expect(captured?.queryParameters['all'], equals('1'));
      expect(tools.single.id, equals('tool-1'));
    });

    test('setAliasTool posts the alias as a query parameter', () async {
      RequestOptions? captured;
      final stub = createStubDio({
        'POST /tool-1/alias': (options) {
          captured = options;
          return {
            'id': 'tool-1',
            'alias': options.queryParameters['alias'],
            'tag': '1.0.0',
            'host': '127.0.0.1',
            'port': 9000,
            'apiKey': 'key-1',
            'status': 'running',
          };
        },
      });

      final client = DaemonClient();
      client.toolDio = stub;

      final dto = await client.setAliasTool('tool-1', 'gamma');

      expect(captured?.queryParameters['alias'], equals('gamma'));
      expect(dto.alias, equals('gamma'));
    });

    test('stopTool hits the stop endpoint and parses the id DTO', () async {
      RequestOptions? captured;
      final stub = createStubDio({
        'POST /tool-1/stop': (options) {
          captured = options;
          return {'id': 'tool-1'};
        },
      });

      final client = DaemonClient();
      client.toolDio = stub;

      final dto = await client.stopTool('tool-1');

      expect(captured?.method, equals('POST'));
      expect(dto.id, equals('tool-1'));
    });
  });
}
