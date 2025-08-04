import 'package:hive/hive.dart';

part 'dao.g.dart';

@HiveType(typeId: 0)
class OpenToolServerDao extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String file;

  @HiveField(3)
  String host;

  @HiveField(4)
  int port;

  @HiveField(5)
  String prefix;

  @HiveField(6)
  List<String>? apiKeys;

  @HiveField(7)
  int? pid;

  OpenToolServerDao({
    required this.id,
    required this.name,
    required this.file,
    required this.host,
    required this.port,
    required this.prefix,
    this.apiKeys,
    this.pid,
  });
}