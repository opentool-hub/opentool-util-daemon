import '../storage/dao.dart';

class ServerIdentity {
  final String registry;
  final String namespace;
  final String name;
  final String version;

  ServerIdentity({
    required this.registry,
    String? namespace,
    @Deprecated('Use namespace') String? repo,
    required this.name,
    String? version,
    @Deprecated('Use version') String? tag,
  }) : namespace =
           namespace ?? repo ?? (throw ArgumentError.notNull('namespace')),
       version = version ?? tag ?? (throw ArgumentError.notNull('version'));

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

  @Deprecated('Use namespace')
  String get repo => namespace;

  @Deprecated('Use version')
  String get tag => version;
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

  VersionModel({required this.name, required this.version});
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
  DateTime? installedAt;

  ServerModel({
    required this.id,
    required this.alias,
    required this.registry,
    String? namespace,
    @Deprecated('Use namespace') String? repo,
    required this.name,
    String? version,
    @Deprecated('Use version') String? tag,
    required this.internalId,
    this.artifactId,
    this.versionDigest,
    this.artifactDigest,
    this.artifactMediaType,
    this.artifactSize,
    this.platform,
    this.installedAt,
  }) : namespace =
           namespace ?? repo ?? (throw ArgumentError.notNull('namespace')),
       version = version ?? tag ?? (throw ArgumentError.notNull('version'));

  @Deprecated('Use namespace')
  String get repo => namespace;

  @Deprecated('Use namespace')
  set repo(String value) => namespace = value;

  @Deprecated('Use version')
  String get tag => version;

  @Deprecated('Use version')
  set tag(String value) => version = value;

  factory ServerModel.fromDao(ServerDao dao) {
    return ServerModel(
      id: dao.id,
      alias: dao.alias,
      registry: dao.registry,
      namespace: dao.namespace,
      name: dao.name,
      version: dao.version,
      internalId: dao.internalId,
      artifactId: dao.artifactId,
      versionDigest: dao.versionDigest,
      artifactDigest: dao.artifactDigest,
      artifactMediaType: dao.artifactMediaType,
      artifactSize: dao.artifactSize,
      platform:
          dao.platformOs == null ||
              dao.platformArch == null ||
              dao.platformAbi == null
          ? null
          : ServerPlatform(
              os: dao.platformOs!,
              arch: dao.platformArch!,
              abi: dao.platformAbi!,
            ),
      installedAt: dao.installedAt,
    );
  }

  ServerDao toDao() {
    return ServerDao(
      id: id,
      alias: alias,
      registry: registry,
      namespace: namespace,
      name: name,
      version: version,
      internalId: internalId,
      artifactId: artifactId,
      versionDigest: versionDigest,
      artifactDigest: artifactDigest,
      artifactMediaType: artifactMediaType,
      artifactSize: artifactSize,
      platformOs: platform?.os,
      platformArch: platform?.arch,
      platformAbi: platform?.abi,
      installedAt: installedAt,
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
  String? serverRepo;
  String? serverName;
  String? serverTag;

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
    this.serverRepo,
    this.serverName,
    this.serverTag,
  });

  ServerIdentity? get serverIdentity {
    final registry = serverRegistry;
    final repo = serverRepo;
    final name = serverName;
    final tag = serverTag;
    if (registry == null || repo == null || name == null || tag == null) {
      return null;
    }
    return ServerIdentity(
      registry: registry,
      namespace: repo,
      name: name,
      version: tag,
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
      serverRepo: dao.serverRepo,
      serverName: dao.serverName,
      serverTag: dao.serverTag,
      extraCmds: dao.extraCmds == null
          ? null
          : List<String>.from(dao.extraCmds!),
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
      serverRepo: serverRepo,
      serverName: serverName,
      serverTag: serverTag,
      extraCmds: extraCmds == null ? null : List<String>.from(extraCmds!),
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
