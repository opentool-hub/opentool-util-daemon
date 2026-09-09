import 'dart:collection';
import 'dart:convert';
import 'dart:io';

class CommandException implements Exception {
  final String command;
  final String message;
  final int? exitCode;
  final String stdout;
  final String stderr;

  CommandException(
    this.command,
    this.message, {
    this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  @override
  String toString() {
    final outputs = <String>[
      if (stderr.trim().isNotEmpty) 'stderr=${_forLog(stderr)}',
      if (stdout.trim().isNotEmpty) 'stdout=${_forLog(stdout)}',
    ];
    final detail = outputs.isEmpty ? _forLog(message) : outputs.join(', ');
    return 'CommandException(exitCode=$exitCode): ${_forLog(command)} -> $detail';
  }
}

const _maxLoggedCommandOutputChars = 8192;
const _maxRetainedStreamOutputChars = 8192;

String _forLog(String value) {
  final escaped = value.trim().replaceAll('\r', r'\r').replaceAll('\n', r'\n');
  if (escaped.length <= _maxLoggedCommandOutputChars) return escaped;
  final omitted = escaped.length - _maxLoggedCommandOutputChars;
  return '${escaped.substring(0, _maxLoggedCommandOutputChars)}'
      '...[truncated $omitted chars]';
}

class CommandUtil {
  static Future<int> runStream(
    String workDir,
    String command,
    List<String> args, {
    void Function(String command, String output)? onStdout,
    void Function(String command, String error)? onStderr,
    bool printStd = true,
  }) async {
    final fullCommand = '$command ${args.join(' ')}';

    Process process;
    if (Platform.isWindows) {
      process = await Process.start(
        'cmd',
        ['/c', fullCommand],
        workingDirectory: workDir,
        runInShell: true,
      );
    } else {
      process = await Process.start(
        'bash',
        ['-c', fullCommand],
        workingDirectory: workDir,
        runInShell: true,
      );
    }

    final commandStdout = _BoundedTextBuffer(_maxRetainedStreamOutputChars);
    final commandStderr = _BoundedTextBuffer(_maxRetainedStreamOutputChars);
    final stdoutDone = process.stdout
        .transform(SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) {
          commandStdout.writeln(line);
          if (printStd) stdout.writeln(line);
          onStdout?.call(command, line);
        })
        .asFuture<void>();

    final stderrDone = process.stderr
        .transform(SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) {
          commandStderr.writeln(line);
          if (printStd) stderr.writeln(line);
          onStderr?.call(command, line);
        })
        .asFuture<void>();

    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);
    if (exitCode != 0) {
      throw CommandException(
        fullCommand,
        'Process exited with code $exitCode',
        exitCode: exitCode,
        stdout: commandStdout.toString(),
        stderr: commandStderr.toString(),
      );
    }
    return exitCode;
  }

  static Future<String> runCommand(
    String workDir,
    String command, {
    void Function(String output)? onStdout,
    void Function(String output)? onStderr,
  }) async {
    Process process;
    if (Platform.isWindows) {
      process = await Process.start('cmd', [
        '/c',
        command,
      ], workingDirectory: workDir);
    } else {
      process = await Process.start('bash', [
        '-c',
        command,
      ], workingDirectory: workDir);
    }
    final commandStdout = StringBuffer();
    final commandStderr = StringBuffer();
    final stdoutDone = process.stdout
        .transform(SystemEncoding().decoder)
        .listen((chunk) {
          commandStdout.write(chunk);
          onStdout?.call(chunk);
        })
        .asFuture<void>();
    final stderrDone = process.stderr
        .transform(SystemEncoding().decoder)
        .listen((chunk) {
          commandStderr.write(chunk);
          onStderr?.call(chunk);
        })
        .asFuture<void>();
    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);
    final stdoutText = commandStdout.toString();
    final stderrText = commandStderr.toString();
    if (exitCode == 0) {
      return stdoutText;
    } else {
      final message = stderrText.trim().isNotEmpty
          ? stderrText
          : stdoutText.trim().isNotEmpty
          ? stdoutText
          : 'Process exited with code $exitCode';
      throw CommandException(
        command,
        message,
        exitCode: exitCode,
        stdout: stdoutText,
        stderr: stderrText,
      );
    }
  }
}

class _BoundedTextBuffer {
  final int maxChars;
  final ListQueue<String> _chunks = ListQueue<String>();
  int _length = 0;

  _BoundedTextBuffer(this.maxChars);

  void writeln(String value) => write('$value\n');

  void write(String value) {
    if (maxChars <= 0 || value.isEmpty) return;
    if (value.length >= maxChars) {
      _chunks
        ..clear()
        ..add(value.substring(value.length - maxChars));
      _length = maxChars;
      return;
    }

    _chunks.addLast(value);
    _length += value.length;
    while (_length > maxChars) {
      final excess = _length - maxChars;
      final first = _chunks.removeFirst();
      if (first.length <= excess) {
        _length -= first.length;
      } else {
        _chunks.addFirst(first.substring(excess));
        _length -= excess;
      }
    }
  }

  @override
  String toString() => _chunks.join();
}
