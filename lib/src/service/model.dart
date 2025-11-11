import '../storage/dao.dart';

class ToolStatusType {
  static const String RUNNING = 'running';
  static const String NOT_RUNNING = 'notRunning';
}

class VersionModel {
  String name;
  String version;

  VersionModel({
    required this.name,
    required this.version,
  });
}

class LoginInfoModel {
  final String registry;
  final String username;
  final String password;

  LoginInfoModel({
    required this.registry,
    required this.username,
    required this.password,
  });
}

class UserInfo {
  String? registry;
  String? username;

  UserInfo({
    this.registry,
    this.username,
  });
}

class ServerModel {
  String id;
  String alias;
  String registry ;
  String repo;
  String name;
  String tag;
  String internalId;

  ServerModel({
    required this.id,
    required this.alias,
    required this.registry,
    required this.repo,
    required this.name,
    required this.tag,
    required this.internalId,
  });

  factory ServerModel.fromDao(ServerDao dao) {
    return ServerModel(
      id: dao.id,
      alias: dao.alias,
      registry: dao.registry,
      repo: dao.repo,
      name: dao.name,
      tag: dao.tag,
      internalId: dao.internalId
    );
  }

  ServerDao toDao() {
    return ServerDao(
        id: id,
        alias: alias,
        registry: registry,
        repo: repo,
        name: name,
        tag: tag,
        internalId: internalId
    );
  }
}

class ToolModel {
  String id;
  String alias;
  String tag;
  String host ;
  int port;
  String apiKey;
  String status;

  ToolModel({
    required this.id,
    required this.alias,
    required this.tag,
    required this.host,
    required this.port,
    required this.apiKey,
    required this.status,
  });

  factory ToolModel.fromDao(ToolDao dao) {
    return ToolModel(
      id: dao.id,
      alias: dao.alias,
      tag: dao.tag,
      host: dao.host,
      port: dao.port,
      apiKey: dao.apiKey,
      status: dao.status,
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
    );
  }
}