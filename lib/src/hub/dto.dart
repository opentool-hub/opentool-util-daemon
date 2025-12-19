import 'package:json_annotation/json_annotation.dart';

part 'dto.g.dart';

@JsonSerializable()
class LoginInfo {
  final String username;
  final String password;

  LoginInfo({required this.username, required this.password});

  factory LoginInfo.fromJson(Map<String, dynamic> json) =>
      _$LoginInfoFromJson(json);

  Map<String, dynamic> toJson() => _$LoginInfoToJson(this);
}

@JsonSerializable()
class LoginResult {
  final String token;
  final String repo;

  LoginResult({required this.token, required this.repo});

  factory LoginResult.fromJson(Map<String, dynamic> json) =>
      _$LoginResultFromJson(json);

  Map<String, dynamic> toJson() => _$LoginResultToJson(this);
}

@JsonSerializable()
class PushResult {
  final String digest;
  final int size;
  final String location;

  PushResult({
    required this.digest,
    required this.size,
    required this.location,
  });

  factory PushResult.fromJson(Map<String, dynamic> json) =>
      _$PushResultFromJson(json);

  Map<String, dynamic> toJson() => _$PushResultToJson(this);
}

@JsonSerializable()
class Manifest {
  final String fileName;
  final ManifestConfig config;

  Manifest({required this.fileName, required this.config});

  factory Manifest.fromJson(Map<String, dynamic> json) =>
      _$ManifestFromJson(json);

  Map<String, dynamic> toJson() => _$ManifestToJson(this);
}

@JsonSerializable()
class ManifestConfig {
  final String digest;
  final int size;

  ManifestConfig({required this.digest, required this.size});

  factory ManifestConfig.fromJson(Map<String, dynamic> json) =>
      _$ManifestConfigFromJson(json);

  Map<String, dynamic> toJson() => _$ManifestConfigToJson(this);
}
