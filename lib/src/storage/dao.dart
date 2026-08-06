import 'package:hive/hive.dart';

part 'dao.g.dart';

@HiveType(typeId: 3)
class ApiKeyDao extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String apiKey;

  @HiveField(3)
  DateTime createdAt;

  ApiKeyDao({
    required this.id,
    required this.name,
    required this.apiKey,
    required this.createdAt,
  });
}

/// Immutable, content-addressed OpenTool artifact.
@HiveType(typeId: 4)
class ArtifactDao extends HiveObject {
  @HiveField(0)
  String digest;
  @HiveField(1)
  int size;
  @HiveField(2)
  String mediaType;
  @HiveField(3)
  String platformOs;
  @HiveField(4)
  String platformArch;
  @HiveField(5)
  String platformAbi;
  @HiveField(6)
  String filePath;
  @HiveField(7)
  String manifestName;
  @HiveField(8)
  String manifestVersion;
  @HiveField(9)
  DateTime verifiedAt;
  @HiveField(10)
  DateTime createdAt;

  ArtifactDao({
    required this.digest,
    required this.size,
    required this.mediaType,
    required this.platformOs,
    required this.platformArch,
    required this.platformAbi,
    required this.filePath,
    required this.manifestName,
    required this.manifestVersion,
    required this.verifiedAt,
    required this.createdAt,
  });
}

/// Logical reference to an immutable [ArtifactDao].
@HiveType(typeId: 5)
class ServerDao extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  String alias;
  @HiveField(2)
  String namespace;
  @HiveField(3)
  String name;
  @HiveField(4)
  String version;
  @HiveField(5)
  String artifactDigest;
  @HiveField(6)
  String sourceKind;
  @HiveField(7)
  String sourceKey;
  @HiveField(8)
  String? registry;
  @HiveField(9)
  String? versionDigest;
  @HiveField(10)
  String? hubArtifactId;
  @HiveField(11)
  String? builtinBundleFamily;
  @HiveField(12)
  String? builtinBundleId;
  @HiveField(13)
  String? builtinKey;
  @HiveField(14)
  bool protected;
  @HiveField(15)
  String managedBy;
  @HiveField(16)
  String state;
  @HiveField(17)
  DateTime createdAt;

  ServerDao({
    required this.id,
    required this.alias,
    required this.namespace,
    required this.name,
    required this.version,
    required this.artifactDigest,
    required this.sourceKind,
    required this.sourceKey,
    this.registry,
    this.versionDigest,
    this.hubArtifactId,
    this.builtinBundleFamily,
    this.builtinBundleId,
    this.builtinKey,
    required this.protected,
    required this.managedBy,
    required this.state,
    required this.createdAt,
  });
}

@HiveType(typeId: 6)
class ToolDao extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  String alias;
  @HiveField(2)
  String tag;
  @HiveField(3)
  String host;
  @HiveField(4)
  int port;
  @HiveField(5)
  String apiKey;
  @HiveField(6)
  String status;
  @HiveField(7)
  List<String>? extraCmds;
  @HiveField(8)
  String? serverId;
  @HiveField(9)
  String? materializedArtifactDigest;
  @HiveField(10)
  String? serverRegistry;
  @HiveField(11)
  String? serverNamespace;
  @HiveField(12)
  String? serverName;
  @HiveField(13)
  String? serverVersion;

  ToolDao({
    required this.id,
    required this.alias,
    required this.tag,
    required this.host,
    required this.port,
    required this.apiKey,
    required this.status,
    this.extraCmds,
    this.serverId,
    this.materializedArtifactDigest,
    this.serverRegistry,
    this.serverNamespace,
    this.serverName,
    this.serverVersion,
  });
}

@HiveType(typeId: 7)
class ArtifactOperationDao extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  String type;
  @HiveField(2)
  String stage;
  @HiveField(3)
  String? tempPath;
  @HiveField(4)
  String? digest;
  @HiveField(5)
  String? serverId;
  @HiveField(6)
  String? sourceKind;
  @HiveField(7)
  String? sourceKey;
  @HiveField(8)
  String? payloadJson;
  @HiveField(9)
  DateTime createdAt;
  @HiveField(10)
  DateTime updatedAt;

  ArtifactOperationDao({
    required this.id,
    required this.type,
    required this.stage,
    this.tempPath,
    this.digest,
    this.serverId,
    this.sourceKind,
    this.sourceKey,
    this.payloadJson,
    required this.createdAt,
    required this.updatedAt,
  });
}

@HiveType(typeId: 8)
class SchemaMetaDao extends HiveObject {
  @HiveField(0)
  int schemaVersion;
  @HiveField(1)
  DateTime initializedAt;

  SchemaMetaDao({required this.schemaVersion, required this.initializedAt});
}

@HiveType(typeId: 9)
class BuiltinBundleDao extends HiveObject {
  @HiveField(0)
  String bundleFamily;
  @HiveField(1)
  String activeBundleId;
  @HiveField(2)
  List<String> itemKeys;
  @HiveField(3)
  DateTime updatedAt;

  BuiltinBundleDao({
    required this.bundleFamily,
    required this.activeBundleId,
    required this.itemKeys,
    required this.updatedAt,
  });
}
