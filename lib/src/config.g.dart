// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Config _$ConfigFromJson(Map<String, dynamic> json) => Config(
  version: json['version'] as String,
  server: json['server'] == null
      ? null
      : Server.fromJson(json['server'] as Map<String, dynamic>),
  log: json['log'] == null
      ? null
      : Log.fromJson(json['log'] as Map<String, dynamic>),
  autoRestore: json['autoRestore'] as bool? ?? false,
);

Server _$ServerFromJson(Map<String, dynamic> json) => Server(
  host: json['host'] as String? ?? HostType.LOCALHOST,
  prefix: json['prefix'] as String? ?? DAEMON_DEFAULT_PREFIX,
  port: (json['port'] as num?)?.toInt() ?? DAEMON_DEFAULT_PORT,
);
