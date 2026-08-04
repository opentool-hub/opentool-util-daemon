import 'dart:io';
import 'package:unique_id_dart/unique_id_dart.dart';
import 'package:opentool_daemon/opentool_daemon_utils.dart';
import '../constants.dart';
import '../storage/dao.dart';
import '../storage/hive_storage.dart';
import '../storage/storage.dart';
import 'exception.dart';
import 'model.dart';

class ManageService {
  String version;
  final String _dataDir;
  final SudoUtil _sudoUtil;
  final Storage<ApiKeyDao> _apiKeyStorage;

  ManageService(
    this.version, {
    String? dataDir,
    SudoUtil? sudoUtil,
    Storage<ApiKeyDao>? apiKeyStorage,
  }) : _dataDir = dataDir ?? OPENTOOL_PATH,
       _sudoUtil = sudoUtil ?? SudoUtil(),
       _apiKeyStorage =
           apiKeyStorage ??
           HiveApiKeyStorage(dataDir: dataDir ?? OPENTOOL_PATH) {}

  String get _sudoTokenFilePath =>
      '$_dataDir${Platform.pathSeparator}$SUDO_TOKEN_FILE_NAME';

  Future<VersionModel> getVersion() async {
    return VersionModel(name: OPENTOOL_DAEMON_NAME, version: version);
  }

  Future<void> ensureSudoToken(String? providedToken) async {
    if (providedToken == null || providedToken.isEmpty) {
      throw SudoAuthorizationException('Missing sudo token header');
    }
    final file = File(_sudoTokenFilePath);
    if (!await file.exists()) {
      throw SudoAuthorizationException('sudo token file not found');
    }
    SudoTokenPayload payload;
    try {
      payload = await _sudoUtil.readToken(_sudoTokenFilePath);
    } catch (error) {
      await _safeDelete(file);
      throw SudoAuthorizationException('sudo token corrupted');
    }
    final stat = await file.stat();
    final expiry = stat.modified.add(
      Duration(seconds: payload.timeoutInSecond),
    );
    if (DateTime.now().isAfter(expiry)) {
      await _safeDelete(file);
      throw SudoAuthorizationException('sudo token expired');
    }
    if (payload.tempToken != providedToken) {
      await _safeDelete(file);
      throw SudoAuthorizationException('sudo token mismatch');
    }
    await _safeDelete(file);
  }

  Future<void> _safeDelete(File file) async {
    if (!await file.exists()) return;
    try {
      await file.delete();
    } catch (_) {}
  }

  Future<ApiKeyModel> createApiKey({String? name}) async {
    final resolvedName = (name == null || name.trim().isEmpty)
        ? 'api-key'
        : name;
    final model = ApiKeyModel(
      id: uniqueId(),
      name: resolvedName,
      apiKey: uniqueId(shorter: false),
      createdAt: DateTime.now().toUtc(),
    );
    await _apiKeyStorage.add(model.toDao());
    return model;
  }

  Future<List<ApiKeyModel>> listApiKeys() async {
    final daos = await _apiKeyStorage.list();
    return daos.map(ApiKeyModel.fromDao).toList();
  }

  Future<void> deleteApiKey(String apiKey) async {
    final daoList = await _apiKeyStorage.list();
    ApiKeyDao? target;
    for (final dao in daoList) {
      if (dao.apiKey == apiKey) {
        target = dao;
        break;
      }
    }
    if (target == null) {
      throw ApiKeyNotFoundException(apiKey);
    }
    await _apiKeyStorage.remove(target.id);
  }

  Future<void> ensureDaemonApiKey(String? providedKey) async {
    if (providedKey == null || providedKey.isEmpty) {
      throw ApiKeyNotFoundException('missing');
    }
    final daoList = await _apiKeyStorage.list();
    for (final dao in daoList) {
      if (dao.apiKey == providedKey) {
        return;
      }
    }
    throw ApiKeyNotFoundException(providedKey);
  }
}
