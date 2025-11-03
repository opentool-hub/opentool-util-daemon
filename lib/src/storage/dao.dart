import 'package:hive/hive.dart';

part 'dao.g.dart';

@HiveType(typeId: 0)
class InternalServerDao extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String file;

  InternalServerDao({
    required this.id,
    required this.file,
  });
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
  String repo;

  @HiveField(4)
  String name;

  @HiveField(5)
  String tag;

  @HiveField(6)
  String internalId;

  ServerDao({
    required this.id,
    required this.alias,
    required this.registry,
    required this.repo,
    required this.name,
    required this.tag,
    required this.internalId,
  });
}

@HiveType(typeId: 2)
class ToolDao extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String alias;

  @HiveField(2)
  String host;

  @HiveField(3)
  int port;

  @HiveField(4)
  String apiKey;

  @HiveField(5)
  String status;

  ToolDao({
    required this.id,
    required this.alias,
    required this.host,
    required this.port,
    required this.apiKey,
    required this.status
  });
}