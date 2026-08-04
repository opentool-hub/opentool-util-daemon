import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:opentool_dart/opentool_client.dart';
import 'package:opentool_daemon/opentool_daemon_utils.dart';
import 'package:shelf/shelf.dart';
import '../service/model.dart';
import '../service/exception.dart';
import '../service/hub_install_service.dart';
import '../service/server_service.dart';
import '../constants.dart';
import 'dto.dart';

class ServerController {
  ServerService serverService;
  HubInstallService? hubInstallService;

  ServerController(this.serverService, {this.hubInstallService});

  /// GET /servers/list
  Future<Response> listServers(Request request) async {
    logger.log(
      LogModule.http,
      "listServers.input",
      detail: "{}",
      level: Level.FINE,
    );
    List<ServerModel> serverModels = await serverService.list();
    List<OpenToolServerDto> serverDtos = serverModels
        .map((server) => OpenToolServerDto.fromModel(server))
        .toList();
    String responseBodyStr = jsonEncode(
      serverDtos.map((e) => e.toJson()).toList(),
    );
    logger.log(LogModule.http, "listServers", detail: responseBodyStr);
    return Response.ok(responseBodyStr, headers: JSON_HEADERS);
  }

  /// POST /servers/build
  Future<Response> buildServer(Request request) async {
    final query = request.url.queryParameters;
    logger.log(
      LogModule.http,
      "buildServer.input",
      detail: "queryParams: ${jsonEncode(query)}",
      level: Level.FINE,
    );
    String? opentoolfile = query['opentoolfile'];
    String? name = query['name'];
    String? tag = query['tag'];
    if (opentoolfile == null || name == null)
      throw ArgumentError('Missing required parameters');

    StreamController<List<int>> streamController =
        StreamController<List<int>>();
    EventMessageDto startMessageDto = EventMessageDto(
      message: "Build server start - name: $name, tag: $tag",
    );
    _pushData(
      streamController,
      EventType.START,
      jsonEncode(startMessageDto.toJson()),
      logMessage: "buildServer.push",
    );
    await serverService.buildServer(
      opentoolfile,
      name,
      tag,
      (String runScript, String output) {
        CommandOutputDto commandOutputDto = CommandOutputDto(
          script: runScript,
          output: output,
        );
        _pushData(
          streamController,
          EventType.DATA,
          jsonEncode(commandOutputDto.toJson()),
          logMessage: "buildServer.push",
        );
      },
      () {
        EventMessageDto doneMessageDto = EventMessageDto(
          message: "Build server done - name: $name, tag: $tag",
        );
        _pushData(
          streamController,
          EventType.DONE,
          jsonEncode(doneMessageDto.toJson()),
          logMessage: "buildServer.push",
        );
        streamController.close();
      },
    );
    return Response.ok(
      streamController.stream,
      headers: STREAM_HEADERS,
      context: {'shelf.io.buffer_output': false},
    );
  }

  /// DELETE /servers/<serverId>
  Future<Response> deleteServer(Request request, String serverId) async {
    logger.log(
      LogModule.http,
      "deleteServer.input",
      detail: "serverId: $serverId",
      level: Level.FINE,
    );
    await serverService.delete(serverId);
    ServerIdDto serverIdDto = ServerIdDto(id: serverId);
    logger.log(
      LogModule.http,
      "deleteServer",
      detail: jsonEncode(serverIdDto.toJson()),
    );
    return Response.ok(jsonEncode(serverIdDto.toJson()), headers: JSON_HEADERS);
  }

  /// POST /servers/<serverId>/tag?tag=<target_tag>
  Future<Response> tagServer(Request request, String serverId) async {
    final query = request.url.queryParameters;
    logger.log(
      LogModule.http,
      "tagServer.input",
      detail: "queryParams: ${jsonEncode(query)}",
      level: Level.FINE,
    );
    final tag = query['tag'];
    ServerModel serverModel = await serverService.tag(serverId, tag);
    OpenToolServerDto serverDto = OpenToolServerDto.fromModel(serverModel);
    logger.log(
      LogModule.http,
      "tagServer",
      detail: jsonEncode(serverDto.toJson()),
    );
    return Response.ok(jsonEncode(serverDto.toJson()), headers: JSON_HEADERS);
  }

  /// POST /servers/pull
  Future<Response> pullServer(Request request) async {
    final service = hubInstallService;
    if (service == null) {
      return Response.internalServerError(
        body: jsonEncode({
          'error': {
            'code': 'INSTALL_FAILED',
            'message': 'Hub installation service is unavailable',
          },
        }),
        headers: JSON_HEADERS,
      );
    }
    final String payload;
    final HubInstallRequest installRequest;
    try {
      payload = await request.readAsString();
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Request body must be a JSON object');
      }
      final dto = PullInfoDto.fromJson(decoded);
      installRequest = HubInstallRequest.validate(
        registry: dto.registry,
        namespace: dto.namespace,
        name: dto.name,
        version: dto.version,
        client: dto.client,
        allowInsecureHub:
            Platform.environment['OPENTOOL_ALLOW_INSECURE_HUB'] == 'true',
      );
    } catch (error) {
      return Response.badRequest(
        body: jsonEncode({
          'error': {
            'code': 'INVALID_PULL_REQUEST',
            'message': error.toString(),
          },
        }),
        headers: JSON_HEADERS,
      );
    }
    logger.log(
      LogModule.http,
      "pullServer.input",
      detail: "ref: ${installRequest.ref}",
      level: Level.FINE,
    );
    final streamController = StreamController<List<int>>();
    scheduleMicrotask(() async {
      try {
        await service.install(
          installRequest,
          onEvent: (event) => _pushData(
            streamController,
            event.event,
            jsonEncode(event.data),
            logMessage: 'pullServer.push',
          ),
        );
      } on InstallException catch (error) {
        _pushData(
          streamController,
          EventType.ERROR,
          jsonEncode(
            PullErrorDto(
              code: error.code,
              message: error.message,
              retryable: error.retryable,
              requestId: error.requestId,
            ).toJson(),
          ),
          logMessage: 'pullServer.error',
        );
      } catch (error, stackTrace) {
        logger.log(
          LogModule.server,
          'pullServer.error',
          detail: '$error\n$stackTrace',
          level: Level.WARNING,
        );
        _pushData(
          streamController,
          EventType.ERROR,
          jsonEncode(
            PullErrorDto(
              code: 'INSTALL_FAILED',
              message: 'OpenTool installation failed',
              retryable: true,
            ).toJson(),
          ),
        );
      } finally {
        await streamController.close();
      }
    });

    return Response.ok(
      streamController.stream,
      headers: STREAM_HEADERS,
      context: {'shelf.io.buffer_output': false},
    );
  }

  /// GET /servers/<serverId>/export
  Future<Response> exportServer(Request request, String serverId) async {
    final payload = await request.readAsString();
    logger.log(
      LogModule.http,
      "exportServer.input",
      detail: "serverId: $serverId, body: $payload",
      level: Level.FINE,
    );
    Map<String, dynamic> data = jsonDecode(payload);
    PathDto pathDto = PathDto.fromJson(data);
    await serverService.export(serverId, pathDto.path);
    ServerIdDto serverIdDto = ServerIdDto(id: serverId);
    logger.log(
      LogModule.http,
      "exportServer",
      detail: jsonEncode(serverIdDto.toJson()),
    );
    return Response.ok(jsonEncode(serverIdDto.toJson()), headers: JSON_HEADERS);
  }

  /// POST /servers/import
  Future<Response> importServer(Request request) async {
    final payload = await request.readAsString();
    logger.log(
      LogModule.http,
      "exportServer.input",
      detail: "body: $payload",
      level: Level.FINE,
    );
    Map<String, dynamic> data = jsonDecode(payload);
    PathDto pathDto = PathDto.fromJson(data);
    ServerModel serverModel = await serverService.import(pathDto.path);
    OpenToolServerDto serverDto = OpenToolServerDto.fromModel(serverModel);
    logger.log(
      LogModule.http,
      "importServer",
      detail: jsonEncode(serverDto.toJson()),
    );
    return Response.ok(jsonEncode(serverDto.toJson()), headers: JSON_HEADERS);
  }

  /// POST /servers/<serverId>/alias?alias=<target_alias>
  Future<Response> setAlias(Request request, String serverId) async {
    final query = request.url.queryParameters;
    logger.log(
      LogModule.http,
      "setAlias.input",
      detail: "queryParams: ${jsonEncode(query)}",
      level: Level.FINE,
    );
    final alias = query['alias'];
    if (alias == null) throw ArgumentError("alias is null");
    await serverService.setAlias(serverId, alias);
    ServerModel serverModel = await serverService.get(serverId);
    OpenToolServerDto serverDto = OpenToolServerDto.fromModel(serverModel);
    logger.log(
      LogModule.http,
      "setAlias",
      detail: jsonEncode(serverDto.toJson()),
    );
    return Response.ok(jsonEncode(serverDto.toJson()), headers: JSON_HEADERS);
  }

  void _pushData(
    StreamController<List<int>> streamController,
    String eventType,
    String dataString, {
    String? logMessage,
  }) {
    logger.log(
      LogModule.sse,
      logMessage ?? "server.pushData",
      detail: "eventType: $eventType, data: $dataString",
    );
    String data = "event:$eventType\ndata:$dataString\n\n";
    streamController.sink.add(utf8.encode(data));
  }
}
