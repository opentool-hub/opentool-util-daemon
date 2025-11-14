import 'dart:async';
import 'dart:convert';
import 'package:logging/logging.dart';
import 'package:opentool_dart/opentool_dart.dart';
import 'package:shelf/shelf.dart';
import '../service/model.dart';
import '../service/server_service.dart';
import '../service/tool_service.dart';
import '../constants.dart';
import '../utils/logger.dart';
import 'dto.dart';

class ToolController {
  ToolService toolService;
  ServerService serverService;

  ToolController(this.toolService, this.serverService);

  /// GET /tools/list?all=0
  Future<Response> listTools(Request request) async {
    final queryParams = request.url.queryParameters;
    logger.log(LogModule.http, "listTools.input", detail: jsonEncode(queryParams), level: Level.FINE);
    final all = queryParams['all'] == '1';
    final tools = await toolService.list(all: all);
    List<Map<String, dynamic>> toolsDto = tools.map((tool) => ToolDto.fromModel(tool).toJson()).toList();
    logger.log(LogModule.http, "listTools.output", detail: jsonEncode(toolsDto));
    return Response.ok(jsonEncode(toolsDto), headers: JSON_HEADERS,);
  }

  /// POST /tools/create?from=<serverId>
  Future<Response> runServer(Request request) async {
    final queryParams = request.url.queryParameters;
    logger.log(LogModule.http, "runServer.input", detail: jsonEncode(queryParams), level: Level.FINE);
    String? serverId = queryParams['from'];
    if(serverId == null) throw ArgumentError('serverId is required');
    String hostType = queryParams['hostType']??HostType.ANY;
    ServerModel serverModel = await serverService.get(serverId);
    StreamController<List<int>> streamController = StreamController<List<int>>();
    await toolService.runServer(serverModel, hostType,
      onStdout: (command, output){
        CommandResultDto commandResultDto = CommandResultDto(command: command, output: output);
        _pushData(streamController, EventType.DATA, jsonEncode(commandResultDto.toJson()), logMessage: "runServer.push");
      },
      onStderr: (command, error){
        CommandResultDto commandResultDto = CommandResultDto(command: command, error: error);
        _pushData(streamController, EventType.ERROR, jsonEncode(commandResultDto.toJson()), logMessage: "runServer.push");
      },
    );
    return Response.ok(streamController.stream, headers: STREAM_HEADERS, context: {'shelf.io.buffer_output': false});
  }

  /// POST /tools/<toolId>/start
  Future<Response> startTool(Request request, String toolId) async {
    final queryParams = request.url.queryParameters;
    logger.log(LogModule.http, "startTool.input", detail: "toolId: $toolId, queryParams: ${jsonEncode(queryParams)}", level: Level.FINE);
    String hostType = queryParams['hostType']??HostType.ANY;
    ServerModel serverModel = await serverService.get(toolId);
    StreamController<List<int>> streamController = StreamController<List<int>>();
    await toolService.runServer(serverModel, hostType,
      onStdout: (command, output){
        CommandResultDto commandResultDto = CommandResultDto(command: command, output: output);
        _pushData(streamController, EventType.DATA, jsonEncode(commandResultDto.toJson()), logMessage: "startTool.push");
      },
      onStderr: (command, error){
        CommandResultDto commandResultDto = CommandResultDto(command: command, error: error);
        _pushData(streamController, EventType.ERROR, jsonEncode(commandResultDto.toJson()), logMessage: "startTool.push");
      },
    );
    return Response.ok(streamController.stream, headers: STREAM_HEADERS, context: {'shelf.io.buffer_output': false});
  }

  /// POST /tools/<toolId>/stop
  Future<Response> stopTool(Request request, String toolId) async {
    logger.log(LogModule.http, "stopTool.input", detail: "toolId: $toolId", level: Level.FINE);
    await toolService.stop(toolId);
    ToolIdDto toolIdDto = ToolIdDto(id: toolId);
    logger.log(LogModule.http, "stopTool.output", detail: jsonEncode(toolIdDto.toJson()));
    return Response.ok(jsonEncode(toolIdDto.toJson()), headers: JSON_HEADERS,);
  }

  /// DELETE /tools/<toolId>
  Future<Response> deleteTool(Request request, String toolId) async {
    logger.log(LogModule.http, "deleteTool.input", detail: "toolId: $toolId", level: Level.FINE);
    await toolService.delete(toolId);
    ToolIdDto toolIdDto = ToolIdDto(id: toolId);
    logger.log(LogModule.http, "deleteTool.output", detail: jsonEncode(toolIdDto.toJson()));
    return Response.ok(jsonEncode(toolIdDto.toJson()), headers: JSON_HEADERS,);
  }

  /// POST /tools/<toolId>/call
  Future<Response> callTool(Request request, String toolId) async {
    final payload = await request.readAsString();
    logger.log(LogModule.http, "callTool.input", detail: "toolId: $toolId, body: $payload", level: Level.FINE);
    Map<String, dynamic> data = jsonDecode(payload);
    FunctionCall functionCall = FunctionCall.fromJson(data);
    ToolReturn toolReturn = await toolService.call(toolId, functionCall);
    logger.log(LogModule.http, "callTool.output", detail: jsonEncode(toolReturn.toJson()));
    return Response.ok(jsonEncode(toolReturn.toJson()), headers: JSON_HEADERS,);
  }

  /// POST /tools/<toolId>/streamCall
  Future<Response> streamCallTool(Request request, String toolId) async {
    final payload = await request.readAsString();
    logger.log(LogModule.http, "streamCallTool.input", detail: "toolId: $toolId, body: $payload", level: Level.FINE);
    Map<String, dynamic> data = jsonDecode(payload);
    FunctionCall functionCall = FunctionCall.fromJson(data);

    StreamController<List<int>> streamController = StreamController<List<int>>();
    toolService.streamCall(toolId, functionCall, (String event, ToolReturn toolReturn) {
      _pushData(streamController, event, jsonEncode(toolReturn.toJson()), logMessage: "streamCallTool.push");
    });
    return Response.ok(streamController.stream, headers: STREAM_HEADERS, context: {'shelf.io.buffer_output': false});
  }

  /// GET /tools/<toolId>/load
  Future<Response> loadTool(Request request, String toolId) async {
    logger.log(LogModule.http, "loadTool.input", detail: "toolId: $toolId");
    OpenTool? openTool = await toolService.load(toolId);
    if(openTool == null) {
      return Response.notFound(jsonEncode(JsonParserException().toJson()), headers: JSON_HEADERS,);
    }
    final responseBody = openTool.toJson();
    logger.log(LogModule.http, "loadTool.output", detail: jsonEncode(responseBody));
    return Response.ok(jsonEncode(responseBody), headers: JSON_HEADERS,);
  }

  /// POST /tools/<toolId>/alias?alias=<target_alias>
  Future<Response> setAlias(Request request, String toolId) async {
    final query = request.url.queryParameters;
    logger.log(LogModule.http, "loadTool.input", detail: "toolId: $toolId, queryParams: $query", level: Level.FINE);
    final alias = query['alias'];
    if(alias == null) throw ArgumentError('alias is required');
    await toolService.setAlias(toolId, alias);
    ToolModel toolModel = await toolService.get(toolId);
    ToolDto toolDto = ToolDto.fromModel(toolModel);
    logger.log(LogModule.http, "setAlias", detail: jsonEncode(toolDto.toJson()));
    return Response.ok(jsonEncode(ToolDto.fromModel(toolModel).toJson()), headers: JSON_HEADERS,);
  }

  void _pushData(StreamController<List<int>> streamController, String eventType, String dataString, {String? logMessage}) {
    logger.log(LogModule.sse, logMessage??"tool.pushData", detail: "eventType: $eventType, data: $dataString");
    String data = "event:$eventType\ndata:$dataString\n\n";
    streamController.sink.add(utf8.encode(data));
  }
}