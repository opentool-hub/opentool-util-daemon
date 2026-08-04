import 'dart:convert';
import 'dart:io';
import 'package:json_annotation/json_annotation.dart';
import 'package:logging/logging.dart';
import 'package:opentool_dart/opentool_client.dart';
import 'constants.dart';
import 'version.dart';

part 'config.g.dart';

Config config = initConfig();

Config initConfig({String? configFilePath, bool strict = false}) {
  final resolvedConfigFilePath =
      configFilePath ??
      '${Directory.current.path}${Platform.pathSeparator}bin${Platform.pathSeparator}config.json';
  const String fallbackVersion = daemonVersion;
  final File configFile = File(resolvedConfigFilePath);

  Config buildDefaultConfig() =>
      Config(version: fallbackVersion, server: Server(), log: Log());

  if (!configFile.existsSync()) {
    if (strict) {
      throw FileSystemException(
        'Config file does not exist',
        resolvedConfigFilePath,
      );
    }
    return buildDefaultConfig();
  }

  try {
    final String configJsonString = configFile.readAsStringSync();
    final Map<String, dynamic> configJson = jsonDecode(configJsonString);
    configJson['version'] = fallbackVersion;
    final Config loadedConfig = Config.fromJson(configJson);
    loadedConfig.server ??= Server();
    loadedConfig.log ??= Log();
    loadedConfig.version = fallbackVersion;
    return loadedConfig;
  } catch (_) {
    if (strict) rethrow;
    return buildDefaultConfig();
  }
}

String? configPathFromArgs(List<String> args) {
  String? configPath;
  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if (argument == '--config') {
      if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
        throw const FormatException('--config requires a file path');
      }
      configPath = args[++index];
    } else if (argument.startsWith('--config=')) {
      configPath = argument.substring('--config='.length);
      if (configPath.isEmpty) {
        throw const FormatException('--config requires a file path');
      }
    }
  }
  return configPath;
}

@JsonSerializable(createToJson: false)
class Config {
  String version;
  Server? server;
  Log? log;
  bool autoRestore;

  Config({
    required this.version,
    this.server,
    this.log,
    this.autoRestore = false,
  });

  factory Config.fromJson(Map<String, dynamic> json) => _$ConfigFromJson(json);
}

@JsonSerializable(createToJson: false)
class Server {
  String host;
  String prefix;
  int port;

  Server({
    this.host = HostType.LOCALHOST,
    this.prefix = DAEMON_DEFAULT_PREFIX,
    this.port = DAEMON_DEFAULT_PORT,
  });

  factory Server.fromJson(Map<String, dynamic> json) => _$ServerFromJson(json);
}

class Log {
  late Level level;

  Log({this.level = Level.INFO});

  factory Log.fromJson(Map<String, dynamic> json) {
    String levelString = json['level'] as String;
    return Log(level: _convertToLevel(levelString));
  }

  static Level _convertToLevel(String level) {
    switch (level) {
      case "ALL":
        return Level.ALL;
      case "FINEST":
        return Level.FINEST;
      case "FINER":
        return Level.FINER;
      case "FINE":
        return Level.FINE;
      case "CONFIG":
        return Level.CONFIG;
      case "INFO":
        return Level.INFO;
      case "WARNING":
        return Level.WARNING;
      case "SEVERE":
        return Level.SEVERE;
      case "SHOUT":
        return Level.SHOUT;
      case "OFF":
        return Level.OFF;
      default:
        return Level.INFO;
    }
  }
}
