import 'dart:io';
import 'package:logging/logging.dart';

enum LogModule { http }

DaemonLogger logger = DaemonLogger(Level.INFO);

class DaemonLogger {
  static final DaemonLogger _singleton = DaemonLogger._internal();
  static Level _level = Level.INFO;

  factory DaemonLogger(Level level) {
    _level = level;
    return _singleton;
  }

  Logger? _logger;
  late File _logFile;

  DaemonLogger._internal() {
    _logger = Logger('OpenToolDaemonLogger');
    Logger.root.level = _level;
    _logFile = File('${Directory.current.path}${Platform.pathSeparator}log${Platform.pathSeparator}daemon.log');
    _logFile.createSync(recursive: true);

    Logger.root.onRecord.listen((record) {
      final message =
          '${record.level.name}: ${record.time}: PID $pid: ${record.message}';
      print(message);
      _logFile.writeAsStringSync('$message\n', mode: FileMode.append);
    });
  }

  void log(LogModule module, String message, {String detail = "{}", Level level = Level.INFO}) {
    _logger?.log(level, "[${module.name.toUpperCase()}] $message - $detail");
  }
}
