import 'package:opentool_daemon/src/service/config.dart';
import 'package:opentool_daemon/src/service/manage_service.dart';
import 'package:opentool_daemon/src/service/model.dart';
import 'package:opentool_daemon/src/service/server_service.dart';
import 'package:opentool_daemon/src/service/tool_service.dart';
import 'package:opentool_daemon/src/storage/dao.dart';
import 'package:opentool_daemon/src/storage/hive_storage.dart';
import 'package:opentool_dart/opentool_dart.dart';

class FakeServerService implements ServerService {
  final Map<String, ServerModel> _servers;
  String? lastDeletedId;

  FakeServerService({Iterable<ServerModel>? initialServers})
    : _servers = {
        for (final server in initialServers ?? <ServerModel>[])
          server.id: server,
      };

  @override
  Future<void> afterPullToTemp(String otsFileTempPath) async =>
      throw UnimplementedError();

  @override
  Future<void> afterPush(String otsFilePath) async =>
      throw UnimplementedError();

  @override
  Future<void> buildServer(
    String path,
    String name,
    String? tag,
    void Function(String command, String output) onRun,
    void Function() onDone,
  ) async => throw UnimplementedError();

  @override
  Future<void> delete(String serverId) async {
    lastDeletedId = serverId;
    _servers.remove(serverId);
  }

  @override
  Future<void> export(String serverId, String exportFolder) async =>
      throw UnimplementedError();

  @override
  Future<ServerModel> get(String serverId) async {
    final server = _servers[serverId];
    if (server == null) throw StateError('Server not found: $serverId');
    return server;
  }

  @override
  Future<ServerModel> import(String otsFilePath) async =>
      throw UnimplementedError();

  @override
  Future<List<ServerModel>> list() async => _servers.values.toList();

  @override
  Future<String> beforePush(String serverId) async =>
      throw UnimplementedError();

  @override
  Future<ServerModel> tag(String serverId, String? tag) async {
    final server = await get(serverId);
    server.tag = tag ?? server.tag;
    return server;
  }

  @override
  Future<void> setAlias(String serverId, String newName) async {
    final server = await get(serverId);
    server.alias = newName;
  }

  @override
  Future<void> removeServersByNameAndTagForTest(
    String name,
    String tag, {
    String? excludeServerId,
  }) async {}
}

class FakeToolService implements ToolService {
  final Map<String, ToolModel> _tools;
  final Map<String, ToolReturn> toolReturns;
  final Map<String, OpenTool?> toolDefinitions;
  String? lastStoppedId;
  String? lastDeletedId;

  FakeToolService({
    Iterable<ToolModel>? initialTools,
    this.toolReturns = const {},
    this.toolDefinitions = const {},
  }) : _tools = {
         for (final tool in initialTools ?? <ToolModel>[]) tool.id: tool,
       };

  @override
  Future<void> delete(String toolId) async {
    lastDeletedId = toolId;
    _tools.remove(toolId);
  }

  @override
  Future<ToolModel> get(String toolId) async {
    final tool = _tools[toolId];
    if (tool == null) throw StateError('Tool not found: $toolId');
    return tool;
  }

  @override
  Future<List<ToolModel>> list({bool all = false}) async {
    final values = _tools.values;
    if (all) return values.toList();
    return values
        .where((tool) => tool.status == ToolStatusType.RUNNING)
        .toList();
  }

  @override
  Future<ToolModel> runServer(
    ServerModel server,
    String hostType, {
    void Function(String script, String output)? onStdout,
    void Function(String script, String error)? onStderr,
    bool printStd = true,
  }) async {
    final tool = ToolModel(
      id: 'tool-${_tools.length + 1}',
      alias: 'alias-${_tools.length + 1}',
      tag: server.tag,
      host: hostType,
      port: 9000 + _tools.length,
      apiKey: 'key-${_tools.length + 1}',
      status: ToolStatusType.RUNNING,
    );
    _tools[tool.id] = tool;
    return tool;
  }

  @override
  Future<void> startTool(
    ToolModel tool, {
    void Function(String script, String output)? onStdout,
    void Function(String script, String error)? onStderr,
    bool printStd = true,
  }) async {}

  @override
  Future<void> stop(String toolId) async {
    await get(toolId);
    lastStoppedId = toolId;
  }

  @override
  Future<void> check(String toolId) async {}

  @override
  Future<ToolReturn> call(String toolId, FunctionCall functionCall) async {
    return toolReturns[toolId] ??
        ToolReturn(id: functionCall.id, result: {'result': null});
  }

  @override
  Future<void> streamCall(
    String toolId,
    FunctionCall functionCall,
    void Function(String event, ToolReturn toolReturn) onToolReturn,
  ) async {}

  @override
  Future<OpenTool?> load(String toolId) async => toolDefinitions[toolId];

  @override
  Future<void> setAlias(String toolId, String newAlias) async {
    final tool = await get(toolId);
    tool.alias = newAlias;
  }
}

class NoopManageService extends ManageService {
  NoopManageService() : super('test') {
    currConfig = OpenToolConfig();
  }

  @override
  Future<void> init() async {}

  @override
  Future<VersionModel> getVersion() async =>
      VersionModel(name: 'noop', version: 'test');

  @override
  Future<void> login(LoginInfoModel loginInfoModel) async {}

  @override
  Future<String> pullToTemp({
    required String name,
    required String tag,
    required void Function(int sizeByByte, String digest) onStart,
    required void Function(int percent) onDownload,
    required void Function() onDone,
  }) async => '/tmp/$name-$tag';

  @override
  Future<void> push({
    required String otsFilePath,
    String? tag,
    required void Function(int sizeByByte, String digest) onStart,
    required void Function(int percent) onUpload,
    required void Function() onDone,
  }) async {}

  @override
  Future<UserInfo> getUserInfo() async => UserInfo();

  @override
  Future<UserInfo> logout() async => UserInfo();
}

class StubHiveServerStorage extends HiveServerStorage {
  final Map<String, ServerDao> _store = {};

  void seed(Iterable<ServerDao> servers) {
    for (final server in servers) {
      _store[server.id] = server;
    }
  }

  @override
  Future<void> add(ServerDao serverDao) async {
    _store[serverDao.id] = serverDao;
  }

  @override
  Future<ServerDao?> get(String id) async => _store[id];

  @override
  Future<void> update(ServerDao serverDao) async {
    _store[serverDao.id] = serverDao;
  }

  @override
  Future<ServerDao?> remove(String id) async => _store.remove(id);

  @override
  Future<List<ServerDao>> list() async => _store.values.toList();
}

class StubHiveInternalServerStorage extends HiveInternalServerStorage {
  final Map<String, InternalServerDao> _store = {};

  void seed(Iterable<InternalServerDao> servers) {
    for (final server in servers) {
      _store[server.id] = server;
    }
  }

  @override
  Future<void> add(InternalServerDao serverDao) async {
    _store[serverDao.id] = serverDao;
  }

  @override
  Future<InternalServerDao?> get(String id) async => _store[id];

  @override
  Future<void> update(InternalServerDao serverDao) async {
    _store[serverDao.id] = serverDao;
  }

  @override
  Future<InternalServerDao?> remove(String id) async => _store.remove(id);

  @override
  Future<List<InternalServerDao>> list() async => _store.values.toList();
}

class StubHiveToolStorage extends HiveToolStorage {
  final Map<String, ToolDao> _store = {};

  void seed(Iterable<ToolDao> tools) {
    for (final tool in tools) {
      _store[tool.id] = tool;
    }
  }

  @override
  Future<void> add(ToolDao toolDao) async {
    _store[toolDao.id] = toolDao;
  }

  @override
  Future<ToolDao?> get(String id) async => _store[id];

  @override
  Future<void> update(ToolDao toolDao) async {
    _store[toolDao.id] = toolDao;
  }

  @override
  Future<ToolDao?> remove(String id) async => _store.remove(id);

  @override
  Future<List<ToolDao>> list() async => _store.values.toList();
}
