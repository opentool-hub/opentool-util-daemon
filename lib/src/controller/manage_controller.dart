import 'dart:async';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import '../service/manage_service.dart';
import '../service/model.dart';
import '../constants.dart';
import 'dto.dart';

class ManageController {
  ManageService manageService;

  ManageController(this.manageService);

  /// GET /version
  Future<Response> getVersion(Request request) async {
    VersionModel versionModel = await manageService.getVersion();
    VersionDto versionDto = VersionDto.fromModel(versionModel);
    return Response.ok(jsonEncode(versionDto.toJson()), headers: JSON_HEADERS,);
  }

  /// POST /opentool-hub/login
  Future<Response> login(Request request) async {
    final payload = await request.readAsString();
    final data = jsonDecode(payload);
    LoginInfoDto loginInfoDto = LoginInfoDto.fromJson(data);
    await manageService.login(loginInfoDto.toModel());
    LoginResultDto loginResultDto = LoginResultDto(registry: loginInfoDto.registry, username: loginInfoDto.username);
    return Response.ok(jsonEncode(loginResultDto.toJson()), headers: JSON_HEADERS);
  }

  /// GET /opentool-hub/user
  Future<Response> getUserInfo(Request request) async {
    UserInfo userInfo = await manageService.getUserInfo();
    return Response.ok(jsonEncode(UserInfoDto.fromModel(userInfo).toJson()), headers: JSON_HEADERS);
  }

  /// POST /opentool-hub/logout
  Future<Response> logout(Request request) async {
    UserInfo userInfo = await manageService.logout();
    return Response.ok(jsonEncode(UserInfoDto.fromModel(userInfo).toJson()), headers: JSON_HEADERS);
  }
}