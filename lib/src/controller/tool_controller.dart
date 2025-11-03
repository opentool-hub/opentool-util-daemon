import 'dart:async';
import 'dart:convert';
import 'package:opentool_dart/opentool_dart.dart';
import 'package:shelf/shelf.dart';
import '../service/model.dart';
import '../service/server_service.dart';
import '../service/tool_service.dart';
import '../constants.dart';
import 'dto.dart';

class ToolController {
  ToolService toolService;
  ServerService serverService;

  ToolController(this.toolService, this.serverService);

  /// GET /tools/list?all=0
  Future<Response> listTools(Request request) async {
    final queryParams = request.url.queryParameters;
    final all = queryParams['all'] == '1';
    final tools = await toolService.list(all: all);
    List<Map<String, dynamic>> toolsDto = tools.map((tool) => ToolDto.fromModel(tool).toJson()).toList();
    return Response.ok(jsonEncode(toolsDto), headers: JSON_HEADERS,);
  }

  /// POST /tools/{serverId}/start
  Future<Response> startServer(Request request, String serverId) async {
    final queryParams = request.url.queryParameters;
    String hostType = queryParams['hostType']??HostType.ANY;
    ServerModel serverModel = await serverService.get(serverId);
    StreamController<List<int>> streamController = StreamController<List<int>>();
    await toolService.startServer(serverModel, hostType,
      onStdout: (command, output){
        CommandResultDto commandResultDto = CommandResultDto(command: command, output: output);
        _pushData(streamController, EventType.DATA, jsonEncode(commandResultDto.toJson()));
      },
      onStderr: (command, error){
        CommandResultDto commandResultDto = CommandResultDto(command: command, error: error);
        _pushData(streamController, EventType.ERROR, jsonEncode(commandResultDto.toJson()));
      },
    );
    return Response.ok(streamController.stream, headers: STREAM_HEADERS, context: {'shelf.io.buffer_output': false});
  }

  /// POST /tools/{toolId}/stop
  Future<Response> stopTool(Request request, String toolId) async {
    await toolService.stop(toolId);
    ToolIdDto toolIdDto = ToolIdDto(id: toolId);
    return Response.ok(jsonEncode(toolIdDto.toJson()), headers: JSON_HEADERS,);
  }

  /// DELETE /tools/{toolId}
  Future<Response> deleteTool(Request request, String toolId) async {
    await toolService.delete(toolId);
    ToolIdDto toolIdDto = ToolIdDto(id: toolId);
    return Response.ok(jsonEncode(toolIdDto.toJson()), headers: JSON_HEADERS,);
  }

  /// POST /tools/{toolId}/call
  Future<Response> callTool(Request request, String toolId) async {
    final payload = await request.readAsString();
    Map<String, dynamic> data = jsonDecode(payload);
    FunctionCall functionCall = FunctionCall.fromJson(data);
    ToolReturn toolReturn = await toolService.call(toolId, functionCall);
    return Response.ok(jsonEncode(toolReturn.toJson()), headers: JSON_HEADERS,);
  }

  /// POST /tools/{toolId}/streamCall
  Future<Response> streamCallTool(Request request, String toolId) async {
    final payload = await request.readAsString();
    Map<String, dynamic> data = jsonDecode(payload);
    FunctionCall functionCall = FunctionCall.fromJson(data);

    StreamController<List<int>> streamController = StreamController<List<int>>();
    toolService.streamCall(toolId, functionCall, (String event, ToolReturn toolReturn) {
      _pushData(streamController, event, jsonEncode(toolReturn.toJson()));
    });
    return Response.ok(streamController.stream, headers: STREAM_HEADERS, context: {'shelf.io.buffer_output': false});
  }

  /// GET /tools/{toolId}/load
  Future<Response> loadTool(Request request, String toolId) async {
    OpenTool? openTool = await toolService.load(toolId);
    if(openTool == null) {
      return Response.notFound(jsonEncode(JsonParserException().toJson()), headers: JSON_HEADERS,);
    }
    final responseBody = openTool.toJson();
    return Response.ok(jsonEncode(responseBody), headers: JSON_HEADERS,);
  }

  /// POST /tools/{toolId}/alias?alias=<target_alias>
  Future<Response> setAlias(Request request, String toolId) async {
    final query = request.url.queryParameters;
    final alias = query['alias'];
    if(alias == null) throw ArgumentError('alias is required');
    await toolService.setAlias(toolId, alias);
    ToolModel toolModel = await toolService.get(toolId);
    return Response.ok(jsonEncode(ToolDto.fromModel(toolModel).toJson()), headers: JSON_HEADERS,);
  }

  void _pushData(StreamController<List<int>> streamController, String eventType, String dataString) {
    String data = "event:$eventType\ndata:$dataString\n\n";
    streamController.sink.add(utf8.encode(data));
  }
}