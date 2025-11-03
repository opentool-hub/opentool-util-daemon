import 'dart:convert';
import 'dart:io';

class CommandException implements Exception {
  final String command;
  final String message;
  final int? exitCode;

  CommandException(this.command, this.message, {this.exitCode});

  @override
  String toString() => 'CommandException(exitCode=$exitCode): $command -> $message';
}

class CommandUtil {
  static Future<int> runStream(String workDir, String command, List<String> args, {void Function(String command, String output)? onStdout, void Function(String command, String error)? onStderr, bool printStd = true,}) async {
    final fullCommand = '$command ${args.join(' ')}';

    Process process;
    if (Platform.isWindows) {
      process = await Process.start('cmd', ['/c', fullCommand], workingDirectory: workDir, runInShell: true,);
    } else {
      process = await Process.start('bash', ['-c', fullCommand], workingDirectory: workDir, runInShell: true,);
    }

    process.stdout
        .transform(SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (printStd) stdout.writeln(line);
      onStdout?.call(command, line);
    });

    process.stderr
        .transform(SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (printStd) stderr.writeln(line);
      onStderr?.call(command, line);
    });

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw CommandException(fullCommand, 'Process exited with code $exitCode', exitCode: exitCode);
    }
    return exitCode;
  }

  static Future<String> runCommand(String workDir, String command) async {
    ProcessResult processResult;
    if (Platform.isWindows) {
      processResult = await Process.run('cmd', ['/c', command], workingDirectory: workDir);
    } else {
      processResult = await Process.run('bash', ['-c', command], workingDirectory: workDir);
    }
    if(processResult.exitCode == 0) {
      return processResult.stdout.toString();
    } else {
      throw CommandException(command, processResult.stderr.toString());
    }
  }
}