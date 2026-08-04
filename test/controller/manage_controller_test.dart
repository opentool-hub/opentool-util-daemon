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
  ApiKeyModel? nextApiKey;
  String? lastCreateApiKeyName;
  String? lastSudoToken;

  FakeManageService({required this.versionModel}) : super('test-version');

  @override
  Future<VersionModel> getVersion() async => versionModel;

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
