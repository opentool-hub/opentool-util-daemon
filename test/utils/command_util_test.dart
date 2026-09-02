import 'dart:io';

import 'package:opentool_daemon/src/utils/command_util.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('command_util_test_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'runCommand preserves exit code, stdout, and stderr on failure',
    () async {
      final script = File(p.join(root.path, 'fail.dart'));
      await script.writeAsString('''
import 'dart:io';

void main() {
  stdout.write('stdout detail');
  stderr.write('stderr detail');
  exitCode = 7;
}
''');

      final command = '"${Platform.resolvedExecutable}" "${script.path}"';

      await expectLater(
        CommandUtil.runCommand(root.path, command),
        throwsA(
          isA<CommandException>()
              .having((error) => error.exitCode, 'exitCode', 7)
              .having((error) => error.stdout, 'stdout', 'stdout detail')
              .having((error) => error.stderr, 'stderr', 'stderr detail')
              .having((error) => error.message, 'message', 'stderr detail')
              .having(
                (error) => error.toString(),
                'toString',
                contains('exitCode=7'),
              )
              .having(
                (error) => error.toString(),
                'toString',
                contains('stderr detail'),
              )
              .having(
                (error) => error.toString(),
                'toString',
                contains('stdout detail'),
              ),
        ),
      );
    },
  );

  test(
    'runCommand uses stdout as the failure message when stderr is empty',
    () async {
      final script = File(p.join(root.path, 'stdout_failure.dart'));
      await script.writeAsString('''
import 'dart:io';

void main() {
  stdout.write('compiler failure');
  exitCode = 3;
}
''');

      final command = '"${Platform.resolvedExecutable}" "${script.path}"';

      await expectLater(
        CommandUtil.runCommand(root.path, command),
        throwsA(
          isA<CommandException>()
              .having((error) => error.exitCode, 'exitCode', 3)
              .having((error) => error.message, 'message', 'compiler failure')
              .having((error) => error.stdout, 'stdout', 'compiler failure')
              .having((error) => error.stderr, 'stderr', isEmpty),
        ),
      );
    },
  );
}
