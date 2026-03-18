import 'dart:convert';
import 'dart:io';
import 'package:json_annotation/json_annotation.dart';
import 'package:logging/logging.dart';
import 'package:opentool_dart/opentool_client.dart';
import 'package:yaml/yaml.dart';
import 'constants.dart';

part 'config.g.dart';

final Config config = initConfig();

Config initConfig() {
  final String configFilePath =
      '${Directory.current.path}${Platform.pathSeparator}bin${Platform.pathSeparator}config.json';
  final String fallbackVersion = getVersionFromPubspec() ?? '0.0.0';
  final File configFile = File(configFilePath);

  Config buildDefaultConfig() =>
      Config(version: fallbackVersion, server: Server(), log: Log());

  if (!configFile.existsSync()) {
    return buildDefaultConfig();
  }

  try {
    final String configJsonString = configFile.readAsStringSync();
    final Map<String, dynamic> configJson = jsonDecode(configJsonString);
    final Config loadedConfig = Config.fromJson(configJson);
    loadedConfig.server ??= Server();
    loadedConfig.log ??= Log();
    final String resolvedVersion = fallbackVersion.isNotEmpty
        ? fallbackVersion
        : (loadedConfig.version.isEmpty ? '0.0.0' : loadedConfig.version);
    loadedConfig.version = resolvedVersion;
    return loadedConfig;
  } catch (_) {
    return buildDefaultConfig();
  }
}

String? getVersionFromPubspec() {
  String pubspecFilePath =
      '${Directory.current.path}${Platform.pathSeparator}pubspec.yaml';
  File pubspecFile = File(pubspecFilePath);
  if (!pubspecFile.existsSync()) return null;

  String pubspecYamlString = pubspecFile.readAsStringSync();
  final YamlMap pubspecYaml = loadYaml(pubspecYamlString);
  return pubspecYaml['version'];
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
