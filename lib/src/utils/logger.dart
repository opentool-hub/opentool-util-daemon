import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';
import '../config.dart';

enum LogModule { http, sse, manage, server, tool }

DaemonLogger logger = DaemonLogger(config.log?.level ?? Level.INFO);

class DaemonLogger {
  static final DaemonLogger _singleton = DaemonLogger._internal();
  static Level _level = Level.INFO;

  factory DaemonLogger(Level level) {
    _level = level;
    Logger.root.level = level;
    return _singleton;
  }

  Logger? _logger;
  late DaemonLogFileWriter _fileWriter;

  DaemonLogger._internal() {
    _logger = Logger('OpenToolDaemonLogger');
    Logger.root.level = _level;
    final logDir =
        Platform.environment['LOG_DIR'] ??
        '${Directory.current.path}${Platform.pathSeparator}log';
    _fileWriter = DaemonLogFileWriter(
      File('$logDir${Platform.pathSeparator}daemon.log'),
    );

    Logger.root.onRecord.listen((record) {
      final message =
          '${record.level.name}: ${record.time}: PID $pid: ${record.message}';
      print(message);
      _fileWriter.writeLine(message);
    });
  }

  void log(
    LogModule module,
    String message, {
    String detail = "{}",
    Level level = Level.INFO,
  }) {
    _logger?.log(level, "[${module.name.toUpperCase()}] $message - $detail");
  }
}

/// Keeps the current daemon log bounded and retains a small number of backups.
class DaemonLogFileWriter {
  DaemonLogFileWriter(
    this.file, {
    this.maxBytes = 10 * 1024 * 1024,
    this.backupCount = 3,
  }) : assert(maxBytes > 0),
       assert(backupCount >= 0) {
    file.createSync(recursive: true);
    _size = file.lengthSync();
  }

  final File file;
  final int maxBytes;
  final int backupCount;
  late int _size;

  void writeLine(String line) {
    final content = '$line\n';
    final bytes = utf8.encode(content).length;
    if (_size > 0 && _size + bytes > maxBytes) {
      _rotate();
    }
    file.writeAsStringSync(content, mode: FileMode.append);
    _size += bytes;
  }

  void _rotate() {
    if (backupCount == 0) {
      file.writeAsStringSync('');
    } else {
      final oldest = File('${file.path}.$backupCount');
      if (oldest.existsSync()) oldest.deleteSync();
      for (var index = backupCount - 1; index >= 1; index--) {
        final source = File('${file.path}.$index');
        if (source.existsSync()) source.renameSync('${file.path}.${index + 1}');
      }
      file.renameSync('${file.path}.1');
      file.createSync();
    }
    _size = 0;
  }
}
