import 'package:json_annotation/json_annotation.dart';
import '../constants.dart';
import '../service/model.dart';

part 'dto.g.dart';

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class VersionDto {
  String name;
  String version;
  @JsonKey(defaultValue: 2)
  int apiVersion;
  @JsonKey(defaultValue: <String>[])
  List<String> capabilities;

  VersionDto({
    required this.name,
    required this.version,
    this.apiVersion = 2,
    this.capabilities = const [],
  });

  factory VersionDto.fromJson(Map<String, dynamic> json) =>
      _$VersionDtoFromJson(json);

  Map<String, dynamic> toJson() => _$VersionDtoToJson(this);

  factory VersionDto.fromModel(VersionModel model) => VersionDto(
    name: model.name,
    version: model.version,
    apiVersion: model.apiVersion,
    capabilities: model.capabilities,
  );
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class CreateApiKeyDto {
  String? name;

  CreateApiKeyDto({this.name});

  factory CreateApiKeyDto.fromJson(Map<String, dynamic> json) =>
      _$CreateApiKeyDtoFromJson(json);

  Map<String, dynamic> toJson() => _$CreateApiKeyDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ApiKeyDto {
  String name;
  String apiKey;
  DateTime createdAt;

  ApiKeyDto({
    required this.name,
    required this.apiKey,
    required this.createdAt,
  });

  factory ApiKeyDto.fromJson(Map<String, dynamic> json) =>
      _$ApiKeyDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ApiKeyDtoToJson(this);

  factory ApiKeyDto.fromModel(ApiKeyModel model) => ApiKeyDto(
    name: model.name,
    apiKey: model.apiKey,
    createdAt: model.createdAt,
  );
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class OpenToolServerDto {
  @JsonKey(defaultValue: 2)
  int schemaVersion;
  String id;
  String alias;
  String registry;
  String namespace;
  String version;
  String name;
  ServerSourceDto? source;
  ServerPlatformDto? platform;
  int? size;
  DateTime? createdAt;
  ServerArtifactDto? artifact;
  ServerPolicyDto? policy;
  ServerCapabilitiesDto? capabilities;
  String? state;

  OpenToolServerDto({
    this.schemaVersion = 2,
    required this.id,
    required this.alias,
    required this.registry,
    required this.namespace,
    required this.version,
    required this.name,
    this.source,
    this.platform,
    this.size,
    this.createdAt,
    this.artifact,
    this.policy,
    this.capabilities,
    this.state,
  });

  factory OpenToolServerDto.fromJson(Map<String, dynamic> json) =>
      _$OpenToolServerDtoFromJson(json);

  Map<String, dynamic> toJson() => _$OpenToolServerDtoToJson(this);

  factory OpenToolServerDto.fromModel(ServerModel model) => OpenToolServerDto(
    id: model.id,
    alias: model.alias,
    registry: model.registry,
    namespace: model.namespace,
    version: model.version,
    name: model.name,
    source: ServerSourceDto.fromModel(model),
    platform: model.platform == null
        ? null
        : ServerPlatformDto.fromModel(model.platform!),
    size: model.artifactSize,
    createdAt: model.createdAt,
    artifact: model.artifactDigest == null
        ? null
        : ServerArtifactDto.fromModel(model),
    policy: ServerPolicyDto(
      protected: model.protected,
      managedBy: model.managedBy,
    ),
    capabilities: ServerCapabilitiesDto(
      canRun: model.canRun,
      canRemove: model.canRemove,
    ),
    state: model.state,
  );
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ServerSourceDto {
  @JsonKey(defaultValue: 'import')
  String kind;
  String? registry;
  String namespace;
  String name;
  String version;
  int? versionRevision;
  String? versionDigest;
  String? artifactId;
  String? artifactDigest;
  String? artifactMediaType;

  ServerSourceDto({
    this.kind = 'import',
    this.registry,
    required this.namespace,
    required this.name,
    required this.version,
    this.versionRevision,
    this.versionDigest,
    this.artifactId,
    this.artifactDigest,
    this.artifactMediaType,
    this.builtinBundleFamily,
    this.builtinBundleId,
    this.builtinKey,
  });
  String? builtinBundleFamily;
  String? builtinBundleId;
  String? builtinKey;

  factory ServerSourceDto.fromJson(Map<String, dynamic> json) =>
      _$ServerSourceDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ServerSourceDtoToJson(this);

  factory ServerSourceDto.fromModel(ServerModel model) => ServerSourceDto(
    kind: model.sourceKind,
    registry: model.registry.isEmpty ? null : model.registry,
    namespace: model.namespace,
    name: model.name,
    version: model.version,
    versionRevision: model.versionRevision,
    versionDigest: model.versionDigest,
    artifactId: model.artifactId,
    artifactDigest: model.artifactDigest,
    artifactMediaType: model.artifactMediaType,
    builtinBundleFamily: model.builtinBundleFamily,
    builtinBundleId: model.builtinBundleId,
    builtinKey: model.builtinKey,
  );
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ServerArtifactDto {
  String digest;
  int? size;
  String? mediaType;
  ServerPlatformDto? platform;
  DateTime? verifiedAt;
  int referenceCount;

  ServerArtifactDto({
    required this.digest,
    this.size,
    this.mediaType,
    this.platform,
    this.verifiedAt,
    required this.referenceCount,
  });

  factory ServerArtifactDto.fromJson(Map<String, dynamic> json) =>
      _$ServerArtifactDtoFromJson(json);
  Map<String, dynamic> toJson() => _$ServerArtifactDtoToJson(this);

  factory ServerArtifactDto.fromModel(ServerModel model) => ServerArtifactDto(
    digest: model.artifactDigest!,
    size: model.artifactSize,
    mediaType: model.artifactMediaType,
    platform: model.platform == null
        ? null
        : ServerPlatformDto.fromModel(model.platform!),
    verifiedAt: model.artifactVerifiedAt,
    referenceCount: model.artifactReferenceCount,
  );
}

@JsonSerializable()
class ServerPolicyDto {
  bool protected;
  String managedBy;
  ServerPolicyDto({required this.protected, required this.managedBy});
  factory ServerPolicyDto.fromJson(Map<String, dynamic> json) =>
      _$ServerPolicyDtoFromJson(json);
  Map<String, dynamic> toJson() => _$ServerPolicyDtoToJson(this);
}

@JsonSerializable()
class ServerCapabilitiesDto {
  bool canRun;
  bool canRemove;
  ServerCapabilitiesDto({required this.canRun, required this.canRemove});
  factory ServerCapabilitiesDto.fromJson(Map<String, dynamic> json) =>
      _$ServerCapabilitiesDtoFromJson(json);
  Map<String, dynamic> toJson() => _$ServerCapabilitiesDtoToJson(this);
}

@JsonSerializable()
class ServerPlatformDto {
  String os;
  String arch;
  String abi;

  ServerPlatformDto({required this.os, required this.arch, required this.abi});

  factory ServerPlatformDto.fromJson(Map<String, dynamic> json) =>
      _$ServerPlatformDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ServerPlatformDtoToJson(this);

  factory ServerPlatformDto.fromModel(ServerPlatform model) =>
      ServerPlatformDto(os: model.os, arch: model.arch, abi: model.abi);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class EventMessageDto {
  String message;

  EventMessageDto({required this.message});

  factory EventMessageDto.fromJson(Map<String, dynamic> json) =>
      _$EventMessageDtoFromJson(json);

  Map<String, dynamic> toJson() => _$EventMessageDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class BuildInfoDto {
  String opentoolfile;
  String name;
  String? tag;

  BuildInfoDto({required this.opentoolfile, required this.name, this.tag});

  factory BuildInfoDto.fromJson(Map<String, dynamic> json) =>
      _$BuildInfoDtoFromJson(json);

  Map<String, dynamic> toJson() => _$BuildInfoDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class CommandOutputDto {
  String script;
  String output;

  CommandOutputDto({required this.script, required this.output});

  factory CommandOutputDto.fromJson(Map<String, dynamic> json) =>
      _$CommandOutputDtoFromJson(json);

  Map<String, dynamic> toJson() => _$CommandOutputDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class PullInfoDto {
  String registry;
  String namespace;
  String name;
  String version;
  String? client;

  PullInfoDto({
    this.registry = DEFAULT_REGISTRY,
    required this.namespace,
    required this.name,
    required this.version,
    this.client,
  });

  factory PullInfoDto.fromJson(Map<String, dynamic> json) =>
      _$PullInfoDtoFromJson(json);

  Map<String, dynamic> toJson() => _$PullInfoDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class PullStartDto {
  String stage;
  String ref;

  PullStartDto({required this.stage, required this.ref});

  factory PullStartDto.fromJson(Map<String, dynamic> json) =>
      _$PullStartDtoFromJson(json);

  Map<String, dynamic> toJson() => _$PullStartDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class PullDownloadDto {
  String stage;
  int? downloadedBytes;
  int? totalBytes;
  int? percent;
  String? digest;

  PullDownloadDto({
    required this.stage,
    this.downloadedBytes,
    this.totalBytes,
    this.percent,
    this.digest,
  });

  factory PullDownloadDto.fromJson(Map<String, dynamic> json) =>
      _$PullDownloadDtoFromJson(json);

  Map<String, dynamic> toJson() => _$PullDownloadDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class PullDoneDto {
  String stage;
  OpenToolServerDto server;

  PullDoneDto({this.stage = 'ready', required this.server});

  factory PullDoneDto.fromJson(Map<String, dynamic> json) =>
      _$PullDoneDtoFromJson(json);

  Map<String, dynamic> toJson() => _$PullDoneDtoToJson(this);
}

@JsonSerializable(includeIfNull: false)
class PullErrorDto {
  String code;
  String message;
  bool retryable;
  String? requestId;

  PullErrorDto({
    required this.code,
    required this.message,
    required this.retryable,
    this.requestId,
  });

  factory PullErrorDto.fromJson(Map<String, dynamic> json) =>
      _$PullErrorDtoFromJson(json);

  Map<String, dynamic> toJson() => _$PullErrorDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ServerIdDto {
  String id;

  ServerIdDto({required this.id});

  factory ServerIdDto.fromJson(Map<String, dynamic> json) =>
      _$ServerIdDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ServerIdDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ServerDeleteResultDto {
  String id;
  String serverId;
  bool artifactRemoved;

  ServerDeleteResultDto({
    required this.id,
    required this.serverId,
    required this.artifactRemoved,
  });

  factory ServerDeleteResultDto.fromJson(Map<String, dynamic> json) =>
      _$ServerDeleteResultDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ServerDeleteResultDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class CommandResultDto {
  String command;
  String? output;
  String? error;

  CommandResultDto({required this.command, this.output, this.error});

  factory CommandResultDto.fromJson(Map<String, dynamic> json) =>
      _$CommandResultDtoFromJson(json);

  Map<String, dynamic> toJson() => _$CommandResultDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ToolServerDto {
  String namespace;
  String name;
  String version;

  ToolServerDto({
    required this.namespace,
    required this.name,
    required this.version,
  });

  factory ToolServerDto.fromJson(Map<String, dynamic> json) =>
      _$ToolServerDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ToolServerDtoToJson(this);

  factory ToolServerDto.fromModel(ServerModel server) => ToolServerDto(
    namespace: server.namespace,
    name: server.name,
    version: server.version,
  );

  factory ToolServerDto.fromIdentity(ServerIdentity identity) => ToolServerDto(
    namespace: identity.namespace,
    name: identity.name,
    version: identity.version,
  );
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ToolDto {
  String id;
  String alias;
  String host;
  int port;
  String status;
  String? serverId;
  ToolServerDto? server;
  String? materializedArtifactDigest;
  String? contentState;

  ToolDto({
    required this.id,
    required this.alias,
    required this.host,
    required this.port,
    required this.status,
    this.serverId,
    this.server,
    this.materializedArtifactDigest,
    this.contentState,
  });

  factory ToolDto.fromJson(Map<String, dynamic> json) =>
      _$ToolDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ToolDtoToJson(this);

  factory ToolDto.fromModel(ToolModel tool, {ServerModel? server}) => ToolDto(
    id: tool.id,
    alias: tool.alias,
    host: tool.host,
    port: tool.port,
    status: tool.status,
    serverId: tool.serverId,
    materializedArtifactDigest: tool.materializedArtifactDigest,
    contentState: tool.contentState,
    server: server != null
        ? ToolServerDto.fromModel(server)
        : tool.serverIdentity == null
        ? null
        : ToolServerDto.fromIdentity(tool.serverIdentity!),
  );
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ToolWithApiKeyDto {
  String id;
  String alias;
  String host;
  int port;
  String apiKey;
  String status;
  String? serverId;
  ToolServerDto? server;
  String? materializedArtifactDigest;
  String? contentState;

  ToolWithApiKeyDto({
    required this.id,
    required this.alias,
    required this.host,
    required this.port,
    required this.apiKey,
    required this.status,
    this.serverId,
    this.server,
    this.materializedArtifactDigest,
    this.contentState,
  });

  factory ToolWithApiKeyDto.fromJson(Map<String, dynamic> json) =>
      _$ToolWithApiKeyDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ToolWithApiKeyDtoToJson(this);

  factory ToolWithApiKeyDto.fromModel(ToolModel tool, {ServerModel? server}) =>
      ToolWithApiKeyDto(
        id: tool.id,
        alias: tool.alias,
        host: tool.host,
        port: tool.port,
        apiKey: tool.apiKey,
        status: tool.status,
        serverId: tool.serverId,
        materializedArtifactDigest: tool.materializedArtifactDigest,
        contentState: tool.contentState,
        server: server != null
            ? ToolServerDto.fromModel(server)
            : tool.serverIdentity == null
            ? null
            : ToolServerDto.fromIdentity(tool.serverIdentity!),
      );
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ToolLifecycleEventDto {
  String type;
  String reason;
  ToolDto tool;
  DateTime occurredAt;

  ToolLifecycleEventDto({
    required this.type,
    required this.reason,
    required this.tool,
    required this.occurredAt,
  });

  factory ToolLifecycleEventDto.fromJson(Map<String, dynamic> json) =>
      _$ToolLifecycleEventDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ToolLifecycleEventDtoToJson(this);

  factory ToolLifecycleEventDto.fromModel(ToolLifecycleEventModel model) =>
      ToolLifecycleEventDto(
        type: model.type,
        reason: model.reason,
        tool: ToolDto.fromModel(model.tool),
        occurredAt: model.occurredAt,
      );
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class StartInfoDto {
  String? hostType;

  StartInfoDto({this.hostType});

  factory StartInfoDto.fromJson(Map<String, dynamic> json) =>
      _$StartInfoDtoFromJson(json);

  Map<String, dynamic> toJson() => _$StartInfoDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ListToolInfoDto {
  String? all;

  ListToolInfoDto({this.all});

  factory ListToolInfoDto.fromJson(Map<String, dynamic> json) =>
      _$ListToolInfoDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ListToolInfoDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ToolIdDto {
  String id;

  ToolIdDto({required this.id});

  factory ToolIdDto.fromJson(Map<String, dynamic> json) =>
      _$ToolIdDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ToolIdDtoToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class PathDto {
  String path;

  PathDto({required this.path});

  factory PathDto.fromJson(Map<String, dynamic> json) =>
      _$PathDtoFromJson(json);

  Map<String, dynamic> toJson() => _$PathDtoToJson(this);
}
