import 'package:json_annotation/json_annotation.dart';
import 'package:opentool_dart/opentool_dart.dart';
import '../service/model.dart';

part 'dto.g.dart';

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class VersionDto {
  late String version;

  VersionDto({required this.version});

  factory VersionDto.fromJson(Map<String, dynamic> json) => _$VersionDtoFromJson(json);

  Map<String, dynamic> toJson() => _$VersionDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class OpenToolServerDto{
  String id;
  String name;
  String file;
  int port;
  int? pid;

  OpenToolServerDto({
    required this.id,
    required this.name,
    required this.file,
    required this.port,
    this.pid,
  });

  factory OpenToolServerDto.fromModel(OpenToolServerModel serverModel) {
    return OpenToolServerDto(
      id: serverModel.id,
      name: serverModel.name,
      file: serverModel.file,
      port: serverModel.port,
      pid: serverModel.pid,
    );
  }

  factory OpenToolServerDto.fromJson(Map<String, dynamic> json) => _$OpenToolServerDtoFromJson(json);

  Map<String, dynamic> toJson() => _$OpenToolServerDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ServerIdDto {
  String id;
  ServerIdDto({required this.id});

  factory ServerIdDto.fromJson(Map<String, dynamic> json) => _$ServerIdDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ServerIdDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class RenameDto extends ServerIdDto {
  String name;

  RenameDto({required super.id, required this.name});

  factory RenameDto.fromJson(Map<String, dynamic> json) => _$RenameDtoFromJson(json);

  Map<String, dynamic> toJson() => _$RenameDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ServerFunctionCallDto extends ServerIdDto {
  FunctionCallDto functionCall;
  ServerFunctionCallDto({required super.id, required this.functionCall});

  factory ServerFunctionCallDto.fromJson(Map<String, dynamic> json) => _$ServerFunctionCallDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ServerFunctionCallDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class StatusDto extends ServerIdDto{
  String status;
  StatusDto({required super.id, required this.status});

  factory StatusDto.fromJson(Map<String, dynamic> json) => _$StatusDtoFromJson(json);

  Map<String, dynamic> toJson() => _$StatusDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class RegisterInfo {
  String file;
  String host;
  int port;
  String prefix;
  List<String>? apiKeys;
  int pid;

  RegisterInfo({required this.file, required this.host, required this.port, required this.prefix, this.apiKeys, required this.pid});

  factory RegisterInfo.fromJson(Map<String, dynamic> json) => _$RegisterInfoFromJson(json);

  Map<String, dynamic> toJson() => _$RegisterInfoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class RegisterResult extends ServerIdDto{
  String? error;
  RegisterResult({required super.id, this.error});

  factory RegisterResult.fromJson(Map<String, dynamic> json) => _$RegisterResultFromJson(json);

  Map<String, dynamic> toJson() => _$RegisterResultToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class FunctionCallDto {
  late String id;
  late String name;
  late Map<String, dynamic> arguments;

  FunctionCallDto({required this.id, required this.name, required this.arguments});

  factory FunctionCallDto.fromJson(Map<String, dynamic> json) => _$FunctionCallDtoFromJson(json);

  Map<String, dynamic> toJson() => _$FunctionCallDtoToJson(this);

  FunctionCall toModel() => FunctionCall(
      id: id,
      name: name,
      arguments: arguments
  );
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ToolReturnDto {
  late String id;
  late Map<String, dynamic> result;

  ToolReturnDto({required this.id, required this.result});

  factory ToolReturnDto.fromJson(Map<String, dynamic> json) => _$ToolReturnDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ToolReturnDtoToJson(this);

  factory ToolReturnDto.fromModel(ToolReturn toolReturn) => ToolReturnDto(
    id: toolReturn.id,
    result: toolReturn.result
  );
}
