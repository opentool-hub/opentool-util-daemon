import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:opentool_dart/opentool_dart.dart';
import 'package:path/path.dart' as p;
import '../utils/directory_util.dart';
import '../utils/json_file_util.dart';
import '../utils/zip_util.dart';
import '../constants.dart';
import '../storage/cache_storage.dart';
import '../storage/hive_storage.dart';
import '../storage/dao.dart';
import '../utils/command_util.dart';
import '../utils/logger.dart';
import '../utils/network_util.dart';
import 'config.dart';
import 'exception.dart';
import 'model.dart';

class ToolService {
  late CacheToolStorage _cacheToolStorage;
  Map<String, OpenToolClient> _clients = {};
  late final OpenToolClient Function(ToolDao toolDao) _clientFactory;
  late final Future<int> Function(String host, int startPort) _portAllocator;

  ToolService(
    HiveToolStorage hive, {
    OpenToolClient Function(ToolDao toolDao)? clientFactory,
    Future<int> Function(String host, int startPort)? portAllocator,
  }) {
    _cacheToolStorage = CacheToolStorage(hive);
    _clientFactory = clientFactory ?? _buildClient;
    _portAllocator = portAllocator ?? findAvailablePort;
  }

  Future<void> refreshStatusesOnStartup() async {
    logger.log(LogModule.tool, "refreshStatusesOnStartup.start", detail: "initializing tool status cache");
    final List<ToolDao> toolDaos = await _cacheToolStorage.list();
    for (final toolDao in toolDaos) {
      if (toolDao.status != ToolStatusType.RUNNING) continue;
      try {
        await _checkThenRun(toolDao.id, (client) async {
          await client.version();
        });
      } catch (error, stackTrace) {
        _clients.remove(toolDao.id);
        logger.log(
          LogModule.tool,
          "refreshStatusesOnStartup.markNotRunning",
          detail: "toolId: ${toolDao.id}, error: $error\n$stackTrace",
          level: Level.WARNING,
        );
      }
    }
    logger.log(LogModule.tool, "refreshStatusesOnStartup.done", detail: "checked: ${toolDaos.length}");
  }

  Future<List<ToolModel>> list({bool all = false}) async {
    logger.log(LogModule.tool, "list.input", detail: "all: $all");
    List<ToolDao> daoList = await _cacheToolStorage.list();
    if (!all) {
      daoList = daoList
          .where((dao) => dao.status == ToolStatusType.RUNNING)
          .toList();
    }
    logger.log(
      LogModule.tool,
      "list.result",
      detail: "count: ${daoList.length}",
    );
    return daoList.map((dao) => ToolModel.fromDao(dao)).toList();
  }

  Future<ToolModel> get(String toolId) async {
    logger.log(LogModule.tool, "get.input", detail: "toolId: $toolId");
    ToolDao? toolDao = await _cacheToolStorage.get(toolId);
    if (toolDao == null) throw ToolNotFoundException(toolId);
    logger.log(LogModule.tool, "get.result", detail: "toolId: $toolId");
    return ToolModel.fromDao(toolDao);
  }

  Future<ToolModel> runServer(
    ServerModel server,
    String hostType, {
    void Function(String script, String output)? onStdout,
    void Function(String script, String error)? onStderr,
    bool printStd = true,
  }) async {
    logger.log(
      LogModule.tool,
      "runServer.input",
      detail: "serverId: ${server.id}, hostType: $hostType",
    );

    /// 1. get the server internal file, .opentool/servers/{name}-{internalId}.ots, then unzip to temp folder
    String name = server.name;
    String internalId = server.internalId;
    String otsFilePath =
        "$OPENTOOL_PATH${Platform.pathSeparator}$SERVER_FOLDER${Platform.pathSeparator}$name-$internalId.ots";
    String tempFolder = await ZipUtil.unzipToTemp(otsFilePath);

    /// 2. copy temp folder to .opentool/tools/{toolId}
    String toolId = uniqueId();
    String toolFolder =
        "$OPENTOOL_PATH${Platform.pathSeparator}$TOOL_FOLDER${Platform.pathSeparator}$toolId";
    await DirectoryUtil.copyDirectory(
      Directory(tempFolder),
      Directory(toolFolder),
    );

    /// 2. run tool
    String opentoolFileJsonPath =
        "$toolFolder${Platform.pathSeparator}$OPENTOOL_FILE_JSON_NAME";
    Map<String, dynamic> opentoolFileJson = await JsonFileUtil.readFromFile(
      opentoolFileJsonPath,
    );
    OpentoolfileConfig rawConfig = OpentoolfileConfig.fromJson(
      opentoolFileJson,
    );
    OpentoolfileConfig config = OpentoolfileConfigUtil.resolve(rawConfig);
    String workdir = _resolveWorkdir(toolFolder, config.run.workdir);
    String entrypoint = _resolveEntrypoint(workdir, config.run.entrypoint);
    List<String> cmds = List<String>.from(config.run.cmds);

    String tag = server.tag;
    cmds.add("--$CLI_ARGUMENT_TAG $tag");

    String host = hostType;
    cmds.add("--$CLI_ARGUMENT_HOST $host");

    final List<ToolDao> existingTools = await _cacheToolStorage.list();
    int preferredPort = TOOL_DEFAULT_PORT;
    if (existingTools.isNotEmpty) {
      existingTools.sort((a, b) => a.port.compareTo(b.port));
      preferredPort = existingTools.last.port + 1;
    }
    final int port = await _portAllocator(host, preferredPort);
    cmds.add("--$CLI_ARGUMENT_PORT $port");

    String apiKey = uniqueId(shorter: false);
    cmds.add("--$CLI_ARGUMENT_APIKEYS $apiKey");

    unawaited(
      _ensureExecutable(entrypoint, workdir).then((_) {
        return CommandUtil.runStream(
          workdir,
          entrypoint,
          cmds,
          onStdout: onStdout,
          onStderr: onStderr,
          printStd: printStd,
        );
      }),
    );

    /// 3. add to storage
    ToolDao toolDao = ToolDao(
      id: toolId,
      alias: toolId,
      tag: tag,
      host: host,
      port: port,
      apiKey: apiKey,
      status: ToolStatusType.RUNNING,
    );
    await _cacheToolStorage.add(toolDao);
    _registerClient(toolDao);
    logger.log(
      LogModule.tool,
      "runServer.result",
      detail: "toolId: $toolId, port: $port",
    );
    return ToolModel.fromDao(toolDao);
  }

  Future<void> startTool(
    ToolModel tool, {
    void Function(String script, String output)? onStdout,
    void Function(String script, String error)? onStderr,
    bool printStd = true,
  }) async {
    logger.log(LogModule.tool, "startTool.input", detail: "toolId: ${tool.id}");

    /// 1. run tool
    String toolFolder =
        "$OPENTOOL_PATH${Platform.pathSeparator}$TOOL_FOLDER${Platform.pathSeparator}${tool.id}";
    String opentoolFileJsonPath =
        "$toolFolder${Platform.pathSeparator}$OPENTOOL_FILE_JSON_NAME";
    Map<String, dynamic> opentoolFileJson = await JsonFileUtil.readFromFile(
      opentoolFileJsonPath,
    );
    OpentoolfileConfig rawConfig = OpentoolfileConfig.fromJson(
      opentoolFileJson,
    );
    OpentoolfileConfig config = OpentoolfileConfigUtil.resolve(rawConfig);
    String workdir = _resolveWorkdir(toolFolder, config.run.workdir);
    String entrypoint = _resolveEntrypoint(workdir, config.run.entrypoint);
    List<String> cmds = List<String>.from(config.run.cmds);

    String tag = tool.tag;
    cmds.add("--$CLI_ARGUMENT_TAG $tag");

    String host = tool.host;
    cmds.add("--$CLI_ARGUMENT_HOST $host");

    final int desiredPort = tool.port;
    final int port = await _portAllocator(host, desiredPort);
    cmds.add("--$CLI_ARGUMENT_PORT $port");

    String apiKey = tool.apiKey;
    cmds.add("--$CLI_ARGUMENT_APIKEYS $apiKey");

    unawaited(
      _ensureExecutable(entrypoint, workdir).then((_) {
        return CommandUtil.runStream(
          workdir,
          entrypoint,
          cmds,
          onStdout: onStdout,
          onStderr: onStderr,
          printStd: printStd,
        );
      }),
    );

    /// 2. update to storage
    ToolDao toolDao = ToolDao(
      id: tool.id,
      alias: tool.alias,
      tag: tag,
      host: host,
      port: port,
      apiKey: apiKey,
      status: ToolStatusType.RUNNING,
    );
    await _cacheToolStorage.update(toolDao);
    _registerClient(toolDao);
    logger.log(
      LogModule.tool,
      "startTool.result",
      detail: "toolId: ${tool.id}, port: $port",
    );
  }

  Future<void> check(String toolId) async {
    await _checkThenRun(toolId, (client) async {
      Version version = await client.version();
      logger.log(
        LogModule.tool,
        "check.version",
        detail: "toolId: $toolId version: ${version.version}",
      );
    });
  }

  Future<void> stop(String toolId) async {
    logger.log(LogModule.tool, "stop.input", detail: "toolId: $toolId");
    await _checkThenRun(toolId, (client) async {
      await client.stop();
    });
    final toolDao = await _cacheToolStorage.get(toolId);
    if (toolDao != null) {
      toolDao.status = ToolStatusType.NOT_RUNNING;
      await _cacheToolStorage.update(toolDao);
    }
    _clients.remove(toolId);
    logger.log(LogModule.tool, "stop.result", detail: "toolId: $toolId");
  }

  Future<void> delete(String toolId) async {
    logger.log(LogModule.tool, "delete.input", detail: "toolId: $toolId");
    OpenToolClient? client = _clients.remove(toolId);
    if (client != null) {
      try {
        await client.stop();
      } catch (error) {
        logger.log(
          LogModule.tool,
          "delete.stop.error",
          detail: "toolId: $toolId, error: $error",
          level: Level.WARNING,
        );
      }
    }

    ToolDao? toolDao = await _cacheToolStorage.get(toolId);
    if (toolDao != null) {
      await _cacheToolStorage.remove(toolId);
    }

    final String toolFolder = p.join(OPENTOOL_PATH, TOOL_FOLDER, toolId);
    await DirectoryUtil.deleteDirectory(toolFolder);
    logger.log(LogModule.tool, "delete.result", detail: "toolId: $toolId");
  }

  Future<ToolReturn> call(String toolId, FunctionCall functionCall) async {
    logger.log(
      LogModule.tool,
      "call.input",
      detail: "toolId: $toolId, function: ${functionCall.name}",
    );
    ToolReturn? toolReturn = await _checkThenRun<ToolReturn?>(toolId, (client) async {
      ToolReturn? toolReturn = await client.call(functionCall);
      return toolReturn;
    });
    logger.log(LogModule.tool, "call.result", detail: "toolId: $toolId");
    return toolReturn ??
        ToolReturn(id: functionCall.id, result: {"result": null});
  }

  Future<void> streamCall(
    String toolId,
    FunctionCall functionCall,
    void Function(String event, ToolReturn toolReturn) onToolReturn,
  ) async {
    logger.log(
      LogModule.tool,
      "streamCall.input",
      detail: "toolId: $toolId, function: ${functionCall.name}",
    );
    await _checkThenRun(toolId, (client) async {
      await client.streamCall(functionCall, onToolReturn);
    });
  }

  Future<OpenTool?> load(String toolId) async {
    logger.log(LogModule.tool, "load.input", detail: "toolId: $toolId");
    OpenTool? tool = await _checkThenRun(toolId, (client) async {
      OpenTool? tool = await client.load();
      return tool;
    });
    logger.log(
      LogModule.tool,
      "load.result",
      detail: "toolId: $toolId, loaded: ${tool != null}",
    );
    return tool;
  }

  Future<void> setAlias(String toolId, String newAlias) async {
    logger.log(
      LogModule.tool,
      "setAlias.input",
      detail: "toolId: $toolId, alias: $newAlias",
    );
    await _checkThenRun(toolId, (client) async {
      ToolDao? toolDao = await _cacheToolStorage.get(toolId);
      if (toolDao == null) throw ToolNotFoundException(toolId);
      toolDao.alias = newAlias;
      await _cacheToolStorage.update(toolDao);
    });
    logger.log(
      LogModule.tool,
      "setAlias.result",
      detail: "toolId: $toolId, alias: $newAlias",
    );
  }

  Future<T> _checkThenRun<T>(
    String toolId,
    Future<T> Function(OpenToolClient client) onRun,
  ) async {
    logger.log(LogModule.tool, "check.input", detail: "toolId: $toolId");
    ToolDao? toolDao = await _cacheToolStorage.get(toolId);
    if (toolDao == null) {
      logger.log(LogModule.tool, "check.missing", detail: "toolId: $toolId");
      throw ToolNotFoundException(toolId);
    }
    OpenToolClient client = _clients[toolId] ?? _registerClient(toolDao);
    try {
      return await onRun(client);
    } catch (e) {
      toolDao.status = ToolStatusType.NOT_RUNNING;
      await _cacheToolStorage.update(toolDao);
      logger.log(
        LogModule.tool,
        "check.error",
        detail: "toolId: $toolId, error: $e",
      );
      rethrow;
    }
  }

  OpenToolClient _registerClient(ToolDao toolDao) {
    final client = _clientFactory(toolDao);
    _clients[toolDao.id] = client;
    return client;
  }

  OpenToolClient _buildClient(ToolDao toolDao) {
    final String resolvedHost =
        toolDao.host.isEmpty || toolDao.host == HostType.ANY
        ? HostType.LOCALHOST
        : toolDao.host;
    return OpenToolClient(
      toolHost: resolvedHost,
      toolPort: toolDao.port,
      toolApiKey: toolDao.apiKey,
    );
  }

  String _resolveWorkdir(String baseFolder, String configuredWorkdir) {
    if (configuredWorkdir.isEmpty || configuredWorkdir == '.') {
      return baseFolder;
    }
    final String candidate = p.normalize(p.join(baseFolder, configuredWorkdir));
    if (Directory(candidate).existsSync()) {
      return candidate;
    }
    return baseFolder;
  }

  String _resolveEntrypoint(String workdir, String entrypoint) {
    if (entrypoint.isEmpty) return entrypoint;
    if (entrypoint.startsWith('/') ||
        entrypoint.startsWith('./') ||
        entrypoint.startsWith('../')) {
      return entrypoint;
    }
    final String candidatePath = p.join(workdir, entrypoint);
    if (File(candidatePath).existsSync()) {
      return './$entrypoint';
    }
    return entrypoint;
  }

  Future<void> _ensureExecutable(String entrypoint, String workdir) async {
    if (entrypoint.isEmpty) return;
    if (!entrypoint.startsWith('./')) return;
    final String executableName = entrypoint.substring(2);
    final String absolutePath = p.join(workdir, executableName);
    final File executable = File(absolutePath);
    if (!await executable.exists()) return;
    final FileStat stat = await executable.stat();
    final bool isExecutable = stat.mode & 0x49 != 0;
    if (!isExecutable) {
      await Process.run('chmod', ['+x', absolutePath]);
    }
  }
}
