import 'dart:async';
import 'dart:convert';
import 'package:logging/logging.dart';
import 'package:opentool_daemon/src/service/manage_service.dart';
import 'package:opentool_dart/opentool_dart.dart';
import 'package:shelf/shelf.dart';
import '../service/model.dart';
import '../service/server_service.dart';
import '../constants.dart';
import '../utils/logger.dart';
import 'dto.dart';

class ServerController {
  ServerService serverService;
  ManageService manageService;

  ServerController(this.serverService, this.manageService);

  /// GET /servers/list
  Future<Response> listServers(Request request) async {
    logger.log(LogModule.http, "listServers.input", detail: "{}", level: Level.FINE);
    List<ServerModel> serverModels = await serverService.list();
    List<OpenToolServerDto> serverDtos = serverModels.map((server) => OpenToolServerDto.fromModel(server)).toList();
    String responseBodyStr = jsonEncode(serverDtos.map((e) => e.toJson()).toList());
    logger.log(LogModule.http, "listServers", detail: responseBodyStr);
    return Response.ok(responseBodyStr, headers: JSON_HEADERS);
  }

  /// POST /servers/build
  Future<Response> buildServer(Request request) async {
    final query = request.url.queryParameters;
    logger.log(LogModule.http, "buildServer.input", detail: "queryParams: ${jsonEncode(query)}", level: Level.FINE);
    String? opentoolfile = query['opentoolfile'];
    String? name = query['name'];
    String? tag = query['tag'];
    if(opentoolfile == null || name == null) throw ArgumentError('Missing required parameters');

    StreamController<List<int>> streamController = StreamController<List<int>>();
    EventMessageDto startMessageDto = EventMessageDto(message: "Build server start - name: $name, tag: $tag");
    _pushData(streamController, EventType.START, jsonEncode(startMessageDto.toJson()), logMessage: "buildServer.push");
    await serverService.buildServer(opentoolfile, name, tag, (String runScript, String output) {
      CommandOutputDto commandOutputDto = CommandOutputDto(script: runScript, output: output);
      _pushData(streamController, EventType.DATA, jsonEncode(commandOutputDto.toJson()), logMessage: "buildServer.push");
    }, () {
      EventMessageDto doneMessageDto = EventMessageDto(message: "Build server done - name: $name, tag: $tag");
      _pushData(streamController, EventType.DONE, jsonEncode(doneMessageDto.toJson()), logMessage: "buildServer.push");
      streamController.close();
    });
    return Response.ok(streamController.stream, headers: STREAM_HEADERS, context: {'shelf.io.buffer_output': false});
  }

  /// DELETE /servers/<serverId>
  Future<Response> deleteServer(Request request, String serverId) async {
    logger.log(LogModule.http, "deleteServer.input", detail: "serverId: $serverId", level: Level.FINE);
    await serverService.delete(serverId);
    ServerIdDto serverIdDto = ServerIdDto(id: serverId);
    logger.log(LogModule.http, "deleteServer", detail: jsonEncode(serverIdDto.toJson()));
    return Response.ok(jsonEncode(serverIdDto.toJson()), headers: JSON_HEADERS);
  }

  /// POST /servers/<serverId>/tag?tag=<target_tag>
  Future<Response> tagServer(Request request, String serverId) async {
    final query = request.url.queryParameters;
    logger.log(LogModule.http, "tagServer.input", detail: "queryParams: ${jsonEncode(query)}", level: Level.FINE);
    final tag = query['tag'];
    ServerModel serverModel = await serverService.tag(serverId, tag);
    OpenToolServerDto serverDto = OpenToolServerDto.fromModel(serverModel);
    logger.log(LogModule.http, "tagServer", detail: jsonEncode(serverDto.toJson()));
    return Response.ok(jsonEncode(serverDto.toJson()), headers: JSON_HEADERS);
  }

  /// POST /servers/pull?name=<target_name>&tag=<target_tag>
  Future<Response> pullServer(Request request) async {
    Map<String, String> query = request.url.queryParameters;
    logger.log(LogModule.http, "pullServer.input", detail: "queryParams: ${jsonEncode(query)}", level: Level.FINE);
    PullInfoDto pullInfoDto = PullInfoDto.fromJson(query);
    String name = pullInfoDto.name;
    String tag = pullInfoDto.tag??NULL_TAG;
    StreamController<List<int>> streamController = StreamController<List<int>>();
    String otsFileTempPath = await manageService.pullToTemp(
      name: name,
      tag: tag,
      onStart:  (int sizeByByte, String digest) {
        PullStartDto pullStartDto = PullStartDto(pullInfoDto: pullInfoDto, sizeByByte: sizeByByte, digest: digest);
        _pushData(streamController, EventType.START, jsonEncode(pullStartDto.toJson()), logMessage: "pullServer.push");
      },
      onDownload:  (int percent) {
        PullDownloadDto pullDownloadDto = PullDownloadDto(pullInfoDto: pullInfoDto, percent: percent);
        _pushData(streamController, EventType.DATA, jsonEncode(pullDownloadDto.toJson()), logMessage: "pullServer.push");
      },
      onDone:  () {
        _pushData(streamController, EventType.DONE, jsonEncode(pullInfoDto.toJson()), logMessage: "pullServer.push");
        streamController.close();
      }
    );
    await serverService.afterPullToTemp(otsFileTempPath);

    return Response.ok(streamController.stream, headers: STREAM_HEADERS, context: {'shelf.io.buffer_output': false});
  }

  /// POST /servers/<serverId>/push
  Future<Response> pushServer(Request request, String serverId) async {
    logger.log(LogModule.http, "pushServer.input", detail: "serverId: $serverId", level: Level.FINE);
    String otsFilePath = await serverService.beforePush(serverId);
    StreamController<List<int>> streamController = StreamController<List<int>>();
    await manageService.push(
      otsFilePath: otsFilePath,
      onStart: (int sizeByByte, String digest) {
        PushStartDto pushStartDto = PushStartDto(serverId: serverId, sizeByByte: sizeByByte, digest: digest);
        _pushData(streamController, EventType.START, jsonEncode(pushStartDto.toJson()), logMessage: "pushServer.push");
      },
      onUpload: (int percent) {
        PushUploadDto pushUploadDto = PushUploadDto(serverId: serverId, percent: percent);
        _pushData(streamController, EventType.DATA, jsonEncode(pushUploadDto.toJson()), logMessage: "pushServer.push");
      },
      onDone: () {
        ServerIdDto serverIdDto = ServerIdDto(id: serverId);
        _pushData(streamController, EventType.DONE, jsonEncode(serverIdDto), logMessage: "pushServer.push");
        streamController.close();
      }
    );
    await serverService.afterPush(otsFilePath);

    return Response.ok(streamController.stream, headers: STREAM_HEADERS, context: {'shelf.io.buffer_output': false});
  }

  /// GET /servers/<serverId>/export
  Future<Response> exportServer(Request request, String serverId) async {
    final payload = await request.readAsString();
    logger.log(LogModule.http, "exportServer.input", detail: "serverId: $serverId, body: $payload", level: Level.FINE);
    Map<String, dynamic> data = jsonDecode(payload);
    PathDto pathDto = PathDto.fromJson(data);
    await serverService.export(serverId, pathDto.path);
    ServerIdDto serverIdDto = ServerIdDto(id: serverId);
    logger.log(LogModule.http, "exportServer", detail: jsonEncode(serverIdDto.toJson()));
    return Response.ok(jsonEncode(serverIdDto.toJson()), headers: JSON_HEADERS);
  }

  /// POST /servers/import
  Future<Response> importServer(Request request) async {
    final payload = await request.readAsString();
    logger.log(LogModule.http, "exportServer.input", detail: "body: $payload", level: Level.FINE);
    Map<String, dynamic> data = jsonDecode(payload);
    PathDto pathDto = PathDto.fromJson(data);
    ServerModel serverModel = await serverService.import(pathDto.path);
    OpenToolServerDto serverDto = OpenToolServerDto.fromModel(serverModel);
    logger.log(LogModule.http, "importServer", detail: jsonEncode(serverDto.toJson()));
    return Response.ok(jsonEncode(serverDto.toJson()), headers: JSON_HEADERS);
  }

  /// POST /servers/<serverId>/alias?alias=<target_alias>
  Future<Response> setAlias(Request request, String serverId) async {
    final query = request.url.queryParameters;
    logger.log(LogModule.http, "setAlias.input", detail: "queryParams: ${jsonEncode(query)}", level: Level.FINE);
    final alias = query['alias'];
    if (alias == null) throw ArgumentError("alias is null");
    await serverService.setAlias(serverId, alias);
    ServerModel serverModel = await serverService.get(serverId);
    OpenToolServerDto serverDto = OpenToolServerDto.fromModel(serverModel);
    logger.log(LogModule.http, "setAlias", detail: jsonEncode(serverDto.toJson()));
    return Response.ok(jsonEncode(serverDto.toJson()), headers: JSON_HEADERS);
  }

  void _pushData(StreamController<List<int>> streamController, String eventType, String dataString, {String? logMessage}) {
    logger.log(LogModule.sse, logMessage??"server.pushData", detail: "eventType: $eventType, data: $dataString");
    String data = "event:$eventType\ndata:$dataString\n\n";
    streamController.sink.add(utf8.encode(data));
  }

}