import 'dart:io';
import 'package:test/test.dart';
import 'package:opentool_daemon/src/utils/network_util.dart';

void main() {
  group('findAvailablePort', () {
    test('returns the requested port when free', () async {
      final tempSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final int freePort = tempSocket.port;
      await tempSocket.close();

      final result = await findAvailablePort(InternetAddress.loopbackIPv4.address, freePort);

      expect(result, equals(freePort));
    });

    test('skips a busy port and picks the next one', () async {
      final busySocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final int busyPort = busySocket.port;

      final result = await findAvailablePort(InternetAddress.loopbackIPv4.address, busyPort);
      await busySocket.close();

      expect(result, isNot(equals(busyPort)));
      expect(result, greaterThan(busyPort));
    });
  });
}
