import '../storage/dao.dart';

class ToolStatusType {
  static const String RUNNING = 'running';
  static const String NOT_RUNNING = 'notRunning';
}

class ToolLifecycleEventType {
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

  UserInfo({this.registry, this.username});
}

class ServerModel {
  String id;
  String alias;
  String registry;
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
      internalId: dao.internalId,
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
      internalId: internalId,
    );
  }
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
      serverId: dao.serverId,
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
