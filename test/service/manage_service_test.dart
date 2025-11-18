import 'dart:convert';
import 'dart:io';
import 'package:opentool_daemon/src/constants.dart';
import 'package:opentool_daemon/src/service/config.dart';
import 'package:opentool_daemon/src/service/exception.dart';
import 'package:opentool_daemon/src/service/manage_service.dart';
import 'package:test/test.dart';

import '../test_doubles.dart';

void main() {
  group('ManageService api keys', () {
    late Directory tempDir;
    late ManageService service;
    late InMemoryApiKeyStorage apiKeyStorage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('manage_service');
      apiKeyStorage = InMemoryApiKeyStorage();
      service = ManageService(
        'test',
        dataDir: tempDir.path,
        apiKeyStorage: apiKeyStorage,
      );
      service.currConfig = OpenToolConfig();
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('create/list/delete api keys persists via storage', () async {
      final created = await service.createApiKey(name: 'custom');
      expect(created.name, equals('custom'));

      final keys = await service.listApiKeys();
      expect(keys, hasLength(1));
      expect(keys.single.apiKey, equals(created.apiKey));
      final stored = await apiKeyStorage.list();
      expect(stored, hasLength(1));
      expect(stored.single.apiKey, equals(created.apiKey));
      expect(stored.single.name, equals('custom'));

      await service.deleteApiKey(created.apiKey);
      expect(await service.listApiKeys(), isEmpty);
      expect(await apiKeyStorage.list(), isEmpty);
    });

    test('createApiKey falls back to default name when omitted', () async {
      final created = await service.createApiKey();
      expect(created.name, equals('api-key'));
    });

    test('ensureSudoToken validates token file and deletes it', () async {
      final path = _sudoTokenFilePath(tempDir.path);
      await _writeTokenFile(path, 'abc', 60);

      await service.ensureSudoToken('abc');
      expect(await File(path).exists(), isFalse);
    });

    test('ensureSudoToken rejects expired or mismatched token', () async {
      final path = _sudoTokenFilePath(tempDir.path);
      await _writeTokenFile(path, 'expected', 0);
      await Future.delayed(const Duration(milliseconds: 5));

      await expectLater(
        service.ensureSudoToken('expected'),
        throwsA(isA<SudoAuthorizationException>()),
      );

      await _writeTokenFile(path, 'expected', 120);
      await expectLater(
        service.ensureSudoToken('wrong'),
        throwsA(isA<SudoAuthorizationException>()),
      );
    });
  });
}

String _sudoTokenFilePath(String baseDir) =>
    '$baseDir${Platform.pathSeparator}$SUDO_TOKEN_FILE_NAME';

Future<void> _writeTokenFile(String path, String token, int timeout) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    jsonEncode({'tempToken': token, 'timeoutInSecond': timeout}),
  );
}
