// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OpentoolfileConfig _$OpentoolfileConfigFromJson(Map<String, dynamic> json) =>
    OpentoolfileConfig(
      name: json['name'] as String,
      tag: json['tag'] as String?,
      os: json['os'] as String,
      cpuArch: json['cpuArch'] as String,
      build: OpenToolBuild.fromJson(json['build'] as Map<String, dynamic>),
      run: OpenToolRun.fromJson(json['run'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$OpentoolfileConfigToJson(OpentoolfileConfig instance) {
  final val = <String, dynamic>{
    'name': instance.name,
    'os': instance.os,
    'cpuArch': instance.cpuArch,
    'build': instance.build.toJson(),
    'run': instance.run.toJson(),
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('tag', instance.tag);
  return val;
}

OpenToolBuild _$OpenToolBuildFromJson(Map<String, dynamic> json) =>
    OpenToolBuild(
      args:
          (json['args'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, e as String),
          ) ??
          const {},
      runs:
          (json['runs'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          const [],
    );

Map<String, dynamic> _$OpenToolBuildToJson(OpenToolBuild instance) =>
    <String, dynamic>{'args': instance.args, 'runs': instance.runs};

OpenToolRun _$OpenToolRunFromJson(Map<String, dynamic> json) => OpenToolRun(
  envs:
      (json['envs'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ) ??
      const {},
  workdir: json['workdir'] as String? ?? '.',
  entrypoint: json['entrypoint'] as String,
  cmds:
      (json['cmds'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
);

Map<String, dynamic> _$OpenToolRunToJson(OpenToolRun instance) =>
    <String, dynamic>{
      'envs': instance.envs,
      'workdir': instance.workdir,
      'entrypoint': instance.entrypoint,
      'cmds': instance.cmds,
    };

OpenToolConfig _$OpenToolConfigFromJson(Map<String, dynamic> json) =>
    OpenToolConfig(
      registry: json['registry'] as String?,
      username: json['username'] as String?,
      auth: json['auth'] == null
          ? null
          : HubAuth.fromJson(json['auth'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$OpenToolConfigToJson(OpenToolConfig instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('registry', instance.registry);
  writeNotNull('username', instance.username);
  writeNotNull('auth', instance.auth?.toJson());
  return val;
}

HubAuth _$HubAuthFromJson(Map<String, dynamic> json) =>
    HubAuth(repo: json['repo'] as String, token: json['token'] as String);

Map<String, dynamic> _$HubAuthToJson(HubAuth instance) => <String, dynamic>{
  'repo': instance.repo,
  'token': instance.token,
};
