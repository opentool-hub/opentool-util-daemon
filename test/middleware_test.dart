import 'dart:convert';

import 'package:opentool_daemon/src/middleware.dart';
import 'package:opentool_daemon/src/service/exception.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  test('maps a Server platform mismatch to an actionable 422 error', () async {
    final handler = exceptionHandler()((_) async {
      throw SystemMismatchException(
        'macos',
        'arm64',
        'windows',
        'arm64',
        nativeAbi: 'native',
        remoteAbi: 'native',
      );
    });

    final response = await handler(
      Request('POST', Uri.parse('http://localhost/servers/import')),
    );
    final body = jsonDecode(await response.readAsString());

    expect(response.statusCode, 422);
    expect(body, {
      'error': {
        'code': 'PLATFORM_MISMATCH',
        'message':
            'Server platform windows-arm64-native is not compatible with '
            'this device (macos-arm64-native). Import an .ots file built for '
            'macos-arm64-native.',
        'retryable': false,
      },
    });
  });
}
