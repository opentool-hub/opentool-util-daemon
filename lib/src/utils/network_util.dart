import 'dart:io';

/// Returns the first available port on [host] starting from [startPort].
/// Continues incrementing the port number until a free socket is found.
Future<int> findAvailablePort(String host, int startPort) async {
  int candidate = startPort;
  while (true) {
    if (await isPortAvailable(host, candidate)) {
      return candidate;
    }
    candidate++;
  }
}

Future<bool> isPortAvailable(String host, int port) async {
  if (await _hasListeningEndpoint(host, port)) return false;

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

Future<bool> _hasListeningEndpoint(String host, int port) async {
  final normalized = host.trim().toLowerCase();
  final probeHosts =
      const {
        '0.0.0.0',
        '127.0.0.1',
        'localhost',
        '::',
        '::1',
      }.contains(normalized)
      ? const ['127.0.0.1', '::1']
      : [host];

  for (final probeHost in probeHosts) {
    Socket? socket;
    try {
      socket = await Socket.connect(
        probeHost,
        port,
        timeout: const Duration(milliseconds: 150),
      );
      return true;
    } catch (_) {
      // No listener is reachable through this address.
    } finally {
      socket?.destroy();
    }
  }
  return false;
}

/// Best-effort diagnostics for endpoint conflicts. Failure to inspect the OS
/// must never hide the original startup error.
Future<List<int>> findListeningProcessIds(int port) async {
  try {
    if (Platform.isWindows) {
      final result = await Process.run('netstat', ['-ano', '-p', 'tcp']);
      if (result.exitCode != 0) return const [];
      final pids = <int>{};
      for (final line in result.stdout.toString().split('\n')) {
        final columns = line.trim().split(RegExp(r'\s+'));
        if (columns.length < 5 || columns[3].toUpperCase() != 'LISTENING') {
          continue;
        }
        if (!columns[1].endsWith(':$port')) continue;
        final pid = int.tryParse(columns[4]);
        if (pid != null) pids.add(pid);
      }
      return pids.toList()..sort();
    }

    final result = await Process.run('lsof', [
      '-nP',
      '-iTCP:$port',
      '-sTCP:LISTEN',
      '-t',
    ]);
    if (result.exitCode != 0) return const [];
    final pids =
        result.stdout
            .toString()
            .split(RegExp(r'\s+'))
            .map(int.tryParse)
            .whereType<int>()
            .toSet()
            .toList()
          ..sort();
    return pids;
  } catch (_) {
    return const [];
  }
}
