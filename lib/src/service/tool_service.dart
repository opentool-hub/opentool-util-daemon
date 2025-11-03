import 'dart:async';
import 'dart:io';
import 'package:opentool_daemon/src/utils/directory_util.dart';
import 'package:opentool_daemon/src/utils/json_file_util.dart';
import 'package:opentool_daemon/src/utils/zip_util.dart';
import 'package:opentool_dart/opentool_dart.dart';
import '../constants.dart';
import '../storage/cache_storage.dart';
import '../storage/hive_storage.dart';
import '../storage/dao.dart';
import '../utils/command_util.dart';
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
    List<ToolDao> daoList = await _cacheToolStorage.list();
    if(!all) {
      daoList = daoList.where((dao) => dao.status == ToolStatusType.RUNNING).toList();
    }
    return daoList.map((dao) => ToolModel.fromDao(dao)).toList();
  }

  Future<ToolModel> get(String toolId) async {
    ToolDao? toolDao = await _cacheToolStorage.get(toolId);
    if(toolDao == null) throw ToolNotFoundException(toolId);
    return ToolModel.fromDao(toolDao);
  }

  Future<void> startServer(ServerModel server, String hostType, {void Function(String script, String output)? onStdout, void Function(String script, String error)? onStderr, bool printStd = true,}) async {
    /// 1. get the server internal file, .opentool/servers/{name}-{internalId}.ots, then unzip to temp folder
    String name = server.name;
    String internalId = server.internalId;
    String otsFilePath = "$OPENTOOL_PATH${Platform.pathSeparator}$SERVER_FOLDER${Platform.pathSeparator}$name-$internalId.ots";
    String tempFolder = await ZipUtil.unzipToTemp(otsFilePath);

    /// 2. copy temp folder to .opentool/tools/{toolId}
    String toolId = uniqueId();
    String toolFolder = "$OPENTOOL_PATH${Platform.pathSeparator}$TOOL_FOLDER${Platform.pathSeparator}$toolId";
    await DirectoryUtil.copyDirectory(Directory(tempFolder), Directory(toolFolder));

    /// 2. run tool
    String opentoolFileJsonPath = "$toolFolder${Platform.pathSeparator}$OPENTOOL_FILE_JSON_NAME";
    Map<String, dynamic> opentoolFileJson = await JsonFileUtil.readFromFile(opentoolFileJsonPath);
    OpentoolfileConfig config = OpentoolfileConfig.fromJson(opentoolFileJson);
    String workdir = config.run.workdir;
    String entrypoint = config.run.entrypoint;
    List<String> cmds = config.run.cmds;

    String host = hostType;
    cmds.add("--toolHost $host");

    int lastPort = (await _cacheToolStorage.list()).last.port;
    int port = lastPort + 1;
    cmds.add("--toolPort $port");

    String apiKey = uniqueId(shorter: false);
    cmds.add("--toolApiKey $apiKey");

    unawaited(CommandUtil.runStream(workdir, entrypoint, cmds, onStdout: onStdout, onStderr: onStderr, printStd: printStd));

    /// 3. add to storage and clients
    ToolDao toolDao = ToolDao(
      id: toolId,
      alias: toolId,
      host: host,
      port: port,
      apiKey: apiKey,
      status: ToolStatusType.RUNNING,
    );
    await _cacheToolStorage.add(toolDao);
  }

  Future<void> check(String toolId) async {
    await _checkThenRun(toolId, (client) async {
      Version version = await client.version();
    });
  }

  Future<void> stop(String toolId) async {
    await _checkThenRun(toolId, (client) async {
      await client.stop();
    });
  }

  Future<void> delete(String toolId) async {
    await _checkThenRun(toolId, (client) async {
      await client.stop();
      await _cacheToolStorage.remove(toolId);
    });
  }

  Future<ToolReturn> call(String toolId, FunctionCall functionCall) async {
    ToolReturn? toolReturn;
    await _checkThenRun(toolId, (client) async {
      toolReturn = await client.call(functionCall);
    });
    return toolReturn?? ToolReturn(id: functionCall.id, result: {"result": null});
  }

  Future<void> streamCall(String toolId, FunctionCall functionCall, void Function(String event, ToolReturn toolReturn) onToolReturn) async {
    await _checkThenRun(toolId, (client) async {
      await client.streamCall(functionCall, onToolReturn);
    });
  }

  Future<OpenTool?> load(String toolId) async {
    OpenTool? tool;
    await _checkThenRun(toolId, (client) async {
      tool = await client.load();
    });
    return tool;
  }

  Future<void> setAlias(String toolId, String newAlias) async {
    await _checkThenRun(toolId, (client) async {
      ToolDao? toolDao = await _cacheToolStorage.get(toolId);
      if(toolDao == null) throw ToolNotFoundException(toolId);
      toolDao.alias = newAlias;
      await _cacheToolStorage.update(toolDao);
    });
  }

  Future<void> _checkThenRun(String toolId, Future<void> Function(OpenToolClient client) onRun) async {
    OpenToolClient? client = _clients[toolId];
    ToolDao? toolDao = await _cacheToolStorage.get(toolId);
    if(client != null) {
      try {
        await onRun(client);
      } catch (e) {
        if(toolDao != null) {
          toolDao.status = ToolStatusType.NOT_RUNNING;
          await _cacheToolStorage.update(toolDao);
        }
        rethrow;
      }
    } else {
      throw ToolNotFoundException(toolId);
    }
  }
}