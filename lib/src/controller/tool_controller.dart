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
    logger.log(
      LogModule.http,
      "listTools.input",
      detail: jsonEncode(queryParams),
      level: Level.FINE,
    );
    final all = queryParams['all'] == '1';
    final tools = await toolService.list(all: all);
    List<Map<String, dynamic>> toolsDto = tools
        .map((tool) => ToolDto.fromModel(tool).toJson())
        .toList();
    logger.log(
      LogModule.http,
      "listTools.output",
      detail: jsonEncode(toolsDto),
    );
    return Response.ok(jsonEncode(toolsDto), headers: JSON_HEADERS);
  }

  /// POST /tools/create?serverId=<serverId>&timeout=<seconds>
  Future<Response> runServer(Request request) async {
    final queryParams = request.url.queryParameters;
    logger.log(
      LogModule.http,
      "runServer.input",
      detail: jsonEncode(queryParams),
      level: Level.FINE,
    );
    String? serverId = queryParams['serverId'];
    if (serverId == null) throw ArgumentError('serverId is required');
    String hostType = queryParams['hostType'] ?? HostType.ANY;
    final int timeoutSeconds =
        int.tryParse(queryParams['timeout'] ?? '-1') ?? -1;
    ServerModel serverModel = await serverService.get(serverId);
    final streamController = StreamController<List<int>>();
    final completer = Completer<void>();
    bool isClosed = false;

    void closeStream() {
      if (isClosed) return;
      isClosed = true;
      unawaited(streamController.close());
    }

    void completeSuccess(ToolModel toolModel) {
      if (completer.isCompleted) return;
      final message =
          'Tool ${toolModel.id} listening on ${toolModel.host}:${toolModel.port}';
      CommandResultDto resultDto = CommandResultDto(
        command: 'runServer',
        output: message,
      );
      _pushData(
        streamController,
        EventType.DATA,
        jsonEncode(resultDto.toJson()),
        logMessage: 'runServer.push',
      );
      completer.complete();
      closeStream();
    }

    void completeError(Object error, StackTrace stackTrace) {
      if (completer.isCompleted) {
        logger.log(
          LogModule.http,
          'runServer.error.late',
          detail: 'error: $error\n$stackTrace',
          level: Level.WARNING,
        );
        return;
      }
      CommandResultDto errorDto = CommandResultDto(
        command: 'runServer',
        error: error.toString(),
      );
      _pushData(
        streamController,
        EventType.ERROR,
        jsonEncode(errorDto.toJson()),
        logMessage: 'runServer.push',
      );
      logger.log(
        LogModule.http,
        'runServer.error',
        detail: 'error: $error\n$stackTrace',
        level: Level.WARNING,
      );
      completer.complete();
      closeStream();
    }

    Future<ToolModel> runFuture;
    try {
      runFuture = toolService.runServer(serverModel, hostType);
    } catch (error, stackTrace) {
      completeError(error, stackTrace);
      return Response.ok(
        streamController.stream,
        headers: STREAM_HEADERS,
        context: {'shelf.io.buffer_output': false},
      );
    }

    runFuture.then(completeSuccess).catchError(completeError);

    if (timeoutSeconds >= 0) {
      Future.delayed(Duration(seconds: timeoutSeconds), () {
        if (completer.isCompleted) return;
        final timeoutMessage =
            'Tool is still starting; daemon will finish in background.';
        CommandResultDto timeoutDto = CommandResultDto(
          command: 'runServer',
          output: timeoutMessage,
        );
        _pushData(
          streamController,
          EventType.DATA,
          jsonEncode(timeoutDto.toJson()),
          logMessage: 'runServer.timeout',
        );
        logger.log(
          LogModule.http,
          'runServer.timeout',
          detail: 'serverId: $serverId timeout: $timeoutSeconds',
          level: Level.INFO,
        );
        completer.complete();
        closeStream();
      });
    }

    return Response.ok(
      streamController.stream,
      headers: STREAM_HEADERS,
      context: {'shelf.io.buffer_output': false},
    );
  }

  /// POST /tools/<toolId>/start
  Future<Response> startTool(Request request, String toolId) async {
    final queryParams = request.url.queryParameters;
    logger.log(
      LogModule.http,
      "startTool.input",
      detail: "toolId: $toolId, queryParams: ${jsonEncode(queryParams)}",
      level: Level.FINE,
    );
    final int timeoutSeconds =
        int.tryParse(queryParams['timeout'] ?? '-1') ?? -1;
    String? hostOverride = queryParams['hostType'];
    ToolModel toolModel = await toolService.get(toolId);
    if (hostOverride != null && hostOverride.isNotEmpty) {
      toolModel.host = hostOverride;
    }

    final streamController = StreamController<List<int>>();
    final completer = Completer<void>();
    bool isClosed = false;

    void closeStream() {
      if (isClosed) return;
      isClosed = true;
      unawaited(streamController.close());
    }

    void completeError(Object error, StackTrace stackTrace) {
      if (completer.isCompleted) {
        logger.log(
          LogModule.http,
          'startTool.error.late',
          detail: 'error: $error\n$stackTrace',
          level: Level.WARNING,
        );
        return;
      }
      CommandResultDto errorDto = CommandResultDto(
        command: 'startTool',
        error: error.toString(),
      );
      if (!isClosed) {
        _pushData(
          streamController,
          EventType.ERROR,
          jsonEncode(errorDto.toJson()),
          logMessage: 'startTool.push',
        );
      }
      completer.complete();
      closeStream();
    }

    Future<void> startFuture;
    try {
      startFuture = toolService.startTool(
        toolModel,
        onStdout: (command, output) {
          if (isClosed) return;
          CommandResultDto commandResultDto = CommandResultDto(
            command: command,
            output: output,
          );
          _pushData(
            streamController,
            EventType.DATA,
            jsonEncode(commandResultDto.toJson()),
            logMessage: "startTool.push",
          );
        },
        onStderr: (command, error) {
          if (isClosed) return;
          CommandResultDto commandResultDto = CommandResultDto(
            command: command,
            error: error,
          );
          _pushData(
            streamController,
            EventType.ERROR,
            jsonEncode(commandResultDto.toJson()),
            logMessage: "startTool.push",
          );
        },
      );
    } catch (error, stackTrace) {
      completeError(error, stackTrace);
      return Response.ok(
        streamController.stream,
        headers: STREAM_HEADERS,
        context: {'shelf.io.buffer_output': false},
      );
    }

    startFuture.catchError(completeError);

    if (timeoutSeconds >= 0) {
      Future.delayed(Duration(seconds: timeoutSeconds), () {
        if (completer.isCompleted) return;
        const timeoutMessage =
            'Tool is still starting; daemon will finish in background.';
        CommandResultDto timeoutDto = CommandResultDto(
          command: 'startTool',
          output: timeoutMessage,
        );
        if (!isClosed) {
          _pushData(
            streamController,
            EventType.DATA,
            jsonEncode(timeoutDto.toJson()),
            logMessage: 'startTool.timeout',
          );
        }
        logger.log(
          LogModule.http,
          'startTool.timeout',
          detail: 'toolId: $toolId timeout: $timeoutSeconds',
          level: Level.INFO,
        );
        completer.complete();
        closeStream();
      });
    }

    return Response.ok(
      streamController.stream,
      headers: STREAM_HEADERS,
      context: {'shelf.io.buffer_output': false},
    );
  }

  /// POST /tools/<toolId>/stop
  Future<Response> stopTool(Request request, String toolId) async {
    logger.log(
      LogModule.http,
      "stopTool.input",
      detail: "toolId: $toolId",
      level: Level.FINE,
    );
    await toolService.stop(toolId);
    ToolIdDto toolIdDto = ToolIdDto(id: toolId);
    logger.log(
      LogModule.http,
      "stopTool.output",
      detail: jsonEncode(toolIdDto.toJson()),
    );
    return Response.ok(jsonEncode(toolIdDto.toJson()), headers: JSON_HEADERS);
  }

  /// DELETE /tools/<toolId>
  Future<Response> deleteTool(Request request, String toolId) async {
    logger.log(
      LogModule.http,
      "deleteTool.input",
      detail: "toolId: $toolId",
      level: Level.FINE,
    );
    await toolService.delete(toolId);
    ToolIdDto toolIdDto = ToolIdDto(id: toolId);
    logger.log(
      LogModule.http,
      "deleteTool.output",
      detail: jsonEncode(toolIdDto.toJson()),
    );
    return Response.ok(jsonEncode(toolIdDto.toJson()), headers: JSON_HEADERS);
  }

  /// POST /tools/<toolId>/call
  Future<Response> callTool(Request request, String toolId) async {
    final payload = await request.readAsString();
    logger.log(
      LogModule.http,
      "callTool.input",
      detail: "toolId: $toolId, body: $payload",
      level: Level.FINE,
    );
    Map<String, dynamic> data = jsonDecode(payload);
    FunctionCall functionCall = FunctionCall.fromJson(data);
    ToolReturn toolReturn = await toolService.call(toolId, functionCall);
    logger.log(
      LogModule.http,
      "callTool.output",
      detail: jsonEncode(toolReturn.toJson()),
    );
    return Response.ok(jsonEncode(toolReturn.toJson()), headers: JSON_HEADERS);
  }

  /// POST /tools/<toolId>/streamCall
  Future<Response> streamCallTool(Request request, String toolId) async {
    final payload = await request.readAsString();
    logger.log(
      LogModule.http,
      "streamCallTool.input",
      detail: "toolId: $toolId, body: $payload",
      level: Level.FINE,
    );
    Map<String, dynamic> data = jsonDecode(payload);
    FunctionCall functionCall = FunctionCall.fromJson(data);

    StreamController<List<int>> streamController =
        StreamController<List<int>>();
    bool isStreamClosed = false;

    void closeStream() {
      if (isStreamClosed) return;
      isStreamClosed = true;
      unawaited(streamController.close());
    }
    toolService.streamCall(toolId, functionCall, (
      String event,
      ToolReturn toolReturn,
    ) {
      _pushData(
        streamController,
        event,
        jsonEncode(toolReturn.toJson()),
        logMessage: "streamCallTool.push",
      );
      if (event == EventType.DONE || event == EventType.ERROR) {
        closeStream();
      }
    });
    return Response.ok(
      streamController.stream,
      headers: STREAM_HEADERS,
      context: {'shelf.io.buffer_output': false},
    );
  }

  /// GET /tools/<toolId>/load
  Future<Response> loadTool(Request request, String toolId) async {
    logger.log(LogModule.http, "loadTool.input", detail: "toolId: $toolId");
    OpenTool? openTool = await toolService.load(toolId);
    if (openTool == null) {
      return Response.notFound(
        jsonEncode(JsonParserException().toJson()),
        headers: JSON_HEADERS,
      );
    }
    final responseBody = openTool.toJson();
    logger.log(
      LogModule.http,
      "loadTool.output",
      detail: jsonEncode(responseBody),
    );
    return Response.ok(jsonEncode(responseBody), headers: JSON_HEADERS);
  }

  /// POST /tools/<toolId>/alias?alias=<target_alias>
  Future<Response> setAlias(Request request, String toolId) async {
    final query = request.url.queryParameters;
    logger.log(
      LogModule.http,
      "loadTool.input",
      detail: "toolId: $toolId, queryParams: $query",
      level: Level.FINE,
    );
    final alias = query['alias'];
    if (alias == null) throw ArgumentError('alias is required');
    await toolService.setAlias(toolId, alias);
    ToolModel toolModel = await toolService.get(toolId);
    ToolDto toolDto = ToolDto.fromModel(toolModel);
    logger.log(
      LogModule.http,
      "setAlias",
      detail: jsonEncode(toolDto.toJson()),
    );
    return Response.ok(
      jsonEncode(ToolDto.fromModel(toolModel).toJson()),
      headers: JSON_HEADERS,
    );
  }

  void _pushData(
    StreamController<List<int>> streamController,
    String eventType,
    String dataString, {
    String? logMessage,
  }) {
    logger.log(
      LogModule.sse,
      logMessage ?? "tool.pushData",
      detail: "eventType: $eventType, data: $dataString",
    );
    String data = "event:$eventType\ndata:$dataString\n\n";
    streamController.sink.add(utf8.encode(data));
  }
}
