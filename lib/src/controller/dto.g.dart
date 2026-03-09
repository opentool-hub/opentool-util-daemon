// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

VersionDto _$VersionDtoFromJson(Map<String, dynamic> json) => VersionDto(
  name: json['name'] as String,
  version: json['version'] as String,
);

Map<String, dynamic> _$VersionDtoToJson(VersionDto instance) =>
    <String, dynamic>{'name': instance.name, 'version': instance.version};

LoginInfoDto _$LoginInfoDtoFromJson(Map<String, dynamic> json) => LoginInfoDto(
  registry: json['registry'] as String? ?? DEFAULT_REGISTRY,
  username: json['username'] as String,
  password: json['password'] as String,
);

Map<String, dynamic> _$LoginInfoDtoToJson(LoginInfoDto instance) =>
    <String, dynamic>{
      'registry': instance.registry,
      'username': instance.username,
      'password': instance.password,
    };

LoginResultDto _$LoginResultDtoFromJson(Map<String, dynamic> json) =>
    LoginResultDto(
      registry: json['registry'] as String,
      username: json['username'] as String,
    );

Map<String, dynamic> _$LoginResultDtoToJson(LoginResultDto instance) =>
    <String, dynamic>{
      'registry': instance.registry,
      'username': instance.username,
    };

UserInfoDto _$UserInfoDtoFromJson(Map<String, dynamic> json) => UserInfoDto(
  registry: json['registry'] as String?,
  username: json['username'] as String?,
);

Map<String, dynamic> _$UserInfoDtoToJson(UserInfoDto instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('registry', instance.registry);
  writeNotNull('username', instance.username);
  return val;
}

CreateApiKeyDto _$CreateApiKeyDtoFromJson(Map<String, dynamic> json) =>
    CreateApiKeyDto(name: json['name'] as String?);

Map<String, dynamic> _$CreateApiKeyDtoToJson(CreateApiKeyDto instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('name', instance.name);
  return val;
}

ApiKeyDto _$ApiKeyDtoFromJson(Map<String, dynamic> json) => ApiKeyDto(
  name: json['name'] as String,
  apiKey: json['apiKey'] as String,
  createdAt: DateTime.parse(json['createdAt'] as String),
);

Map<String, dynamic> _$ApiKeyDtoToJson(ApiKeyDto instance) => <String, dynamic>{
  'name': instance.name,
  'apiKey': instance.apiKey,
  'createdAt': instance.createdAt.toIso8601String(),
};

OpenToolServerDto _$OpenToolServerDtoFromJson(Map<String, dynamic> json) =>
    OpenToolServerDto(
      id: json['id'] as String,
      alias: json['alias'] as String,
      registry: json['registry'] as String,
      repo: json['repo'] as String,
      name: json['name'] as String,
      tag: json['tag'] as String,
    );

Map<String, dynamic> _$OpenToolServerDtoToJson(OpenToolServerDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'alias': instance.alias,
      'registry': instance.registry,
      'repo': instance.repo,
      'name': instance.name,
      'tag': instance.tag,
    };

EventMessageDto _$EventMessageDtoFromJson(Map<String, dynamic> json) =>
    EventMessageDto(message: json['message'] as String);

Map<String, dynamic> _$EventMessageDtoToJson(EventMessageDto instance) =>
    <String, dynamic>{'message': instance.message};

BuildInfoDto _$BuildInfoDtoFromJson(Map<String, dynamic> json) => BuildInfoDto(
  opentoolfile: json['opentoolfile'] as String,
  name: json['name'] as String,
  tag: json['tag'] as String?,
);

Map<String, dynamic> _$BuildInfoDtoToJson(BuildInfoDto instance) {
  final val = <String, dynamic>{
    'opentoolfile': instance.opentoolfile,
    'name': instance.name,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('tag', instance.tag);
  return val;
}

CommandOutputDto _$CommandOutputDtoFromJson(Map<String, dynamic> json) =>
    CommandOutputDto(
      script: json['script'] as String,
      output: json['output'] as String,
    );

Map<String, dynamic> _$CommandOutputDtoToJson(CommandOutputDto instance) =>
    <String, dynamic>{'script': instance.script, 'output': instance.output};

PushStartDto _$PushStartDtoFromJson(Map<String, dynamic> json) => PushStartDto(
  serverId: json['serverId'] as String,
  sizeByByte: (json['sizeByByte'] as num).toInt(),
  digest: json['digest'] as String,
);

Map<String, dynamic> _$PushStartDtoToJson(PushStartDto instance) =>
    <String, dynamic>{
      'serverId': instance.serverId,
      'sizeByByte': instance.sizeByByte,
      'digest': instance.digest,
    };

PushUploadDto _$PushUploadDtoFromJson(Map<String, dynamic> json) =>
    PushUploadDto(
      serverId: json['serverId'] as String,
      percent: (json['percent'] as num).toInt(),
    );

Map<String, dynamic> _$PushUploadDtoToJson(PushUploadDto instance) =>
    <String, dynamic>{
      'serverId': instance.serverId,
      'percent': instance.percent,
    };

PullInfoDto _$PullInfoDtoFromJson(Map<String, dynamic> json) =>
    PullInfoDto(name: json['name'] as String, tag: json['tag'] as String?);

Map<String, dynamic> _$PullInfoDtoToJson(PullInfoDto instance) {
  final val = <String, dynamic>{'name': instance.name};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('tag', instance.tag);
  return val;
}

PullStartDto _$PullStartDtoFromJson(Map<String, dynamic> json) => PullStartDto(
  pullInfoDto: PullInfoDto.fromJson(
    json['pullInfoDto'] as Map<String, dynamic>,
  ),
  sizeByByte: (json['sizeByByte'] as num).toInt(),
  digest: json['digest'] as String,
);

Map<String, dynamic> _$PullStartDtoToJson(PullStartDto instance) =>
    <String, dynamic>{
      'pullInfoDto': instance.pullInfoDto.toJson(),
      'sizeByByte': instance.sizeByByte,
      'digest': instance.digest,
    };

PullDownloadDto _$PullDownloadDtoFromJson(Map<String, dynamic> json) =>
    PullDownloadDto(
      pullInfoDto: PullInfoDto.fromJson(
        json['pullInfoDto'] as Map<String, dynamic>,
      ),
      percent: (json['percent'] as num).toInt(),
    );

Map<String, dynamic> _$PullDownloadDtoToJson(PullDownloadDto instance) =>
    <String, dynamic>{
      'pullInfoDto': instance.pullInfoDto.toJson(),
      'percent': instance.percent,
    };

ServerIdDto _$ServerIdDtoFromJson(Map<String, dynamic> json) =>
    ServerIdDto(id: json['id'] as String);

Map<String, dynamic> _$ServerIdDtoToJson(ServerIdDto instance) =>
    <String, dynamic>{'id': instance.id};

CommandResultDto _$CommandResultDtoFromJson(Map<String, dynamic> json) =>
    CommandResultDto(
      command: json['command'] as String,
      output: json['output'] as String?,
      error: json['error'] as String?,
    );

Map<String, dynamic> _$CommandResultDtoToJson(CommandResultDto instance) {
  final val = <String, dynamic>{'command': instance.command};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('output', instance.output);
  writeNotNull('error', instance.error);
  return val;
}

ToolDto _$ToolDtoFromJson(Map<String, dynamic> json) => ToolDto(
  id: json['id'] as String,
  alias: json['alias'] as String,
  host: json['host'] as String,
  port: (json['port'] as num).toInt(),
  status: json['status'] as String,
  serverId: json['serverId'] as String?,
);

Map<String, dynamic> _$ToolDtoToJson(ToolDto instance) {
  final val = <String, dynamic>{
    'id': instance.id,
    'alias': instance.alias,
    'host': instance.host,
    'port': instance.port,
    'status': instance.status,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('serverId', instance.serverId);
  return val;
}

ToolWithApiKeyDto _$ToolWithApiKeyDtoFromJson(Map<String, dynamic> json) =>
    ToolWithApiKeyDto(
      id: json['id'] as String,
      alias: json['alias'] as String,
      host: json['host'] as String,
      port: (json['port'] as num).toInt(),
      apiKey: json['apiKey'] as String,
      status: json['status'] as String,
      serverId: json['serverId'] as String?,
    );

Map<String, dynamic> _$ToolWithApiKeyDtoToJson(ToolWithApiKeyDto instance) {
  final val = <String, dynamic>{
    'id': instance.id,
    'alias': instance.alias,
    'host': instance.host,
    'port': instance.port,
    'apiKey': instance.apiKey,
    'status': instance.status,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('serverId', instance.serverId);
  return val;
}

ToolLifecycleEventDto _$ToolLifecycleEventDtoFromJson(
  Map<String, dynamic> json,
) => ToolLifecycleEventDto(
  type: json['type'] as String,
  reason: json['reason'] as String,
  tool: ToolDto.fromJson(json['tool'] as Map<String, dynamic>),
  occurredAt: DateTime.parse(json['occurredAt'] as String),
);

Map<String, dynamic> _$ToolLifecycleEventDtoToJson(
  ToolLifecycleEventDto instance,
) => <String, dynamic>{
  'type': instance.type,
  'reason': instance.reason,
  'tool': instance.tool.toJson(),
  'occurredAt': instance.occurredAt.toIso8601String(),
};

StartInfoDto _$StartInfoDtoFromJson(Map<String, dynamic> json) =>
    StartInfoDto(hostType: json['hostType'] as String?);

Map<String, dynamic> _$StartInfoDtoToJson(StartInfoDto instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('hostType', instance.hostType);
  return val;
}

ListToolInfoDto _$ListToolInfoDtoFromJson(Map<String, dynamic> json) =>
    ListToolInfoDto(all: json['all'] as String?);

Map<String, dynamic> _$ListToolInfoDtoToJson(ListToolInfoDto instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('all', instance.all);
  return val;
}

ToolIdDto _$ToolIdDtoFromJson(Map<String, dynamic> json) =>
    ToolIdDto(id: json['id'] as String);

Map<String, dynamic> _$ToolIdDtoToJson(ToolIdDto instance) => <String, dynamic>{
  'id': instance.id,
};

PathDto _$PathDtoFromJson(Map<String, dynamic> json) =>
    PathDto(path: json['path'] as String);

Map<String, dynamic> _$PathDtoToJson(PathDto instance) => <String, dynamic>{
  'path': instance.path,
};
