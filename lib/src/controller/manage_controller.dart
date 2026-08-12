import 'dart:async';
import 'dart:convert';
import 'package:logging/logging.dart';
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
      detail:
          "apiVersion=${versionDto.apiVersion}, capabilities=${versionDto.capabilities.length}",
      level: Level.FINE,
    );
    return Response.ok(jsonEncode(versionDto.toJson()), headers: JSON_HEADERS);
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
      detail: 'name=${dto.name}',
      level: Level.FINE,
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
      detail: 'count=${payload.length}',
      level: Level.FINE,
    );
    return Response.ok(jsonEncode(payload), headers: JSON_HEADERS);
  }

  /// DELETE /apiKey/<apiKey>
  Future<Response> deleteApiKey(Request request, String apiKey) async {
    final unauthorized = await _requireSudo(request);
    if (unauthorized != null) return unauthorized;
    await manageService.deleteApiKey(apiKey);
    logger.log(
      LogModule.http,
      'deleteApiKey.output',
      detail: 'deleted=true',
      level: Level.FINE,
    );
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
