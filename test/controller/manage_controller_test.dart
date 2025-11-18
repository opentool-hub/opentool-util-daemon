import 'dart:convert';
import 'package:opentool_daemon/src/controller/dto.dart';
import 'package:opentool_daemon/src/controller/manage_controller.dart';
import 'package:opentool_daemon/src/service/exception.dart';
import 'package:opentool_daemon/src/service/manage_service.dart';
import 'package:opentool_daemon/src/service/model.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('ManageController', () {
    late FakeManageService manageService;
    late ManageController controller;

    setUp(() {
      manageService = FakeManageService(
        versionModel: VersionModel(name: 'opentool-daemon', version: '1.2.3'),
        userInfo: UserInfo(registry: 'hub.local', username: 'agent'),
      );
      controller = ManageController(manageService);
    });

    test('returns version payload that matches client expectations', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/opentool-daemon/version'),
      );
      final response = await controller.getVersion(request);

      expect(response.statusCode, equals(200));
      final dto = VersionDto.fromJson(
        jsonDecode(await response.readAsString()) as Map<String, dynamic>,
      );
      expect(dto.version, equals('1.2.3'));
      expect(dto.name, equals('opentool-daemon'));
    });

    test(
      'accepts login credentials and mirrors them in the response DTO',
      () async {
        final loginDto = LoginInfoDto(
          username: 'agent',
          password: 'secret',
          registry: 'hub.local',
        );
        final request = Request(
          'POST',
          Uri.parse('http://localhost/opentool-daemon/opentool-hub/login'),
          body: jsonEncode(loginDto.toJson()),
        );

        final response = await controller.login(request);

        expect(manageService.lastLogin!.username, equals('agent'));
        expect(manageService.lastLogin!.password, equals('secret'));

        final dto = LoginResultDto.fromJson(
          jsonDecode(await response.readAsString()) as Map<String, dynamic>,
        );
        expect(dto.registry, equals('hub.local'));
        expect(dto.username, equals('agent'));
      },
    );

    test('exposes user info and clears state on logout', () async {
      final getUserRequest = Request(
        'GET',
        Uri.parse('http://localhost/opentool-daemon/opentool-hub/user'),
      );
      final response = await controller.getUserInfo(getUserRequest);
      final dto = UserInfoDto.fromJson(
        jsonDecode(await response.readAsString()) as Map<String, dynamic>,
      );

      expect(dto.username, equals('agent'));

      final logoutRequest = Request(
        'POST',
        Uri.parse('http://localhost/opentool-daemon/opentool-hub/logout'),
      );
      final logoutResponse = await controller.logout(logoutRequest);
      final logoutDto = UserInfoDto.fromJson(
        jsonDecode(await logoutResponse.readAsString()) as Map<String, dynamic>,
      );
      expect(logoutDto.registry, equals('hub.local'));
      expect(manageService.userInfo.username, isNull);
    });

    test(
      'createApiKey forwards optional name and enforces sudo token',
      () async {
        manageService.nextApiKey = ApiKeyModel(
          id: 'id-1',
          name: 'webhook',
          apiKey: 'secret',
          createdAt: DateTime.utc(2024, 1, 1),
        );
        final request = Request(
          'POST',
          Uri.parse('http://localhost/opentool-daemon/apiKey'),
          headers: {'x-opentool-sudo-token': 'sudo'},
          body: jsonEncode({'name': 'webhook'}),
        );

        final response = await controller.createApiKey(request);

        expect(response.statusCode, equals(200));
        final payload =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(payload['name'], equals('webhook'));
        expect(manageService.lastCreateApiKeyName, equals('webhook'));
        expect(manageService.lastSudoToken, equals('sudo'));
      },
    );
  });
}

class FakeManageService extends ManageService {
  VersionModel versionModel;
  UserInfo userInfo;
  LoginInfoModel? lastLogin;
  ApiKeyModel? nextApiKey;
  String? lastCreateApiKeyName;
  String? lastSudoToken;

  FakeManageService({required this.versionModel, required this.userInfo})
    : super('test-version');

  @override
  Future<VersionModel> getVersion() async => versionModel;

  @override
  Future<void> login(LoginInfoModel loginInfoModel) async {
    lastLogin = loginInfoModel;
  }

  @override
  Future<UserInfo> getUserInfo() async => userInfo;

  @override
  Future<UserInfo> logout() async {
    final previous = UserInfo(
      registry: userInfo.registry,
      username: userInfo.username,
    );
    userInfo = UserInfo();
    return previous;
  }

  @override
  Future<ApiKeyModel> createApiKey({String? name}) async {
    lastCreateApiKeyName = name;
    return nextApiKey ??
        ApiKeyModel(
          id: 'generated',
          name: name ?? 'api-key',
          apiKey: 'generated-secret',
          createdAt: DateTime.now().toUtc(),
        );
  }

  @override
  Future<void> ensureSudoToken(String? providedToken) async {
    lastSudoToken = providedToken;
    if (providedToken == null) {
      throw SudoAuthorizationException('missing');
    }
  }
}
