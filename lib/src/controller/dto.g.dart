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
      namespace: json['namespace'] as String,
      version: json['version'] as String,
      repo: json['repo'] as String,
      name: json['name'] as String,
      tag: json['tag'] as String,
      source: json['source'] == null
          ? null
          : ServerSourceDto.fromJson(json['source'] as Map<String, dynamic>),
      platform: json['platform'] == null
          ? null
          : ServerPlatformDto.fromJson(
              json['platform'] as Map<String, dynamic>,
            ),
      size: (json['size'] as num?)?.toInt(),
      installedAt: json['installedAt'] == null
          ? null
          : DateTime.parse(json['installedAt'] as String),
    );

Map<String, dynamic> _$OpenToolServerDtoToJson(OpenToolServerDto instance) {
  final val = <String, dynamic>{
    'id': instance.id,
    'alias': instance.alias,
    'registry': instance.registry,
    'namespace': instance.namespace,
    'version': instance.version,
    'repo': instance.repo,
    'name': instance.name,
    'tag': instance.tag,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('source', instance.source?.toJson());
  writeNotNull('platform', instance.platform?.toJson());
  writeNotNull('size', instance.size);
  writeNotNull('installedAt', instance.installedAt?.toIso8601String());
  return val;
}

ServerSourceDto _$ServerSourceDtoFromJson(Map<String, dynamic> json) =>
    ServerSourceDto(
      registry: json['registry'] as String,
      namespace: json['namespace'] as String,
      name: json['name'] as String,
      version: json['version'] as String,
      versionDigest: json['versionDigest'] as String?,
      artifactId: json['artifactId'] as String?,
      artifactDigest: json['artifactDigest'] as String?,
      artifactMediaType: json['artifactMediaType'] as String?,
    );

Map<String, dynamic> _$ServerSourceDtoToJson(ServerSourceDto instance) {
  final val = <String, dynamic>{
    'registry': instance.registry,
    'namespace': instance.namespace,
    'name': instance.name,
    'version': instance.version,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('versionDigest', instance.versionDigest);
  writeNotNull('artifactId', instance.artifactId);
  writeNotNull('artifactDigest', instance.artifactDigest);
  writeNotNull('artifactMediaType', instance.artifactMediaType);
  return val;
}

ServerPlatformDto _$ServerPlatformDtoFromJson(Map<String, dynamic> json) =>
    ServerPlatformDto(
      os: json['os'] as String,
      arch: json['arch'] as String,
      abi: json['abi'] as String,
    );

Map<String, dynamic> _$ServerPlatformDtoToJson(ServerPlatformDto instance) =>
    <String, dynamic>{
      'os': instance.os,
      'arch': instance.arch,
      'abi': instance.abi,
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

PullInfoDto _$PullInfoDtoFromJson(Map<String, dynamic> json) => PullInfoDto(
  registry: json['registry'] as String? ?? DEFAULT_REGISTRY,
  namespace: json['namespace'] as String,
  name: json['name'] as String,
  version: json['version'] as String,
  client: json['client'] as String?,
);

Map<String, dynamic> _$PullInfoDtoToJson(PullInfoDto instance) {
  final val = <String, dynamic>{
    'registry': instance.registry,
    'namespace': instance.namespace,
    'name': instance.name,
    'version': instance.version,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('client', instance.client);
  return val;
}

PullStartDto _$PullStartDtoFromJson(Map<String, dynamic> json) =>
    PullStartDto(stage: json['stage'] as String, ref: json['ref'] as String);

Map<String, dynamic> _$PullStartDtoToJson(PullStartDto instance) =>
    <String, dynamic>{'stage': instance.stage, 'ref': instance.ref};

PullDownloadDto _$PullDownloadDtoFromJson(Map<String, dynamic> json) =>
    PullDownloadDto(
      stage: json['stage'] as String,
      downloadedBytes: (json['downloadedBytes'] as num?)?.toInt(),
      totalBytes: (json['totalBytes'] as num?)?.toInt(),
      percent: (json['percent'] as num?)?.toInt(),
      digest: json['digest'] as String?,
    );

Map<String, dynamic> _$PullDownloadDtoToJson(PullDownloadDto instance) {
  final val = <String, dynamic>{'stage': instance.stage};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('downloadedBytes', instance.downloadedBytes);
  writeNotNull('totalBytes', instance.totalBytes);
  writeNotNull('percent', instance.percent);
  writeNotNull('digest', instance.digest);
  return val;
}

PullDoneDto _$PullDoneDtoFromJson(Map<String, dynamic> json) => PullDoneDto(
  stage: json['stage'] as String? ?? 'installed',
  server: OpenToolServerDto.fromJson(json['server'] as Map<String, dynamic>),
);

Map<String, dynamic> _$PullDoneDtoToJson(PullDoneDto instance) =>
    <String, dynamic>{
      'stage': instance.stage,
      'server': instance.server.toJson(),
    };

PullErrorDto _$PullErrorDtoFromJson(Map<String, dynamic> json) => PullErrorDto(
  code: json['code'] as String,
  message: json['message'] as String,
  retryable: json['retryable'] as bool,
  requestId: json['requestId'] as String?,
);

Map<String, dynamic> _$PullErrorDtoToJson(PullErrorDto instance) {
  final val = <String, dynamic>{
    'code': instance.code,
    'message': instance.message,
    'retryable': instance.retryable,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('requestId', instance.requestId);
  return val;
}

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

ToolServerDto _$ToolServerDtoFromJson(Map<String, dynamic> json) =>
    ToolServerDto(
      repo: json['repo'] as String,
      name: json['name'] as String,
      tag: json['tag'] as String,
    );

Map<String, dynamic> _$ToolServerDtoToJson(ToolServerDto instance) =>
    <String, dynamic>{
      'repo': instance.repo,
      'name': instance.name,
      'tag': instance.tag,
    };

ToolDto _$ToolDtoFromJson(Map<String, dynamic> json) => ToolDto(
  id: json['id'] as String,
  alias: json['alias'] as String,
  host: json['host'] as String,
  port: (json['port'] as num).toInt(),
  status: json['status'] as String,
  serverId: json['serverId'] as String?,
  server: json['server'] == null
      ? null
      : ToolServerDto.fromJson(json['server'] as Map<String, dynamic>),
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
  writeNotNull('server', instance.server?.toJson());
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
      server: json['server'] == null
          ? null
          : ToolServerDto.fromJson(json['server'] as Map<String, dynamic>),
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
  writeNotNull('server', instance.server?.toJson());
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
