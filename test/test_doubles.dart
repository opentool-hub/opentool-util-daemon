import 'dart:async';
import 'dart:io';
import 'package:opentool_daemon/src/service/artifact_registry_service.dart';
import 'package:opentool_daemon/src/service/manage_service.dart';
import 'package:opentool_daemon/src/service/model.dart';
import 'package:opentool_daemon/src/service/server_service.dart';
import 'package:opentool_daemon/src/service/tool_service.dart';
import 'package:opentool_daemon/src/storage/dao.dart';
import 'package:opentool_daemon/src/storage/artifact_storage.dart';
import 'package:opentool_daemon/src/storage/storage.dart';
import 'package:opentool_dart/opentool_client.dart';

class FakeServerService implements ServerService {
  final Map<String, ServerModel> _servers;
  String? lastDeletedId;

  FakeServerService({Iterable<ServerModel>? initialServers})
    : _servers = {
        for (final server in initialServers ?? <ServerModel>[])
          server.id: server,
      };

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
  Future<ServerModel?> findHubSource({
    required String registry,
    required String namespace,
    required String name,
    required String version,
  }) async {
    for (final server in _servers.values) {
      if (server.registry == registry &&
          server.namespace == namespace &&
          server.name == name &&
          server.version == version) {
        return server;
      }
    }
    return null;
  }

  @override
  Future<ServerModel> registerHubArtifact(
    String sourcePath,
    HubArtifactMetadata metadata, {
    required void Function() onImporting,
  }) async => throw UnimplementedError();

  @override
  Future<void> reconcileInstallations() async {}

  @override
  Future<void> setAlias(String serverId, String newName) async {
    final server = await get(serverId);
    server.alias = newName;
  }
}

class FakeToolService implements ToolService {
  final Map<String, ToolModel> _tools;
  final Map<String, ToolReturn> toolReturns;
  final Map<String, OpenTool?> toolDefinitions;
  final StreamController<ToolLifecycleEventModel> _events =
      StreamController<ToolLifecycleEventModel>.broadcast();
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
  Stream<ToolLifecycleEventModel> get events => _events.stream;

  void emitEvent(ToolLifecycleEventModel event) {
    _events.add(event);
  }

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
  Future<int> repairServerAssociations(List<ServerModel> servers) async => 0;

  @override
  Future<ToolModel> runServer(
    ServerModel server,
    String hostType, {
    List<String>? extraCmds,
    void Function(String script, String output)? onStdout,
    void Function(String script, String error)? onStderr,
    bool printStd = true,
  }) async {
    final tool = ToolModel(
      id: 'tool-${_tools.length + 1}',
      alias: 'alias-${_tools.length + 1}',
      tag: server.version,
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
  ) async {
    onToolReturn(
      EventType.START,
      ToolReturn(id: functionCall.id, result: {'start': functionCall.name}),
    );

    final returnValue =
        toolReturns[toolId] ??
        ToolReturn(id: functionCall.id, result: {'result': null});
    onToolReturn(EventType.DATA, returnValue);
    onToolReturn(
      EventType.DONE,
      ToolReturn(
        id: functionCall.id,
        result: {EventType.DONE: functionCall.name},
      ),
    );
  }

  @override
  Future<void> refreshStatusesOnStartup({bool autoRestore = false}) async {}

  @override
  Future<OpenTool?> load(String toolId) async => toolDefinitions[toolId];

  @override
  Future<void> setAlias(String toolId, String newAlias) async {
    final tool = await get(toolId);
    tool.alias = newAlias;
  }
}

class NoopManageService extends ManageService {
  NoopManageService() : super('test');

  @override
  Future<VersionModel> getVersion() async =>
      VersionModel(name: 'noop', version: 'test');
}

class MemoryStorage<T> implements Storage<T> {
  final String Function(T value) _keyOf;
  final Map<String, T> _store = {};

  MemoryStorage(this._keyOf);

  void seed(Iterable<T> values) {
    for (final value in values) {
      _store[_keyOf(value)] = value;
    }
  }

  @override
  Future<void> add(T value) async {
    _store[_keyOf(value)] = value;
  }

  @override
  Future<T?> get(String id) async => _store[id];

  @override
  Future<void> update(T value) async {
    _store[_keyOf(value)] = value;
  }

  @override
  Future<T?> remove(String id) async => _store.remove(id);

  @override
  Future<List<T>> list() async => _store.values.toList();
}

class MemoryServerStorage extends MemoryStorage<ServerDao> {
  MemoryServerStorage() : super((value) => value.id);
}

class MemoryToolStorage extends MemoryStorage<ToolDao> {
  MemoryToolStorage() : super((value) => value.id);
}

class TestRegistryHarness {
  final Directory root;
  final MemoryStorage<ArtifactDao> artifacts;
  final MemoryStorage<ServerDao> servers;
  final MemoryStorage<ToolDao> tools;
  final MemoryStorage<ArtifactOperationDao> operations;
  final ArtifactRegistryService registry;
  final ServerService serverService;

  TestRegistryHarness._({
    required this.root,
    required this.artifacts,
    required this.servers,
    required this.tools,
    required this.operations,
    required this.registry,
    required this.serverService,
  });

  static Future<TestRegistryHarness> create({
    Directory? root,
    MemoryStorage<ServerDao>? serverStorage,
  }) async {
    final dataRoot =
        root ?? await Directory.systemTemp.createTemp('registry_harness_');
    final artifacts = MemoryStorage<ArtifactDao>((value) => value.digest);
    final servers =
        serverStorage ?? MemoryStorage<ServerDao>((value) => value.id);
    final tools = MemoryStorage<ToolDao>((value) => value.id);
    final operations = MemoryStorage<ArtifactOperationDao>((value) => value.id);
    final registry = ArtifactRegistryService(
      content: ArtifactStorage(dataRoot.path),
      artifacts: artifacts,
      servers: servers,
      operations: operations,
      tools: tools,
    );
    return TestRegistryHarness._(
      root: dataRoot,
      artifacts: artifacts,
      servers: servers,
      tools: tools,
      operations: operations,
      registry: registry,
      serverService: ServerService(servers, artifactRegistry: registry),
    );
  }

  Future<void> dispose() async {
    if (await root.exists()) await root.delete(recursive: true);
  }
}

class InMemoryApiKeyStorage implements Storage<ApiKeyDao> {
  final Map<String, ApiKeyDao> _store = {};

  @override
  Future<void> add(ApiKeyDao value) async {
    _store[value.id] = value;
  }

  @override
  Future<ApiKeyDao?> get(String id) async => _store[id];

  @override
  Future<void> update(ApiKeyDao value) async {
    _store[value.id] = value;
  }

  @override
  Future<ApiKeyDao?> remove(String id) async => _store.remove(id);

  @override
  Future<List<ApiKeyDao>> list() async => _store.values.toList();
}
