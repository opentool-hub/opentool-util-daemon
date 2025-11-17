import 'dart:io';

/// Returns the first available port on [host] starting from [startPort].
/// Continues incrementing the port number until a free socket is found.
Future<int> findAvailablePort(String host, int startPort) async {
  int candidate = startPort;
  while (true) {
    if (await _isPortOpen(host, candidate)) {
      return candidate;
    }
    candidate++;
  }
}

Future<bool> _isPortOpen(String host, int port) async {
  ServerSocket? socket;
  try {
    socket = await ServerSocket.bind(host, port);
    return true;
  } catch (_) {
    return false;
  } finally {
    await socket?.close();
  }
}
