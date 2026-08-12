import 'dart:async';
import 'dart:convert';
import 'package:logging/logging.dart';
import 'package:opentool_dart/opentool_client.dart';
import 'package:opentool_daemon/opentool_daemon_utils.dart';
import 'package:shelf/shelf.dart';
import '../service/model.dart';
import '../service/exception.dart';
import '../service/hub_pull_service.dart';
import '../service/builtin_reconcile_service.dart';
import '../service/pull_cancellation.dart';
import '../service/server_service.dart';
import '../constants.dart';
import 'dto.dart';

class ServerController {
  ServerService serverService;
  HubPullService? hubPullService;
  BuiltinReconcileService? builtinReconcileService;
  HostManagementAuthenticator? hostAuthenticator;

  ServerController(
    this.serverService, {
    this.hubPullService,
    this.builtinReconcileService,
    this.hostAuthenticator,
  });

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
    logger.log(
      LogModule.http,
      "listServers.output",
      detail:
          "count=${serverDtos.length}, bytes=${utf8.encode(responseBodyStr).length}",
      level: Level.FINE,
    );
    return Response.ok(responseBodyStr, headers: JSON_HEADERS);
  }

  /// POST /servers/build
  Future<Response> buildServer(Request request) async {
    final query = request.url.queryParameters;
    logger.log(
      LogModule.http,
      "buildServer.input",
      detail: "name: ${query['name']}, tag: ${query['tag']}",
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
    final existing = await serverService.get(serverId);
    final artifactRemoved = existing.artifactReferenceCount <= 1;
    await serverService.delete(serverId);
    final body = {
      'id': serverId,
      'serverId': serverId,
      'artifactRemoved': artifactRemoved,
    };
    logger.log(
      LogModule.http,
      "deleteServer.output",
      detail: "serverId=$serverId, artifactRemoved=$artifactRemoved",
      level: Level.FINE,
    );
    return Response.ok(jsonEncode(body), headers: JSON_HEADERS);
  }

  /// POST /servers/pull
  Future<Response> pullServer(Request request) async {
    final service = hubPullService;
    if (service == null) {
      return Response.internalServerError(
        body: jsonEncode({
          'error': {
            'code': 'PULL_FAILED',
            'message': 'Hub pull service is unavailable',
          },
        }),
        headers: JSON_HEADERS,
      );
    }
    final String payload;
    final HubPullRequest pullRequest;
    try {
      payload = await request.readAsString();
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Request body must be a JSON object');
      }
      final dto = PullInfoDto.fromJson(decoded);
      pullRequest = HubPullRequest.validate(
        registry: dto.registry,
        namespace: dto.namespace,
        name: dto.name,
        version: dto.version,
        client: dto.client,
      );
    } catch (error) {
      return Response.badRequest(
        body: jsonEncode({
          'error': {'code': 'INVALID_REQUEST', 'message': error.toString()},
        }),
        headers: JSON_HEADERS,
      );
    }
    logger.log(
      LogModule.http,
      "pullServer.input",
      detail: "ref: ${pullRequest.ref}",
      level: Level.FINE,
    );
    final cancellation = PullCancellationToken();
    late final StreamController<List<int>> streamController;
    streamController = StreamController<List<int>>(
      onCancel: cancellation.cancel,
    );
    scheduleMicrotask(() async {
      try {
        final server = await service.pull(
          pullRequest,
          cancellation: cancellation,
          onEvent: (event) {
            if (!cancellation.isCancelled && event.event != EventType.DONE) {
              _pushData(
                streamController,
                event.event,
                jsonEncode(event.data),
                logMessage: 'pullServer.push',
              );
            }
          },
        );
        if (!cancellation.isCancelled) {
          _pushData(
            streamController,
            EventType.DONE,
            jsonEncode(
              PullDoneDto(server: OpenToolServerDto.fromModel(server)).toJson(),
            ),
            logMessage: 'pullServer.push',
          );
        }
      } on ArtifactOperationException catch (error) {
        if (!cancellation.isCancelled)
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
        if (!cancellation.isCancelled)
          _pushData(
            streamController,
            EventType.ERROR,
            jsonEncode(
              PullErrorDto(
                code: 'PULL_FAILED',
                message: 'OpenTool pull failed',
                retryable: true,
              ).toJson(),
            ),
          );
      } finally {
        if (!streamController.isClosed) await streamController.close();
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
      detail: "serverId: $serverId",
      level: Level.FINE,
    );
    Map<String, dynamic> data = jsonDecode(payload);
    PathDto pathDto = PathDto.fromJson(data);
    await serverService.export(serverId, pathDto.path);
    ServerIdDto serverIdDto = ServerIdDto(id: serverId);
    logger.log(
      LogModule.http,
      "exportServer",
      detail: "serverId=$serverId",
      level: Level.FINE,
    );
    return Response.ok(jsonEncode(serverIdDto.toJson()), headers: JSON_HEADERS);
  }

  /// POST /servers/import
  Future<Response> importServer(Request request) async {
    final payload = await request.readAsString();
    Map<String, dynamic> data = jsonDecode(payload);
    PathDto pathDto = PathDto.fromJson(data);
    ServerModel serverModel = await serverService.import(pathDto.path);
    OpenToolServerDto serverDto = OpenToolServerDto.fromModel(serverModel);
    logger.log(
      LogModule.http,
      "importServer",
      detail: "serverId=${serverDto.id}",
      level: Level.FINE,
    );
    return Response.ok(jsonEncode(serverDto.toJson()), headers: JSON_HEADERS);
  }

  /// PUT /servers/builtins/reconcile
  Future<Response> reconcileBuiltins(Request request) async {
    final service = builtinReconcileService;
    final authenticator = hostAuthenticator;
    if (service == null ||
        authenticator == null ||
        !authenticator.authorize(
          request.headers[HOST_MANAGEMENT_TOKEN_HEADER],
        )) {
      return Response.forbidden(
        jsonEncode({
          'error': {
            'code': 'HOST_AUTH_REQUIRED',
            'message': 'A valid host management credential is required',
            'retryable': false,
          },
        }),
        headers: JSON_HEADERS,
      );
    }
    final decoded = jsonDecode(await request.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const ArtifactOperationException(
        code: 'INVALID_REQUEST',
        message: 'Request body must be an object',
        retryable: false,
      );
    }
    final rawItems = decoded['items'];
    if (rawItems is! List) {
      throw const ArtifactOperationException(
        code: 'INVALID_REQUEST',
        message: 'items must be an array',
        retryable: false,
      );
    }
    final result = await service.reconcile(
      bundleFamily: decoded['bundleFamily'] as String? ?? '',
      bundleId: decoded['bundleId'] as String? ?? '',
      items: rawItems.map((value) {
        final item = Map<String, dynamic>.from(value as Map);
        return BuiltinItemInput(
          key: item['key'] as String? ?? '',
          path: item['path'] as String? ?? '',
          expectedDigest: item['expectedDigest'] as String? ?? '',
          expectedSize: item['expectedSize'] as int? ?? -1,
        );
      }).toList(),
    );
    return Response.ok(jsonEncode(result.toJson()), headers: JSON_HEADERS);
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
      detail: "serverId=$serverId",
      level: Level.FINE,
    );
    return Response.ok(jsonEncode(serverDto.toJson()), headers: JSON_HEADERS);
  }

  void _pushData(
    StreamController<List<int>> streamController,
    String eventType,
    String dataString, {
    String? logMessage,
  }) {
    if (streamController.isClosed) return;
    logger.log(
      LogModule.sse,
      logMessage ?? "server.pushData",
      detail: "eventType=$eventType, bytes=${utf8.encode(dataString).length}",
      level: Level.FINE,
    );
    String data = "event:$eventType\ndata:$dataString\n\n";
    streamController.sink.add(utf8.encode(data));
  }
}
