import 'dart:io';

import 'package:opentool_daemon/src/utils/executable_util.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ExecutableUtil.resolveEntrypoint', () {
    test('returns .\\\\<name>.exe when present on Windows', () async {
      final tmp = await Directory.systemTemp.createTemp('exe_util_win_');
      await File(p.join(tmp.path, 'mock_tool.exe')).writeAsString('test');

      final resolved = ExecutableUtil.resolveEntrypoint(
        tmp.path,
        'mock_tool',
        isWindows: true,
      );

      expect(resolved, equals(r'.\mock_tool.exe'));
      await tmp.delete(recursive: true);
    });

    test('returns .\\\\<name> when exact file exists on Windows', () async {
      final tmp = await Directory.systemTemp.createTemp('exe_util_win2_');
      await File(p.join(tmp.path, 'mock_tool')).writeAsString('test');

      final resolved = ExecutableUtil.resolveEntrypoint(
        tmp.path,
        'mock_tool',
        isWindows: true,
      );

      expect(resolved, equals(r'.\mock_tool'));
      await tmp.delete(recursive: true);
    });

    test('returns ./<name> when file exists on POSIX', () async {
      final tmp = await Directory.systemTemp.createTemp('exe_util_posix_');
      await File(p.join(tmp.path, 'mock_tool')).writeAsString('test');

      final resolved = ExecutableUtil.resolveEntrypoint(
        tmp.path,
        'mock_tool',
        isWindows: false,
      );

      expect(resolved, equals('./mock_tool'));
      await tmp.delete(recursive: true);
    });
  });

  group('ExecutableUtil.ensureExecutable', () {
    test('does not invoke chmod on Windows', () async {
      final tmp = await Directory.systemTemp.createTemp('exe_util_chmod_');
      await File(p.join(tmp.path, 'mock_tool')).writeAsString('test');
      var called = false;

      await ExecutableUtil.ensureExecutable(
        './mock_tool',
        tmp.path,
        isWindows: true,
        commandRunner: (_, __) async {
          called = true;
          return ProcessResult(0, 0, '', '');
        },
      );

      expect(called, isFalse);
      await tmp.delete(recursive: true);
    });

    test('invokes chmod on POSIX when file is not executable', () async {
      final tmp = await Directory.systemTemp.createTemp('exe_util_chmod2_');
      final file = File(p.join(tmp.path, 'mock_tool'));
      await file.writeAsString('test');
      await Process.run('chmod', ['644', file.path]);

      var called = false;
      await ExecutableUtil.ensureExecutable(
        './mock_tool',
        tmp.path,
        isWindows: false,
        commandRunner: (cmd, args) async {
          called = true;
          expect(cmd, equals('chmod'));
          expect(args.first, equals('+x'));
          return ProcessResult(0, 0, '', '');
        },
      );

      expect(called, isTrue);
      await tmp.delete(recursive: true);
    });
  });
}
