import 'package:dio/dio.dart';
import 'package:opentool_daemon/src/client/client.dart';
import 'package:opentool_daemon/src/controller/dto.dart';
import 'package:test/test.dart';
import 'dio_stub.dart';

void main() {
  group('DaemonClient manage APIs', () {
    test('getVersion parses the daemon payload', () async {
      RequestOptions? observedRequest;
      final stubDio = createStubDio({
        'GET /version': (options) {
          observedRequest = options;
          return {'name': 'opentool-daemon', 'version': '0.2.0'};
        },
      });

      final client = DaemonClient();
      client.manageDio = stubDio;

      final dto = await client.getVersion();

      expect(observedRequest?.method, equals('GET'));
      expect(dto.name, equals('opentool-daemon'));
      expect(dto.version, equals('0.2.0'));
    });

    test('loginHub posts the JSON body expected by the controller', () async {
      RequestOptions? observedRequest;
      final stubDio = createStubDio({
        'POST /opentool-hub/login': (options) {
          observedRequest = options;
          return {'registry': 'hub.local', 'username': 'tester'};
        },
      });

      final client = DaemonClient();
      client.manageDio = stubDio;

      final loginDto = LoginInfoDto(
        registry: 'hub.local',
        username: 'tester',
        password: 'secret',
      );
      final result = await client.loginHub(loginDto);

      expect(observedRequest?.method, equals('POST'));
      expect(observedRequest?.data, equals(loginDto.toJson()));
      expect(result.username, equals('tester'));
      expect(result.registry, equals('hub.local'));
    });

    test(
      'create/list/delete api keys set sudo header and parse payloads',
      () async {
        RequestOptions? createRequest;
        RequestOptions? listRequest;
        RequestOptions? deleteRequest;
        final stubDio = createStubDio({
          'POST /apiKey': (options) {
            createRequest = options;
            return {
              'name': options.data['name'],
              'apiKey': 'generated',
              'createdAt': '2024-01-01T00:00:00.000Z',
            };
          },
          'GET /apiKeys': (options) {
            listRequest = options;
            return [
              {
                'name': 'ops',
                'apiKey': 'generated',
                'createdAt': '2024-01-01T00:00:00.000Z',
              },
            ];
          },
          'DELETE /apiKey/generated': (options) {
            deleteRequest = options;
            return {'apiKey': 'generated'};
          },
        });

        final client = DaemonClient();
        client.manageDio = stubDio;

        final created = await client.createApiKey(
          sudoToken: 'sudo',
          name: 'ops',
        );
        expect(createRequest?.headers['x-opentool-sudo-token'], equals('sudo'));
        expect(created.name, equals('ops'));

        final listed = await client.listApiKeys(sudoToken: 'sudo');
        expect(listRequest?.headers['x-opentool-sudo-token'], equals('sudo'));
        expect(listed, hasLength(1));

        await client.deleteApiKey(sudoToken: 'sudo', apiKey: 'generated');
        expect(deleteRequest?.headers['x-opentool-sudo-token'], equals('sudo'));
      },
    );
  });
}
