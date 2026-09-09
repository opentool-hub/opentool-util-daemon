import 'dart:async';
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

  test('runCommand forwards output before the process exits', () async {
    final script = File(p.join(root.path, 'stream.dart'));
    await script.writeAsString('''
import 'dart:async';
import 'dart:io';

Future<void> main() async {
  stdout.write('first');
  await stdout.flush();
  await Future<void>.delayed(const Duration(milliseconds: 150));
  stdout.write(' second');
}
''');
    final firstOutput = Completer<void>();
    var completed = false;
    final command = '"${Platform.resolvedExecutable}" "${script.path}"';

    final running =
        CommandUtil.runCommand(
          root.path,
          command,
          onStdout: (chunk) {
            if (chunk.contains('first') && !firstOutput.isCompleted) {
              firstOutput.complete();
            }
          },
        ).then((value) {
          completed = true;
          return value;
        });

    await firstOutput.future.timeout(const Duration(seconds: 2));
    expect(completed, isFalse);
    expect(await running, 'first second');
  });

  test('runStream retains only bounded diagnostic output', () async {
    final script = File(p.join(root.path, 'verbose_failure.dart'));
    await script.writeAsString(r'''
import 'dart:io';

void main() {
  stdout.writeln('${List.filled(12000, 'a').join()}stdout-tail');
  stderr.writeln('${List.filled(12000, 'b').join()}stderr-tail');
  exitCode = 9;
}
''');

    await expectLater(
      CommandUtil.runStream(root.path, Platform.resolvedExecutable, [
        script.path,
      ], printStd: false),
      throwsA(
        isA<CommandException>()
            .having((error) => error.stdout.length, 'stdout length', 8192)
            .having(
              (error) => error.stdout.trimRight(),
              'stdout tail',
              endsWith('stdout-tail'),
            )
            .having((error) => error.stderr.length, 'stderr length', 8192)
            .having(
              (error) => error.stderr.trimRight(),
              'stderr tail',
              endsWith('stderr-tail'),
            ),
      ),
    );
  });
}
