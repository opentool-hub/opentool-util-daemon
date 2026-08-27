import 'dart:io';
import 'package:test/test.dart';
import 'package:opentool_daemon/src/utils/network_util.dart';

void main() {
  group('findAvailablePort', () {
    test('returns the requested port when free', () async {
      final tempSocket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final int freePort = tempSocket.port;
      await tempSocket.close();

      final result = await findAvailablePort(
        InternetAddress.loopbackIPv4.address,
        freePort,
      );

      expect(result, equals(freePort));
    });

    test('skips a busy port and picks the next one', () async {
      final busySocket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final int busyPort = busySocket.port;

      final result = await findAvailablePort(
        InternetAddress.loopbackIPv4.address,
        busyPort,
      );
      await busySocket.close();

      expect(result, isNot(equals(busyPort)));
      expect(result, greaterThan(busyPort));
    });

    test('wildcard allocation rejects a loopback listener', () async {
      final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(listener.close);

      expect(
        await isPortAvailable(InternetAddress.anyIPv4.address, listener.port),
        isFalse,
      );
    });

    test('loopback allocation rejects a wildcard listener', () async {
      final listener = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      addTearDown(listener.close);

      expect(
        await isPortAvailable(
          InternetAddress.loopbackIPv4.address,
          listener.port,
        ),
        isFalse,
      );
    });
  });
}
