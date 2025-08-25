import 'dart:convert';
import 'package:opentool_daemon/src/utils/utils.dart';
import 'package:opentool_dart/opentool_dart.dart';
import 'package:shelf/shelf.dart';
import '../service/model.dart';
import '../utils/logger.dart';
import 'dto.dart';
import '../service/manage_service.dart';
import '../service/runner_service.dart';

const Map<String, String> jsonHeaders = {'Content-Type': 'application/json'};

class Controller {
  ManageService manageService;
  RunnerService runnerService;
  final String version;

  Controller({required this.manageService, required this.runnerService, required this.version});

  Future<Response> getVersion(Request request) async {
    final versionObj = VersionDto(version: version);
    logger.log(LogModule.http, "getVersionResult", detail: jsonEncode(versionObj.toJson()));
    return Response.ok(jsonEncode(versionObj.toJson()), headers: jsonHeaders,);
  }

  Future<Response> list(Request request) async {
    List<OpenToolServerModel> serverModelList= await manageService.list();
    List<OpenToolServerDto> serverDtoList = serverModelList.map((model) => OpenToolServerDto.fromModel(model)).toList();
    logger.log(LogModule.http, "listResult", detail: jsonEncode(serverDtoList));
    return Response.ok(
      jsonEncode(serverDtoList),
      headers: jsonHeaders,
    );
  }

  Future<Response> register(Request request) async {
    final payload = await request.readAsString();
    final data = jsonDecode(payload);

    try {
      RegisterInfo serverInfo = RegisterInfo.fromJson(data);
      logger.log(LogModule.http, "register", detail: jsonEncode(serverInfo.toJson()));
      String url = "http://${serverInfo.host}:${serverInfo.port}${serverInfo.prefix}";
      String serverId = generateFixedIdByMd5(url);
      OpenToolServerModel serverModel = OpenToolServerModel(
        id: serverId,
        name: serverId,
        file: serverInfo.file,
        host: serverInfo.host,
        port: serverInfo.port,
        prefix: serverInfo.prefix,
        apiKeys: serverInfo.apiKeys,
        pid: serverInfo.pid,
      );
      await manageService.add(serverModel);

      final result = RegisterResult(id: serverId, error: null,);
      logger.log(LogModule.http, "registerResult", detail: jsonEncode(result.toJson()));

      return Response.ok(jsonEncode(result.toJson()), headers: jsonHeaders,);
    } on FormatException catch (_) {
      return Response.badRequest(body: data);
    } catch(e) {
      return Response.internalServerError();
    }
  }

  Future<Response> rename(Request request) async {
    final payload = await request.readAsString();
    final data = jsonDecode(payload);

    try {
      RenameDto renameDto = RenameDto.fromJson(data);
      logger.log(LogModule.http, "rename", detail: jsonEncode(renameDto.toJson()));
      await manageService.rename(renameDto.id, renameDto.name);
      StatusDto statusDto = StatusDto(id: renameDto.id, status: StatusType.RENAME_SUCCESS);
      logger.log(LogModule.http, "renameResult", detail: jsonEncode(statusDto.toJson()));
      return Response.ok(jsonEncode(statusDto.toJson()), headers: jsonHeaders,);
    } on FormatException catch (_) {
      return Response.badRequest(body: data);
    } catch(e) {
      return Response.internalServerError();
    }
  }

  Future<Response> call(Request request) async {
    final payload = await request.readAsString();
    final data = jsonDecode(payload);

    try {
      ServerFunctionCallDto functionCallDto = ServerFunctionCallDto.fromJson(data);
      logger.log(LogModule.http, "call", detail: jsonEncode(functionCallDto.toJson()));
      ToolReturn toolReturn = await runnerService.call(functionCallDto.id, functionCallDto.functionCall.toModel());
      logger.log(LogModule.http, "callResult", detail: jsonEncode(toolReturn.toJson()));
      return Response.ok(jsonEncode(ToolReturnDto.fromModel(toolReturn).toJson()), headers: jsonHeaders,);
    } on OpenToolServerNoAccessException catch(e) {
      return Response.ok(jsonEncode(e.toJson()), headers: jsonHeaders,);
    } on FormatException catch (_) {
      return Response.badRequest(body: data);
    } catch(e) {
      return Response.internalServerError();
    }
  }

  Future<Response> load(Request request) async {
    final payload = await request.readAsString();
    final data = jsonDecode(payload);
    try {
      ServerIdDto serverIdDto = ServerIdDto.fromJson(data);
      logger.log(LogModule.http, "load", detail: jsonEncode(serverIdDto.toJson()));
      OpenTool? openTool = await runnerService.load(serverIdDto.id);
      Map<String, dynamic> result = openTool != null ? openTool.toJson():{};
      logger.log(LogModule.http, "loadResult", detail: jsonEncode(result));
      return Response.ok(jsonEncode(result), headers: jsonHeaders,);
    } on FormatException catch (_) {
      return Response.badRequest(body: data);
    } catch(e) {
      return Response.internalServerError();
    }
  }

  Future<Response> stop(Request request) async {
    final payload = await request.readAsString();
    final data = jsonDecode(payload);

    try{
      ServerIdDto serverIdDto = ServerIdDto.fromJson(data);
      logger.log(LogModule.http, "stop", detail: jsonEncode(serverIdDto.toJson()));
      String serverId = serverIdDto.id;
      await runnerService.stop(serverId);
      StatusDto statusDto = StatusDto(id: serverId, status: StatusType.STOP_SUCCESS);
      logger.log(LogModule.http, "stopResult", detail: jsonEncode(statusDto.toJson()));
      return Response.ok(jsonEncode(statusDto.toJson()), headers: jsonHeaders);
    } on FormatException catch (_) {
      return Response.badRequest(body: data);
    } catch(e) {
      return Response.internalServerError();
    }
  }

  Future<Response> remove(Request request) async {
    final payload = await request.readAsString();
    final data = jsonDecode(payload);

    try{
      ServerIdDto serverIdDto = ServerIdDto.fromJson(data);
      logger.log(LogModule.http, "remove", detail: jsonEncode(serverIdDto.toJson()));
      String serverId = serverIdDto.id;
      await manageService.remove(serverId);
      StatusDto statusDto = StatusDto(id: serverId, status: StatusType.REMOVE_SUCCESS);
      logger.log(LogModule.http, "removeResult", detail: jsonEncode(statusDto.toJson()));
      return Response.ok(jsonEncode(statusDto.toJson()), headers: jsonHeaders);
    } on FormatException catch (_) {
      return Response.badRequest(body: data);
    } catch(e) {
      return Response.internalServerError();
    }
  }
}
