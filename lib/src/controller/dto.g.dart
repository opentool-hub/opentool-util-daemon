// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

VersionDto _$VersionDtoFromJson(Map<String, dynamic> json) => VersionDto(
      version: json['version'] as String,
    );

Map<String, dynamic> _$VersionDtoToJson(VersionDto instance) =>
    <String, dynamic>{
      'version': instance.version,
    };

OpenToolServerDto _$OpenToolServerDtoFromJson(Map<String, dynamic> json) =>
    OpenToolServerDto(
      id: json['id'] as String,
      name: json['name'] as String,
      file: json['file'] as String,
      port: (json['port'] as num).toInt(),
      pid: (json['pid'] as num?)?.toInt(),
    );

Map<String, dynamic> _$OpenToolServerDtoToJson(OpenToolServerDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'file': instance.file,
      'port': instance.port,
      if (instance.pid case final value?) 'pid': value,
    };

ServerIdDto _$ServerIdDtoFromJson(Map<String, dynamic> json) => ServerIdDto(
      id: json['id'] as String,
    );

Map<String, dynamic> _$ServerIdDtoToJson(ServerIdDto instance) =>
    <String, dynamic>{
      'id': instance.id,
    };

RenameDto _$RenameDtoFromJson(Map<String, dynamic> json) => RenameDto(
      id: json['id'] as String,
      name: json['name'] as String,
    );

Map<String, dynamic> _$RenameDtoToJson(RenameDto instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
    };

ServerFunctionCallDto _$ServerFunctionCallDtoFromJson(
        Map<String, dynamic> json) =>
    ServerFunctionCallDto(
      id: json['id'] as String,
      functionCall: FunctionCallDto.fromJson(
          json['functionCall'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$ServerFunctionCallDtoToJson(
        ServerFunctionCallDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'functionCall': instance.functionCall.toJson(),
    };

StatusDto _$StatusDtoFromJson(Map<String, dynamic> json) => StatusDto(
      id: json['id'] as String,
      status: json['status'] as String,
    );

Map<String, dynamic> _$StatusDtoToJson(StatusDto instance) => <String, dynamic>{
      'id': instance.id,
      'status': instance.status,
    };

RegisterInfo _$RegisterInfoFromJson(Map<String, dynamic> json) => RegisterInfo(
      file: json['file'] as String,
      host: json['host'] as String,
      port: (json['port'] as num).toInt(),
      prefix: json['prefix'] as String,
      apiKeys:
          (json['apiKeys'] as List<dynamic>?)?.map((e) => e as String).toList(),
      pid: (json['pid'] as num).toInt(),
    );

Map<String, dynamic> _$RegisterInfoToJson(RegisterInfo instance) =>
    <String, dynamic>{
      'file': instance.file,
      'host': instance.host,
      'port': instance.port,
      'prefix': instance.prefix,
      if (instance.apiKeys case final value?) 'apiKeys': value,
      'pid': instance.pid,
    };

RegisterResult _$RegisterResultFromJson(Map<String, dynamic> json) =>
    RegisterResult(
      id: json['id'] as String,
      error: json['error'] as String?,
    );

Map<String, dynamic> _$RegisterResultToJson(RegisterResult instance) =>
    <String, dynamic>{
      'id': instance.id,
      if (instance.error case final value?) 'error': value,
    };

FunctionCallDto _$FunctionCallDtoFromJson(Map<String, dynamic> json) =>
    FunctionCallDto(
      id: json['id'] as String,
      name: json['name'] as String,
      arguments: json['arguments'] as Map<String, dynamic>,
    );

Map<String, dynamic> _$FunctionCallDtoToJson(FunctionCallDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'arguments': instance.arguments,
    };

ToolReturnDto _$ToolReturnDtoFromJson(Map<String, dynamic> json) =>
    ToolReturnDto(
      id: json['id'] as String,
      result: json['result'] as Map<String, dynamic>,
    );

Map<String, dynamic> _$ToolReturnDtoToJson(ToolReturnDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'result': instance.result,
    };
