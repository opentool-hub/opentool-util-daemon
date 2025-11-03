import 'dart:async';
import 'dart:convert';
import 'package:opentool_daemon/src/service/manage_service.dart';
import 'package:opentool_dart/opentool_dart.dart';
import 'package:shelf/shelf.dart';
import '../service/model.dart';
import '../service/server_service.dart';
import '../constants.dart';
import 'dto.dart';

class ServerController {
  ServerService serverService;
  ManageService manageService;

  ServerController(this.serverService, this.manageService);

  /// GET /servers/list
  Future<Response> listServers(Request request) async {
    List<ServerModel> serverModels = await serverService.list();
    List<OpenToolServerDto> serverDtos = serverModels.map((server) => OpenToolServerDto.fromModel(server)).toList();
    String responseBodyStr = jsonEncode(serverDtos.map((e) => e.toJson()).toList());
    return Response.ok(responseBodyStr, headers: JSON_HEADERS);
  }

  /// POST /servers/build
  Future<Response> buildServer(Request request) async {
    final query = request.url.queryParameters;
    String? opentoolfile = query['opentoolfile'];
    String? name = query['name'];
    String? tag = query['tag'];
    if(opentoolfile == null || name == null) throw ArgumentError('Missing required parameters');

    StreamController<List<int>> streamController = StreamController<List<int>>();
    EventMessageDto startMessageDto = EventMessageDto(message: "Build server start - name: $name, tag: $tag");
    _pushData(streamController, EventType.START, jsonEncode(startMessageDto.toJson()));
    await serverService.buildServer(opentoolfile, name, tag, (String runScript, String output) {
      CommandOutputDto commandOutputDto = CommandOutputDto(script: runScript, output: output);
      _pushData(streamController, EventType.DATA, jsonEncode(commandOutputDto.toJson()));
    }, () {
      EventMessageDto doneMessageDto = EventMessageDto(message: "Build server done - name: $name, tag: $tag");
      _pushData(streamController, EventType.DONE, jsonEncode(doneMessageDto.toJson()));
      streamController.close();
    });
    return Response.ok(streamController.stream, headers: STREAM_HEADERS, context: {'shelf.io.buffer_output': false});
  }

  /// DELETE /servers/{server_id}
  Future<Response> deleteServer(Request request, String serverId) async {
    await serverService.delete(serverId);
    ServerIdDto serverIdDto = ServerIdDto(id: serverId);
    return Response.ok(jsonEncode(serverIdDto.toJson()), headers: JSON_HEADERS);
  }

  /// POST /servers/{server_id}/tag?tag=<target_tag>
  Future<Response> tagServer(Request request, String serverId) async {
    final query = request.url.queryParameters;
    final tag = query['tag'];
    ServerModel serverModel = await serverService.tag(serverId, tag);
    OpenToolServerDto serverDto = OpenToolServerDto.fromModel(serverModel);
    return Response.ok(jsonEncode(serverDto.toJson()), headers: JSON_HEADERS);
  }

  /// POST /servers/pull?name=<target_name>&tag=<target_tag>
  Future<Response> pullServer(Request request) async {
    Map<String, String> query = request.url.queryParameters;
    PullInfoDto pullInfoDto = PullInfoDto.fromJson(query);
    String name = pullInfoDto.name;
    String tag = pullInfoDto.tag??NULL_TAG;
    StreamController<List<int>> streamController = StreamController<List<int>>();
    String otsFileTempPath = await manageService.pullToTemp(
      name: name,
      tag: tag,
      onStart:  (int sizeByByte, String digest) {
        PullStartDto pullStartDto = PullStartDto(pullInfoDto: pullInfoDto, sizeByByte: sizeByByte, digest: digest);
        _pushData(streamController, EventType.START, jsonEncode(pullStartDto.toJson()));
      },
      onDownload:  (int percent) {
        PullDownloadDto pullDownloadDto = PullDownloadDto(pullInfoDto: pullInfoDto, percent: percent);
        _pushData(streamController, EventType.DATA, jsonEncode(pullDownloadDto.toJson()));
      },
      onDone:  () {
        _pushData(streamController, EventType.DONE, jsonEncode(pullInfoDto.toJson()));
        streamController.close();
      }
    );
    await serverService.afterPullToTemp(otsFileTempPath);

    return Response.ok(streamController.stream, headers: STREAM_HEADERS, context: {'shelf.io.buffer_output': false});
  }

  /// POST /servers/{serverId}/push
  Future<Response> pushServer(Request request, String serverId) async {
    String otsFilePath = await serverService.beforePush(serverId);
    StreamController<List<int>> streamController = StreamController<List<int>>();
    await manageService.push(
      otsFilePath: otsFilePath,
      onStart: (int sizeByByte, String digest) {
        PushStartDto pushStartDto = PushStartDto(serverId: serverId, sizeByByte: sizeByByte, digest: digest);
        _pushData(streamController, EventType.START, jsonEncode(pushStartDto.toJson()));
      },
      onUpload: (int percent) {
        PushUploadDto pushUploadDto = PushUploadDto(serverId: serverId, percent: percent);
        _pushData(streamController, EventType.DATA, jsonEncode(pushUploadDto.toJson()));
      },
      onDone: () {
        ServerIdDto serverIdDto = ServerIdDto(id: serverId);
        _pushData(streamController, EventType.DONE, jsonEncode(serverIdDto));
        streamController.close();
      }
    );
    await serverService.afterPush(otsFilePath);

    return Response.ok(streamController.stream, headers: STREAM_HEADERS, context: {'shelf.io.buffer_output': false});
  }

  /// GET /servers/{serverId}/export
  Future<Response> exportServer(Request request, String serverId) async {
    final payload = await request.readAsString();
    Map<String, dynamic> data = jsonDecode(payload);
    PathDto pathDto = PathDto.fromJson(data);
    await serverService.export(serverId, pathDto.path);
    ServerIdDto serverIdDto = ServerIdDto(id: serverId);
    return Response.ok(jsonEncode(serverIdDto.toJson()), headers: JSON_HEADERS);
  }

  /// POST /servers/import
  Future<Response> importServer(Request request) async {
    final payload = await request.readAsString();
    Map<String, dynamic> data = jsonDecode(payload);
    PathDto pathDto = PathDto.fromJson(data);
    ServerModel serverModel = await serverService.import(pathDto.path);
    OpenToolServerDto serverDto = OpenToolServerDto.fromModel(serverModel);
    return Response.ok(jsonEncode(serverDto.toJson()), headers: JSON_HEADERS);
  }

  /// POST /servers/{serverId}/alias?alias=<target_alias>
  Future<Response> setAlias(Request request, String serverId) async {
    final query = request.url.queryParameters;
    final alias = query['alias'];
    if (alias == null) throw ArgumentError("alias is null");
    await serverService.setAlias(serverId, alias);
    ServerModel serverModel = await serverService.get(serverId);
    OpenToolServerDto serverDto = OpenToolServerDto.fromModel(serverModel);
    return Response.ok(jsonEncode(serverDto.toJson()), headers: JSON_HEADERS);
  }

  void _pushData(StreamController<List<int>> streamController, String eventType, String dataString) {
    String data = "event:$eventType\ndata:$dataString\n\n";
    streamController.sink.add(utf8.encode(data));
  }

}