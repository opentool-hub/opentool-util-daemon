// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LoginInfo _$LoginInfoFromJson(Map<String, dynamic> json) => LoginInfo(
  username: json['username'] as String,
  password: json['password'] as String,
);

Map<String, dynamic> _$LoginInfoToJson(LoginInfo instance) => <String, dynamic>{
  'username': instance.username,
  'password': instance.password,
};

LoginResult _$LoginResultFromJson(Map<String, dynamic> json) =>
    LoginResult(token: json['token'] as String, repo: json['repo'] as String);

Map<String, dynamic> _$LoginResultToJson(LoginResult instance) =>
    <String, dynamic>{'token': instance.token, 'repo': instance.repo};

PushResult _$PushResultFromJson(Map<String, dynamic> json) => PushResult(
  digest: json['digest'] as String,
  size: (json['size'] as num).toInt(),
  location: json['location'] as String,
);

Map<String, dynamic> _$PushResultToJson(PushResult instance) =>
    <String, dynamic>{
      'digest': instance.digest,
      'size': instance.size,
      'location': instance.location,
    };

Manifest _$ManifestFromJson(Map<String, dynamic> json) => Manifest(
  fileName: json['fileName'] as String,
  config: ManifestConfig.fromJson(json['config'] as Map<String, dynamic>),
);

Map<String, dynamic> _$ManifestToJson(Manifest instance) => <String, dynamic>{
  'fileName': instance.fileName,
  'config': instance.config,
};

ManifestConfig _$ManifestConfigFromJson(Map<String, dynamic> json) =>
    ManifestConfig(
      digest: json['digest'] as String,
      size: (json['size'] as num).toInt(),
    );

Map<String, dynamic> _$ManifestConfigToJson(ManifestConfig instance) =>
    <String, dynamic>{'digest': instance.digest, 'size': instance.size};
