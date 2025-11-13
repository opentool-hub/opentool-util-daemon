import 'dart:async';
import 'dart:io';
import 'package:opentool_dart/opentool_dart.dart';
import '../utils/directory_util.dart';
import '../utils/json_file_util.dart';
import '../utils/zip_util.dart';
import '../constants.dart';
import '../storage/cache_storage.dart';
import '../storage/hive_storage.dart';
import '../storage/dao.dart';
import '../utils/command_util.dart';
import '../utils/logger.dart';
import 'config.dart';
import 'exception.dart';
import 'model.dart';

class ToolService {
  late CacheToolStorage _cacheToolStorage;
  Map<String, OpenToolClient> _clients = {};

  ToolService(HiveToolStorage hive) {
    _cacheToolStorage = CacheToolStorage(hive);
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

  Future<void> runServer(
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
    OpentoolfileConfig config = OpentoolfileConfig.fromJson(opentoolFileJson);
    String workdir = config.run.workdir;
    String entrypoint = config.run.entrypoint;
    List<String> cmds = config.run.cmds;

    String tag = server.tag;
    cmds.add("--$CLI_ARGUMENT_TAG $tag");

    String host = hostType;
    cmds.add("--$CLI_ARGUMENT_HOST $host");

    int lastPort = (await _cacheToolStorage.list()).last.port;
    int port = lastPort + 1;
    cmds.add("--$CLI_ARGUMENT_PORT $port");

    String apiKey = uniqueId(shorter: false);
    cmds.add("--$CLI_ARGUMENT_APIKEYS $apiKey");

    unawaited(
      CommandUtil.runStream(
        workdir,
        entrypoint,
        cmds,
        onStdout: onStdout,
        onStderr: onStderr,
        printStd: printStd,
      ),
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
    logger.log(
      LogModule.tool,
      "runServer.result",
      detail: "toolId: $toolId, port: $port",
    );
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
    OpentoolfileConfig config = OpentoolfileConfig.fromJson(opentoolFileJson);
    String workdir = config.run.workdir;
    String entrypoint = config.run.entrypoint;
    List<String> cmds = config.run.cmds;

    String tag = tool.tag;
    cmds.add("--$CLI_ARGUMENT_TAG $tag");

    String host = tool.host;
    cmds.add("--$CLI_ARGUMENT_HOST $host");

    int lastPort = tool.port;
    int port = lastPort + 1;
    cmds.add("--$CLI_ARGUMENT_PORT $port");

    String apiKey = tool.apiKey;
    cmds.add("--$CLI_ARGUMENT_APIKEYS $apiKey");

    unawaited(
      CommandUtil.runStream(
        workdir,
        entrypoint,
        cmds,
        onStdout: onStdout,
        onStderr: onStderr,
        printStd: printStd,
      ),
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
    logger.log(
      LogModule.tool,
      "startTool.result",
      detail: "toolId: ${tool.id}, port: $port",
    );
  }

  Future<void> check(String toolId) async {
    await _checkThenRun(toolId, (client) async {
      Version version = await client.version();
    });
  }

  Future<void> stop(String toolId) async {
    logger.log(LogModule.tool, "stop.input", detail: "toolId: $toolId");
    await _checkThenRun(toolId, (client) async {
      await client.stop();
    });
    logger.log(LogModule.tool, "stop.result", detail: "toolId: $toolId");
  }

  Future<void> delete(String toolId) async {
    logger.log(LogModule.tool, "delete.input", detail: "toolId: $toolId");
    await _checkThenRun(toolId, (client) async {
      await client.stop();
      await _cacheToolStorage.remove(toolId);
    });
    logger.log(LogModule.tool, "delete.result", detail: "toolId: $toolId");
  }

  Future<ToolReturn> call(String toolId, FunctionCall functionCall) async {
    logger.log(
      LogModule.tool,
      "call.input",
      detail: "toolId: $toolId, function: ${functionCall.name}",
    );
    ToolReturn? toolReturn;
    await _checkThenRun(toolId, (client) async {
      toolReturn = await client.call(functionCall);
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
    OpenTool? tool;
    await _checkThenRun(toolId, (client) async {
      tool = await client.load();
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

  Future<void> _checkThenRun(
    String toolId,
    Future<void> Function(OpenToolClient client) onRun,
  ) async {
    logger.log(LogModule.tool, "check.input", detail: "toolId: $toolId");
    OpenToolClient? client = _clients[toolId];
    ToolDao? toolDao = await _cacheToolStorage.get(toolId);
    if (client != null) {
      try {
        await onRun(client);
      } catch (e) {
        if (toolDao != null) {
          toolDao.status = ToolStatusType.NOT_RUNNING;
          await _cacheToolStorage.update(toolDao);
        }
        logger.log(
          LogModule.tool,
          "check.error",
          detail: "toolId: $toolId, error: $e",
        );
        rethrow;
      }
      logger.log(LogModule.tool, "check.result", detail: "toolId: $toolId");
    } else {
      logger.log(LogModule.tool, "check.missing", detail: "toolId: $toolId");
      throw ToolNotFoundException(toolId);
    }
  }
}
