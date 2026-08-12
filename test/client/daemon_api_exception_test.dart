import 'package:dio/dio.dart';
import 'package:opentool_daemon/opentool_daemon_client.dart';
import 'package:test/test.dart';

void main() {
  group('DaemonApiException', () {
    test('parses the stable daemon envelope', () {
      final error = DaemonApiException.fromResponse(
        statusCode: 422,
        body: const {
          'error': {
            'code': 'PLATFORM_NOT_SUPPORTED',
            'message': 'No compatible artifact',
            'retryable': false,
            'requestId': 'req-1',
            'details': {'os': 'linux'},
          },
        },
      );

      expect(error.code, 'PLATFORM_NOT_SUPPORTED');
      expect(error.message, 'No compatible artifact');
      expect(error.statusCode, 422);
      expect(error.retryable, isFalse);
      expect(error.requestId, 'req-1');
      expect(error.details, {'os': 'linux'});
    });

    test('provides a stable fallback for non-JSON HTTP errors', () {
      final error = DaemonApiException.fromResponse(
        statusCode: 502,
        body: '<html>bad gateway</html>',
      );

      expect(error.code, 'DAEMON_HTTP_ERROR');
      expect(error.message, '<html>bad gateway</html>');
      expect(error.retryable, isTrue);
    });

    test('maps transport failures without exposing DioException', () {
      final request = RequestOptions(path: '/version');
      final error = DaemonApiException.fromDio(
        DioException(
          requestOptions: request,
          type: DioExceptionType.connectionError,
          message: 'connection refused',
        ),
      );

      expect(error.code, 'DAEMON_UNAVAILABLE');
      expect(error.retryable, isTrue);
      expect(error.statusCode, isNull);
    });
  });
}
