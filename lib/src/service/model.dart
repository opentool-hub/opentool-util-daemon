import 'dart:io';

import '../storage/dao.dart';

class StatusType {
  static const String START_SUCCESS = 'startSuccess';
  static const String START_FAILED = 'startFailed';
  static const String RENAME_SUCCESS = 'renameSuccess';
  static const String RUNNING = 'running';
  static const String STOP_SUCCESS = 'stopSuccess';
  static const String NOT_RUNNING = 'notRunning';
  static const String PID_NOT_EXIST = 'pidNotExist';
  static const String SERVER_NOT_EXIST = 'serverNotExist';
  static const String REMOVE_SUCCESS = 'removeSuccess';
}

class OpenToolServerModel {
  String id;
  String name;
  String file;
  String host;
  int port;
  String prefix;
  List<String>? apiKeys;
  int? pid;

  OpenToolServerModel({
    required this.id,
    required this.name,
    required this.file,
    required this.host,
    required this.port,
    required this.prefix,
    this.apiKeys,
    this.pid,
  });

  factory OpenToolServerModel.fromDao(OpenToolServerDao dao) {
    return OpenToolServerModel(
      id: dao.id,
      name: dao.name,
      file: dao.file,
      host: dao.host,
      port: dao.port,
      prefix: dao.prefix,
      apiKeys: dao.apiKeys,
      pid: dao.pid,
    );
  }

  OpenToolServerDao toDao() {
    return OpenToolServerDao(
      id: id,
      name: name,
      file: file,
      host: host == InternetAddress.anyIPv4.host? InternetAddress.loopbackIPv4.host : host,
      port: port,
      prefix: prefix,
      apiKeys: apiKeys,
      pid: pid,
    );
  }
}