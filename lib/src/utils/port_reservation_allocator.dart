import 'dart:async';

typedef AvailablePortAllocator =
    Future<int> Function(String host, int startPort);

/// Coordinates the short gap between finding a free port and a child process
/// binding it.
///
/// Reservations are intentionally keyed only by port. This conservatively
/// avoids assigning the same port to bindings whose host names may overlap,
/// such as `0.0.0.0`, `127.0.0.1`, and `localhost`.
class PortReservationAllocator {
  final AvailablePortAllocator _portAllocator;
  final Set<int> _reservedPorts = <int>{};
  final _AsyncMutex _mutex = _AsyncMutex();

  PortReservationAllocator(this._portAllocator);

  Future<int> allocateAndReserve(String host, int startPort) =>
      _mutex.run(() async {
        var candidate = startPort;
        while (true) {
          while (_reservedPorts.contains(candidate)) {
            candidate++;
          }

          final port = await _portAllocator(host, candidate);
          if (_reservedPorts.contains(port)) {
            candidate = port + 1;
            continue;
          }

          _reservedPorts.add(port);
          return port;
        }
      });

  Future<void> release(int port) => _mutex.run(() async {
    _reservedPorts.remove(port);
  });

  /// Exposed for deterministic unit tests and diagnostics.
  bool isReserved(int port) => _reservedPorts.contains(port);
}

/// A FIFO asynchronous mutex whose queue always advances when an action fails.
class _AsyncMutex {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    return previous.then((_) => action()).whenComplete(() {
      if (!release.isCompleted) release.complete();
    });
  }
}
