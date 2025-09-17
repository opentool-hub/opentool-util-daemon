import 'dart:async';
import 'package:opentool_dart/opentool_dart.dart';
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
        if(status == ServerStatusType.NOT_RUNNING && serverModel.pid != null) {
          manager.updatePid(serverModel.id, null);
        }
      });
    });
  }

  Future<String> check(String id) async {
    OpenToolClient client = await _getClient(id);

    try {
      await client.version();
      return ServerStatusType.RUNNING;
    } catch (e) {
      return ServerStatusType.NOT_RUNNING;
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

  Future<ToolReturn> call(String id, FunctionCall functionCall) async {
    OpenToolClient client = await _getClient(id);

    try {
      ToolReturn result = await client.call(functionCall);
      return result;
    } catch (e) {
      throw OpenToolServerNoAccessException();
    }
  }

  Future<ToolReturn> streamCall(String id, FunctionCall functionCall) async {
    OpenToolClient client = await _getClient(id);

    try {
      Map<String, dynamic> accumulatedData = {};
      Completer<ToolReturn> completer = Completer<ToolReturn>();
      
      await client.streamCall(functionCall, (String event, ToolReturn toolReturn) {
        print("Stream call event: $event");
        print("Stream call toolReturn: ${toolReturn.result}");
        if (event == EventType.DATA) {
          accumulatedData.addAll(toolReturn.result);
        } else if (event == EventType.ERROR) {
          completer.completeError(Exception('Stream call error: ${toolReturn.result}'));
        } else if (event == EventType.DONE) {
          completer.complete(ToolReturn(id: functionCall.id, result: accumulatedData));
        }
      });
      
      return await completer.future;
    } catch (e) {
      throw OpenToolServerNoAccessException();
    }
  }

  Future<bool> stop(String id) async {
    OpenToolClient client = await _getClient(id);

    try {
      StatusInfo? result = await client.stop();
      return result?.status == StatusType.STOPPED;
    } catch (e) {
      throw OpenToolServerNoAccessException();
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
}