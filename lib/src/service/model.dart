import '../storage/dao.dart';

class ServerIdentity {
  final String registry;
  final String namespace;
  final String name;
  final String version;

  ServerIdentity({
    required this.registry,
    required this.namespace,
    required this.name,
    required this.version,
  });

  factory ServerIdentity.fromServer(ServerModel server) => ServerIdentity(
    registry: server.registry,
    namespace: server.namespace,
    name: server.name,
    version: server.version,
  );

  @override
  bool operator ==(Object other) =>
      other is ServerIdentity &&
      registry == other.registry &&
      namespace == other.namespace &&
      name == other.name &&
      version == other.version;

  @override
  int get hashCode => Object.hash(registry, namespace, name, version);

  @override
  String toString() => '$registry/$namespace/$name:$version';
}

class ServerPlatform {
  final String os;
  final String arch;
  final String abi;

  const ServerPlatform({
    required this.os,
    required this.arch,
    required this.abi,
  });
}

class HubArtifactMetadata {
  final String registry;
  final String namespace;
  final String name;
  final String version;
  final String versionDigest;
  final String artifactId;
  final String artifactDigest;
  final String artifactMediaType;
  final int artifactSize;
  final ServerPlatform platform;

  const HubArtifactMetadata({
    required this.registry,
    required this.namespace,
    required this.name,
    required this.version,
    required this.versionDigest,
    required this.artifactId,
    required this.artifactDigest,
    required this.artifactMediaType,
    required this.artifactSize,
    required this.platform,
  });
}

class ToolStatusType {
  static const String RUNNING = 'running';
  static const String STARTING = 'starting';
  static const String STOPPING = 'stopping';
  static const String NOT_RUNNING = 'notRunning';
}

class ToolLifecycleEventType {
  static const String STARTING = 'tool.starting';
  static const String READY = 'tool.ready';
  static const String DRAINING = 'tool.draining';
  static const String UNAVAILABLE = 'tool.unavailable';
  static const String REMOVED = 'tool.removed';
  static const String SNAPSHOT = 'tool.snapshot';
}

class ToolLifecycleEventReason {
  static const String CREATED = 'created';
  static const String STARTED = 'started';
  static const String ALIAS_UPDATED = 'alias_updated';
  static const String STOP_REQUESTED = 'stop_requested';
  static const String DELETE_REQUESTED = 'delete_requested';
  static const String HEALTHCHECK_FAILED = 'healthcheck_failed';
  static const String DELETED = 'deleted';
  static const String SNAPSHOT = 'snapshot';
}

class VersionModel {
  String name;
  String version;
  int apiVersion;
  List<String> capabilities;

  VersionModel({
    required this.name,
    required this.version,
    this.apiVersion = 2,
    this.capabilities = const [
      'artifactRegistryV2',
      'builtinReconcileV1',
      'pullSseV1',
      'startToolTerminalV1',
      'toolMaterializationV1',
      'toolEventsV1',
    ],
  });
}

class ServerModel {
  String id;
  String alias;
  String registry;
  String namespace;
  String name;
  String version;
  String internalId;
  String? artifactId;
  String? versionDigest;
  String? artifactDigest;
  String? artifactMediaType;
  int? artifactSize;
  ServerPlatform? platform;
  String sourceKind;
  String sourceKey;
  bool protected;
  String managedBy;
  String state;
  DateTime? createdAt;
  String? builtinBundleFamily;
  String? builtinBundleId;
  String? builtinKey;
  String? artifactFilePath;
  DateTime? artifactVerifiedAt;
  int artifactReferenceCount;
  bool canRun;
  bool canRemove;

  ServerModel({
    required this.id,
    required this.alias,
    required this.registry,
    required this.namespace,
    required this.name,
    required this.version,
    required this.internalId,
    this.artifactId,
    this.versionDigest,
    this.artifactDigest,
    this.artifactMediaType,
    this.artifactSize,
    this.platform,
    this.sourceKind = 'import',
    this.sourceKey = '',
    this.protected = false,
    this.managedBy = 'user',
    this.state = 'available',
    this.createdAt,
    this.builtinBundleFamily,
    this.builtinBundleId,
    this.builtinKey,
    this.artifactFilePath,
    this.artifactVerifiedAt,
    this.artifactReferenceCount = 1,
    this.canRun = true,
    this.canRemove = true,
  });

  factory ServerModel.fromDao(
    ServerDao dao, {
    ArtifactDao? artifact,
    int artifactReferenceCount = 1,
  }) {
    return ServerModel(
      id: dao.id,
      alias: dao.alias,
      registry: dao.registry ?? '',
      namespace: dao.namespace,
      name: dao.name,
      version: dao.version,
      internalId: dao.artifactDigest,
      artifactId: dao.hubArtifactId,
      versionDigest: dao.versionDigest,
      artifactDigest: dao.artifactDigest,
      artifactMediaType: artifact?.mediaType,
      artifactSize: artifact?.size,
      platform: artifact == null
          ? null
          : ServerPlatform(
              os: artifact.platformOs,
              arch: artifact.platformArch,
              abi: artifact.platformAbi,
            ),
      sourceKind: dao.sourceKind,
      sourceKey: dao.sourceKey,
      protected: dao.protected,
      managedBy: dao.managedBy,
      state: dao.state,
      createdAt: dao.createdAt,
      builtinBundleFamily: dao.builtinBundleFamily,
      builtinBundleId: dao.builtinBundleId,
      builtinKey: dao.builtinKey,
      artifactFilePath: artifact?.filePath,
      artifactVerifiedAt: artifact?.verifiedAt,
      artifactReferenceCount: artifactReferenceCount,
      canRun: dao.state == 'available' && artifact != null,
      canRemove: !dao.protected,
    );
  }

  ServerDao toDao() {
    return ServerDao(
      id: id,
      alias: alias,
      namespace: namespace,
      name: name,
      version: version,
      artifactDigest: artifactDigest ?? internalId,
      sourceKind: sourceKind,
      sourceKey: sourceKey,
      registry: registry.isEmpty ? null : registry,
      versionDigest: versionDigest,
      hubArtifactId: artifactId,
      protected: protected,
      managedBy: managedBy,
      state: state,
      createdAt: createdAt ?? DateTime.now().toUtc(),
      builtinBundleFamily: builtinBundleFamily,
      builtinBundleId: builtinBundleId,
      builtinKey: builtinKey,
    );
  }

  ServerIdentity get identity => ServerIdentity.fromServer(this);
}

class ToolModel {
  String id;
  String alias;
  String tag;
  String host;
  int port;
  String apiKey;
  String status;
  List<String>? extraCmds;
  String? serverId;
  String? serverRegistry;
  String? serverNamespace;
  String? serverName;
  String? serverVersion;
  String? materializedArtifactDigest;
  String? contentState;

  ToolModel({
    required this.id,
    required this.alias,
    required this.tag,
    required this.host,
    required this.port,
    required this.apiKey,
    required this.status,
    this.serverId,
    this.extraCmds,
    this.serverRegistry,
    this.serverNamespace,
    this.serverName,
    this.serverVersion,
    this.materializedArtifactDigest,
    this.contentState,
  });

  ServerIdentity? get serverIdentity {
    final registry = serverRegistry;
    final namespace = serverNamespace;
    final name = serverName;
    final version = serverVersion;
    if (registry == null ||
        namespace == null ||
        name == null ||
        version == null) {
      return null;
    }
    return ServerIdentity(
      registry: registry,
      namespace: namespace,
      name: name,
      version: version,
    );
  }

  factory ToolModel.fromDao(ToolDao dao) {
    return ToolModel(
      id: dao.id,
      alias: dao.alias,
      tag: dao.tag,
      host: dao.host,
      port: dao.port,
      apiKey: dao.apiKey,
      status: dao.status,
      serverId: dao.serverId,
      serverRegistry: dao.serverRegistry,
      serverNamespace: dao.serverNamespace,
      serverName: dao.serverName,
      serverVersion: dao.serverVersion,
      extraCmds: dao.extraCmds == null
          ? null
          : List<String>.from(dao.extraCmds!),
      materializedArtifactDigest: dao.materializedArtifactDigest,
    );
  }

  ToolDao toDao() {
    return ToolDao(
      id: id,
      alias: alias,
      tag: tag,
      host: host,
      port: port,
      apiKey: apiKey,
      status: status,
      serverId: serverId,
      serverRegistry: serverRegistry,
      serverNamespace: serverNamespace,
      serverName: serverName,
      serverVersion: serverVersion,
      extraCmds: extraCmds == null ? null : List<String>.from(extraCmds!),
      materializedArtifactDigest: materializedArtifactDigest,
    );
  }
}

class ToolLifecycleEventModel {
  final String type;
  final String reason;
  final ToolModel tool;
  final DateTime occurredAt;

  ToolLifecycleEventModel({
    required this.type,
    required this.reason,
    required this.tool,
    required this.occurredAt,
  });
}

class ApiKeyModel {
  String id;
  String name;
  String apiKey;
  DateTime createdAt;

  ApiKeyModel({
    required this.id,
    required this.name,
    required this.apiKey,
    required this.createdAt,
  });

  factory ApiKeyModel.fromDao(ApiKeyDao dao) => ApiKeyModel(
    id: dao.id,
    name: dao.name,
    apiKey: dao.apiKey,
    createdAt: dao.createdAt,
  );

  ApiKeyDao toDao() =>
      ApiKeyDao(id: id, name: name, apiKey: apiKey, createdAt: createdAt);
}
