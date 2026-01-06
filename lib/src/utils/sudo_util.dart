import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:unique_id_dart/unique_id_dart.dart';

import '../../opentool_daemon_utils.dart';

typedef _CommandRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);
typedef _TokenGenerator = String Function();

class SudoRequiredException implements Exception {
  final String message;

  const SudoRequiredException([
    this.message = 'sudo privileges are required to run this command',
  ]);

  @override
  String toString() => 'SudoRequiredException: $message';
}

class SudoPlatformContext {
  final bool isWindows;
  final Map<String, String> environment;

  const SudoPlatformContext({
    required this.isWindows,
    required this.environment,
  });

  factory SudoPlatformContext.system() => SudoPlatformContext(
    isWindows: Platform.isWindows,
    environment: Platform.environment,
  );
}

class SudoUtil {
  /// Helper for sudo/Administrator checks and issuing temp tokens to CLI.
  final _CommandRunner _commandRunner;
  final SudoPlatformContext _platform;
  final _TokenGenerator _tokenGenerator;

  SudoUtil({
    _CommandRunner? commandRunner,
    SudoPlatformContext? platform,
    _TokenGenerator? tokenGenerator,
  }) : _commandRunner =
           commandRunner ?? ((cmd, args) => Process.run(cmd, args)),
       _platform = platform ?? SudoPlatformContext.system(),
       _tokenGenerator = tokenGenerator ?? (() => uniqueId(shorter: false));

  /// Verifies the current process has sudo/Administrator privileges.
  Future<void> ensureSudo() async {
    if (!await isRunningAsRoot()) {
      throw const SudoRequiredException();
    }
  }

  /// Returns true if current process is elevated (root/Admin), regardless of OS.
  Future<bool> isRunningAsRoot() async {
    if (_platform.isWindows) {
      return _isWindowsAdministrator();
    }
    return _isPosixRoot();
  }

  Future<bool> _isPosixRoot() async {
    final env = _platform.environment;
    if (env['USER'] == 'root' || env.containsKey('SUDO_UID')) {
      return true;
    }
    final result = await _commandRunner('id', ['-u']);
    if (result.exitCode != 0) return false;
    return result.stdout.toString().trim() == '0';
  }

  Future<bool> _isWindowsAdministrator() async {
    final script =
        '[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)';
    final result = await _commandRunner('powershell', [
      '-NoProfile',
      '-Command',
      script,
    ]);
    if (result.exitCode != 0) return false;
    return result.stdout.toString().trim().toLowerCase() == 'true';
  }

  /// Ensures sudo rights, then writes a temp token JSON file next to the daemon socket.
  Future<String> ensureSudoAndWriteToken(
    String socketPath, {
    int timeoutSeconds = 300,
  }) async {
    await ensureSudo();
    final token = _tokenGenerator();
    final payload = jsonEncode({
      'tempToken': token,
      'timeoutInSecond': timeoutSeconds,
    });
    final file = File(socketPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(payload);
    return token;
  }

  /// Reads the JSON token payload that a CLI dropped near the daemon socket.
  Future<SudoTokenPayload> readToken(String socketPath) async {
    try {
      final content = await File(socketPath).readAsString();
      final Map<String, dynamic> json = jsonDecode(content);
      return SudoTokenPayload.fromJson(json);
    } catch (error) {
      logger.log(
        LogModule.manage,
        'sudoToken.read.failed',
        detail: 'path: $socketPath error: $error',
        level: Level.WARNING,
      );
      rethrow;
    }
  }
}

class SudoTokenPayload {
  final String tempToken;
  final int timeoutInSecond;

  SudoTokenPayload({required this.tempToken, required this.timeoutInSecond});

  factory SudoTokenPayload.fromJson(Map<String, dynamic> json) {
    return SudoTokenPayload(
      tempToken: json['tempToken'] as String,
      timeoutInSecond: json['timeoutInSecond'] as int,
    );
  }
}
