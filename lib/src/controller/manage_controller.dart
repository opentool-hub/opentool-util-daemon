import 'dart:async';
import 'dart:convert';
import 'package:opentool_daemon/src/utils/logger.dart';
import 'package:shelf/shelf.dart';
import '../service/manage_service.dart';
import '../service/model.dart';
import '../service/exception.dart';
import '../constants.dart';
import 'dto.dart';

class ManageController {
  ManageService manageService;
  static const _sudoHeader = 'x-opentool-sudo-token';

  ManageController(this.manageService);

  /// GET /version
  Future<Response> getVersion(Request request) async {
    VersionModel versionModel = await manageService.getVersion();
    VersionDto versionDto = VersionDto.fromModel(versionModel);
    logger.log(
      LogModule.http,
      "getVersion",
      detail: jsonEncode(versionDto.toJson()),
    );
    return Response.ok(jsonEncode(versionDto.toJson()), headers: JSON_HEADERS);
  }

  /// POST /opentool-hub/login
  Future<Response> login(Request request) async {
    final payload = await request.readAsString();
    final data = jsonDecode(payload);
    LoginInfoDto loginInfoDto = LoginInfoDto.fromJson(data);
    await manageService.login(loginInfoDto.toModel());
    LoginResultDto loginResultDto = LoginResultDto(
      registry: loginInfoDto.registry,
      username: loginInfoDto.username,
    );
    logger.log(
      LogModule.http,
      "login",
      detail: jsonEncode(loginResultDto.toJson()),
    );
    return Response.ok(
      jsonEncode(loginResultDto.toJson()),
      headers: JSON_HEADERS,
    );
  }

  /// GET /opentool-hub/user
  Future<Response> getUserInfo(Request request) async {
    UserInfo userInfo = await manageService.getUserInfo();
    UserInfoDto userInfoDto = UserInfoDto.fromModel(userInfo);
    logger.log(
      LogModule.http,
      "getUserInfo",
      detail: jsonEncode(userInfoDto.toJson()),
    );
    return Response.ok(jsonEncode(userInfoDto.toJson()), headers: JSON_HEADERS);
  }

  /// POST /opentool-hub/logout
  Future<Response> logout(Request request) async {
    UserInfo userInfo = await manageService.logout();
    UserInfoDto userInfoDto = UserInfoDto.fromModel(userInfo);
    logger.log(
      LogModule.http,
      "logout",
      detail: jsonEncode(userInfoDto.toJson()),
    );
    return Response.ok(jsonEncode(userInfoDto.toJson()), headers: JSON_HEADERS);
  }

  /// POST /apiKey
  Future<Response> createApiKey(Request request) async {
    final unauthorized = await _requireSudo(request);
    if (unauthorized != null) return unauthorized;
    String? name;
    final payload = await request.readAsString();
    if (payload.trim().isNotEmpty) {
      try {
        final dto = CreateApiKeyDto.fromJson(jsonDecode(payload));
        name = dto.name;
      } catch (_) {
        return Response.badRequest(
          body: jsonEncode({'error': 'invalid request body'}),
          headers: JSON_HEADERS,
        );
      }
    }
    final apiKey = await manageService.createApiKey(name: name);
    final dto = ApiKeyDto.fromModel(apiKey);
    logger.log(
      LogModule.http,
      'createApiKey',
      detail: jsonEncode(dto.toJson()),
    );
    return Response.ok(jsonEncode(dto.toJson()), headers: JSON_HEADERS);
  }

  /// GET /apiKeys
  Future<Response> listApiKeys(Request request) async {
    final unauthorized = await _requireSudo(request);
    if (unauthorized != null) return unauthorized;
    final keys = await manageService.listApiKeys();
    final payload = keys.map((e) => ApiKeyDto.fromModel(e).toJson()).toList();
    logger.log(
      LogModule.http,
      'listApiKeys.output',
      detail: jsonEncode(payload),
    );
    return Response.ok(jsonEncode(payload), headers: JSON_HEADERS);
  }

  /// DELETE /apiKey/<apiKey>
  Future<Response> deleteApiKey(Request request, String apiKey) async {
    final unauthorized = await _requireSudo(request);
    if (unauthorized != null) return unauthorized;
    await manageService.deleteApiKey(apiKey);
    logger.log(LogModule.http, 'deleteApiKey.output', detail: apiKey);
    return Response.ok(jsonEncode({'apiKey': apiKey}), headers: JSON_HEADERS);
  }

  Future<Response?> _requireSudo(Request request) async {
    final token = request.headers[_sudoHeader];
    try {
      await manageService.ensureSudoToken(token);
      return null;
    } on SudoAuthorizationException catch (error) {
      return Response.forbidden(
        jsonEncode({'error': error.message}),
        headers: JSON_HEADERS,
      );
    }
  }
}
