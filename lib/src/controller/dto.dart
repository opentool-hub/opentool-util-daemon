import 'package:json_annotation/json_annotation.dart';
import '../constants.dart';
import '../service/model.dart';

part 'dto.g.dart';

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class VersionDto {
  String name;
  String version;

  VersionDto({required this.name, required this.version});

  factory VersionDto.fromJson(Map<String, dynamic> json) => _$VersionDtoFromJson(json);

  Map<String, dynamic> toJson() => _$VersionDtoToJson(this);

  factory VersionDto.fromModel(VersionModel model) => VersionDto(
    name: model.name,
    version: model.version,
  );
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class LoginInfoDto {
  String registry;
  String username;
  String password;

  LoginInfoDto({
    this.registry  = DEFAULT_REGISTRY,
    required this.username,
    required this.password,
  });

  factory LoginInfoDto.fromJson(Map<String, dynamic> json) => _$LoginInfoDtoFromJson(json);

  Map<String, dynamic> toJson() => _$LoginInfoDtoToJson(this);

  LoginInfoModel toModel() => LoginInfoModel(
    registry: registry,
    username: username,
    password: password,
  );
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class LoginResultDto {
  String registry;
  String username;

  LoginResultDto({
    required this.registry,
    required this.username,
  });

  factory LoginResultDto.fromJson(Map<String, dynamic> json) => _$LoginResultDtoFromJson(json);

  Map<String, dynamic> toJson() => _$LoginResultDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class UserInfoDto {
  String? registry;
  String? username;

  UserInfoDto({
    this.registry,
    this.username,
  });

  factory UserInfoDto.fromJson(Map<String, dynamic> json) => _$UserInfoDtoFromJson(json);

  Map<String, dynamic> toJson() => _$UserInfoDtoToJson(this);

  factory UserInfoDto.fromModel(UserInfo userInfo) => UserInfoDto(
    registry: userInfo.registry,
    username: userInfo.username,
  );
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class OpenToolServerDto {
  String id;
  String alias;
  String registry;
  String repo;
  String name;
  String tag;

  OpenToolServerDto({
    required this.id,
    required this.alias,
    required this.registry,
    required this.repo,
    required this.name,
    required this.tag,
  });

  factory OpenToolServerDto.fromJson(Map<String, dynamic> json) => _$OpenToolServerDtoFromJson(json);

  Map<String, dynamic> toJson() => _$OpenToolServerDtoToJson(this);

  factory OpenToolServerDto.fromModel(ServerModel model) => OpenToolServerDto(
    id: model.id,
    alias: model.alias,
    registry: model.registry,
    repo: model.repo,
    name: model.name,
    tag: model.tag,
  );
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class EventMessageDto {
  String message;

  EventMessageDto({
    required this.message,
  });

  factory EventMessageDto.fromJson(Map<String, dynamic> json) => _$EventMessageDtoFromJson(json);

  Map<String, dynamic> toJson() => _$EventMessageDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class BuildInfoDto {
  String opentoolfile;
  String name;
  String? tag;

  BuildInfoDto({
    required this.opentoolfile,
    required this.name,
    this.tag
  });

  factory BuildInfoDto.fromJson(Map<String, dynamic> json) => _$BuildInfoDtoFromJson(json);

  Map<String, dynamic> toJson() => _$BuildInfoDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class CommandOutputDto {
  String script;
  String output;

  CommandOutputDto({
    required this.script,
    required this.output,
  });

  factory CommandOutputDto.fromJson(Map<String, dynamic> json) => _$CommandOutputDtoFromJson(json);

  Map<String, dynamic> toJson() => _$CommandOutputDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class PushStartDto {
  String serverId;
  int sizeByByte;
  String digest;

  PushStartDto({
    required this.serverId,
    required this.sizeByByte,
    required this.digest,
  });

  factory PushStartDto.fromJson(Map<String, dynamic> json) => _$PushStartDtoFromJson(json);

  Map<String, dynamic> toJson() => _$PushStartDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class PushUploadDto {
  String serverId;
  int percent;

  PushUploadDto({
    required this.serverId,
    required this.percent,
  });

  factory PushUploadDto.fromJson(Map<String, dynamic> json) => _$PushUploadDtoFromJson(json);

  Map<String, dynamic> toJson() => _$PushUploadDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class PullInfoDto {
  String name;
  String? tag;

  PullInfoDto({
    required this.name,
    this.tag,
  });

  factory PullInfoDto.fromJson(Map<String, dynamic> json) => _$PullInfoDtoFromJson(json);

  Map<String, dynamic> toJson() => _$PullInfoDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class PullStartDto {
  PullInfoDto pullInfoDto;
  int sizeByByte;
  String digest;

  PullStartDto({
    required this.pullInfoDto,
    required this.sizeByByte,
    required this.digest,
  });

  factory PullStartDto.fromJson(Map<String, dynamic> json) => _$PullStartDtoFromJson(json);

  Map<String, dynamic> toJson() => _$PullStartDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class PullDownloadDto {
  PullInfoDto pullInfoDto;
  int percent;

  PullDownloadDto({
    required this.pullInfoDto,
    required this.percent,
  });

  factory PullDownloadDto.fromJson(Map<String, dynamic> json) => _$PullDownloadDtoFromJson(json);

  Map<String, dynamic> toJson() => _$PullDownloadDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ServerIdDto {
  String id;

  ServerIdDto({
    required this.id,
  });

  factory ServerIdDto.fromJson(Map<String, dynamic> json) => _$ServerIdDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ServerIdDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class CommandResultDto {
  String command;
  String? output;
  String? error;

  CommandResultDto({
    required this.command,
    this.output,
    this.error,
  });

  factory CommandResultDto.fromJson(Map<String, dynamic> json) => _$CommandResultDtoFromJson(json);

  Map<String, dynamic> toJson() => _$CommandResultDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ToolDto {
  String id;
  String alias;
  String host;
  int port;
  String apiKey;
  String status;

  ToolDto({
    required this.id,
    required this.alias,
    required this.host,
    required this.port,
    required this.apiKey,
    required this.status,
  });

  factory ToolDto.fromJson(Map<String, dynamic> json) => _$ToolDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ToolDtoToJson(this);

  factory ToolDto.fromModel(ToolModel tool) => ToolDto(
    id: tool.id,
    alias: tool.alias,
    host: tool.host,
    port: tool.port,
    apiKey: tool.apiKey,
    status: tool.status,
  );
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class StartInfoDto {
  String? hostType;

  StartInfoDto({
    this.hostType,
  });

  factory StartInfoDto.fromJson(Map<String, dynamic> json) => _$StartInfoDtoFromJson(json);

  Map<String, dynamic> toJson() => _$StartInfoDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ListToolInfoDto {
  String? all;

  ListToolInfoDto({
    this.all,
  });

  factory ListToolInfoDto.fromJson(Map<String, dynamic> json) => _$ListToolInfoDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ListToolInfoDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ToolIdDto {
  String id;

  ToolIdDto({
    required this.id,
  });

  factory ToolIdDto.fromJson(Map<String, dynamic> json) => _$ToolIdDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ToolIdDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class PathDto {
  String path;

  PathDto({
    required this.path,
  });

  factory PathDto.fromJson(Map<String, dynamic> json) => _$PathDtoFromJson(json);

  Map<String, dynamic> toJson() => _$PathDtoToJson(this);
}