import 'dart:async';
import 'package:opentool_dart/opentool_dart.dart';
import '../utils/utils.dart';
import 'manage_service.dart';
import 'model.dart';

class RunnerService {
  final ManageService manager;

  RunnerService({required this.manager});

  Future<void> startCheckPeriodic(Duration duration) async {
    Timer.periodic(duration, (Timer timer) async {
      List<OpenToolServerModel> serverModelList = await manager.list();
      serverModelList.forEach((serverModel) async {
        String status = await check(serverModel.id);
        if(status == StatusType.NOT_RUNNING && serverModel.pid != null) {
          manager.updatePid(serverModel.id, null);
        }
      });
    });
  }

  Future<String> stop(String id) async {
    OpenToolServerModel serverModel = await manager.get(id);
    if(serverModel.pid != null) {
      bool result = stopProcess(serverModel.pid!);
      if(result) {
        serverModel.pid = null;
        manager.updatePid(id, null);
        return StatusType.STOP_SUCCESS;
      } else {
        return StatusType.PID_NOT_EXIST;
      }
    } else {
      return StatusType.NOT_RUNNING;
    }
  }

  Future<OpenToolClient> _getClient(String id) async {
    OpenToolServerModel serverModel = await manager.get(id);
    return OpenToolClient(
      isSSL: false,
      host: serverModel.host,
      port: serverModel.port,
      apiKey: (serverModel.apiKeys != null && serverModel.apiKeys!.isNotEmpty)? serverModel.apiKeys!.first : null,
    );
  }

  Future<ToolReturn> call(String id, FunctionCall functionCall) async {
    OpenToolClient client = await _getClient(id);

    try {
      ToolReturn result = await client.call(functionCall);
      return result;
    } catch (e) {
      throw OpenToolServerNoAccessException();
    }
  }

  Future<OpenTool?> load(String id) async {
    OpenToolClient client = await _getClient(id);

    try {
      OpenTool? opentool = await client.load();
      return opentool;
    } catch (e) {
      return null;
    }
  }

  Future<String> check(String id) async {
    OpenToolClient client = await _getClient(id);

    try {
      await client.version();
      return StatusType.RUNNING;
    } catch (e) {
      return StatusType.NOT_RUNNING;
    }
  }
}