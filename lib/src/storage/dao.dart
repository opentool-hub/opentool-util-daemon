import 'package:hive/hive.dart';

part 'dao.g.dart';

@HiveType(typeId: 0)
class InternalServerDao extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String file;

  InternalServerDao({required this.id, required this.file});
}

@HiveType(typeId: 1)
class ServerDao extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String alias;

  @HiveField(2)
  String registry;

  @HiveField(3)
  String namespace;

  @HiveField(4)
  String name;

  @HiveField(5)
  String version;

  @HiveField(6)
  String internalId;

  @HiveField(7)
  String? artifactId;

  @HiveField(8)
  String? versionDigest;

  @HiveField(9)
  String? artifactDigest;

  @HiveField(10)
  int? artifactSize;

  @HiveField(11)
  String? platformOs;

  @HiveField(12)
  String? platformArch;

  @HiveField(13)
  String? platformAbi;

  @HiveField(14)
  DateTime? installedAt;

  @HiveField(15)
  String? artifactMediaType;

  ServerDao({
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
    this.artifactSize,
    this.platformOs,
    this.platformArch,
    this.platformAbi,
    this.installedAt,
    this.artifactMediaType,
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
}

@HiveType(typeId: 2)
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
  String? serverRegistry;

  @HiveField(10)
  String? serverRepo;

  @HiveField(11)
  String? serverName;

  @HiveField(12)
  String? serverTag;

  ToolDao({
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
}

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
