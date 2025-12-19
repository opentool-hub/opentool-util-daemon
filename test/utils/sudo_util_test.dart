import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:opentool_daemon/src/utils/sudo_util.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<ProcessResult> _result(String stdout, {int exitCode = 0}) async {
  return ProcessResult(0, exitCode, stdout, '');
}

void main() {
  group('SudoUtil', () {
    test('detects root from environment without running command', () async {
      var invoked = false;
      final util = SudoUtil(
        platform: const SudoPlatformContext(
          isWindows: false,
          environment: {'USER': 'root'},
        ),
        commandRunner: (cmd, args) {
          invoked = true;
          return _result('1000');
        },
      );

      final isRoot = await util.isRunningAsRoot();

      expect(isRoot, isTrue);
      expect(invoked, isFalse);
    });

    test('falls back to id -u when env is not elevated', () async {
      final util = SudoUtil(
        platform: const SudoPlatformContext(isWindows: false, environment: {}),
        commandRunner: (cmd, args) => _result('0'),
      );

      expect(await util.isRunningAsRoot(), isTrue);
    });

    test('ensureSudo throws when user is not root', () async {
      final util = SudoUtil(
        platform: const SudoPlatformContext(isWindows: false, environment: {}),
        commandRunner: (cmd, args) => _result('1000'),
      );

      expect(util.ensureSudo(), throwsA(isA<SudoRequiredException>()));
    });

    test('ensureSudoAndWriteToken writes json next to socket', () async {
      final tempDir = await Directory.systemTemp.createTemp('sudo_util_test');
      final socketPath = p.join(tempDir.path, 'opentool.sock');
      final util = SudoUtil(
        platform: const SudoPlatformContext(
          isWindows: false,
          environment: {'USER': 'root'},
        ),
        tokenGenerator: () => 'fixed-token',
      );

      final token = await util.ensureSudoAndWriteToken(
        socketPath,
        timeoutSeconds: 120,
      );

      expect(token, equals('fixed-token'));
      final content = await File(socketPath).readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      expect(json['tempToken'], equals('fixed-token'));
      expect(json['timeoutInSecond'], equals(120));

      await tempDir.delete(recursive: true);
    });

    test('readToken parses json from socket file', () async {
      final tempDir = await Directory.systemTemp.createTemp('sudo_util_read');
      final socketPath = p.join(tempDir.path, 'opentool.sock');
      await File(
        socketPath,
      ).writeAsString(jsonEncode({'tempToken': 'abc', 'timeoutInSecond': 60}));
      final util = SudoUtil(
        platform: const SudoPlatformContext(
          isWindows: false,
          environment: {'USER': 'root'},
        ),
      );

      final payload = await util.readToken(socketPath);

      expect(payload.tempToken, equals('abc'));
      expect(payload.timeoutInSecond, equals(60));

      await tempDir.delete(recursive: true);
    });
  });
}
