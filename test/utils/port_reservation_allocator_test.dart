import 'dart:async';

import 'package:opentool_daemon/src/utils/port_reservation_allocator.dart';
import 'package:test/test.dart';

void main() {
  group('PortReservationAllocator', () {
    test('concurrent allocations reserve distinct ports globally', () async {
      final allocator = PortReservationAllocator(
        (_, startPort) async => startPort,
      );

      final ports = await Future.wait([
        allocator.allocateAndReserve('127.0.0.1', 9010),
        allocator.allocateAndReserve('0.0.0.0', 9010),
      ]);

      expect(ports, [9010, 9011]);
      expect(allocator.isReserved(9010), isTrue);
      expect(allocator.isReserved(9011), isTrue);
    });

    test('checks the actual port returned by the port allocator', () async {
      final starts = <int>[];
      final allocator = PortReservationAllocator((_, startPort) async {
        starts.add(startPort);
        return startPort == 9010 ? 9011 : startPort;
      });

      final first = await allocator.allocateAndReserve('localhost', 9010);
      final second = await allocator.allocateAndReserve('localhost', 9010);

      expect(first, 9011);
      expect(second, 9012);
      expect(starts, [9010, 9010, 9012]);
    });

    test('released ports can be allocated again', () async {
      final allocator = PortReservationAllocator(
        (_, startPort) async => startPort,
      );

      expect(await allocator.allocateAndReserve('localhost', 9010), 9010);
      await allocator.release(9010);

      expect(allocator.isReserved(9010), isFalse);
      expect(await allocator.allocateAndReserve('localhost', 9010), 9010);
    });

    test('an allocator error does not deadlock the mutex queue', () async {
      var calls = 0;
      final firstCallStarted = Completer<void>();
      final allocator = PortReservationAllocator((_, startPort) async {
        calls++;
        if (calls == 1) {
          firstCallStarted.complete();
          throw StateError('allocation failed');
        }
        return startPort;
      });

      final first = allocator.allocateAndReserve('localhost', 9010);
      await firstCallStarted.future;
      final second = allocator.allocateAndReserve('localhost', 9010);

      await expectLater(first, throwsStateError);
      await expectLater(second, completion(9010));
      expect(calls, 2);
    });
  });
}
