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
  });
}
