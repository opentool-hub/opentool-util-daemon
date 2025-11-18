import 'dart:io';
import 'package:opentool_daemon/src/utils/logger.dart';
import 'package:opentool_dart/opentool_dart.dart';

import '../constants.dart';
import '../hub/dto.dart';
import '../hub/hub_client.dart';
import '../storage/dao.dart';
import '../storage/hive_storage.dart';
import '../storage/storage.dart';
import '../utils/crypto_util.dart';
import '../utils/json_file_util.dart';
import '../utils/sudo_util.dart';
import 'config.dart';
import 'exception.dart';
import 'model.dart';

class ManageService {
  String version;
  HubClient? hubClient;
  late OpenToolConfig currConfig;
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
           HiveApiKeyStorage(dataDir: dataDir ?? OPENTOOL_PATH) {
    currConfig = OpenToolConfig();
  }

  String get _configFilePath =>
      '$_dataDir${Platform.pathSeparator}$SYSTEM_CONFIG_FILE_NAME';
  String get _sudoTokenFilePath =>
      '$_dataDir${Platform.pathSeparator}$SUDO_TOKEN_FILE_NAME';

  Future<void> init() async {
    Map<String, dynamic> configJson = await JsonFileUtil.readFromFile(
      _configFilePath,
    );
    currConfig = OpenToolConfig.fromJson(configJson);
  }

  Future<VersionModel> getVersion() async {
    return VersionModel(name: OPENTOOL_DAEMON_NAME, version: version);
  }

  Future<void> login(LoginInfoModel loginInfoModel) async {
    logger.log(
      LogModule.manage,
      "login.input",
      detail:
          "registry: ${loginInfoModel.registry}, username: ${loginInfoModel.username}",
    );
    hubClient = HubClient(loginInfoModel.registry);
    if (hubClient == null) throw LoginFailedException(loginInfoModel.username);

    LoginResult? loginResult = await hubClient!.login(
      loginInfoModel.username,
      loginInfoModel.password,
    );
    if (loginResult == null)
      throw LoginFailedException(loginInfoModel.username);

    currConfig.registry = loginInfoModel.registry;
    currConfig.username = loginInfoModel.username;
    HubAuth currAuth = HubAuth(
      repo: loginResult.repo,
      token: loginResult.token,
    );
    currConfig.auth = currAuth;

    await JsonFileUtil.saveToFile(
      currConfig.toJson(),
      _dataDir,
      SYSTEM_CONFIG_FILE_NAME,
    );
    logger.log(
      LogModule.manage,
      "login.result",
      detail: "registry: ${loginResult}",
    );
  }

  Future<String> pullToTemp({
    required String name,
    required String tag,
    required void Function(int sizeByByte, String digest) onStart,
    required void Function(int percent) onDownload,
    required void Function() onDone,
  }) async {
    /// 1. download to temp folder
    if (currConfig.auth == null || hubClient == null)
      throw LoginRequiredException();
    final tmpDir = await Directory.systemTemp.createTemp('opentool_server_');
    String repo = currConfig.auth!.repo;
    Manifest manifest = await hubClient!.pullManifest(repo, name, tag);
    String otsFileTempPath =
        "${tmpDir.path}${Platform.pathSeparator}${manifest.fileName}";
    onStart(manifest.config.size, manifest.config.digest);
    await hubClient!.pullBlob(
      repo,
      manifest.config.digest,
      otsFileTempPath,
      onProgress: (int download, int total) {
        onDownload((download / total * 100).round());
      },
    );
    onDone();

    return otsFileTempPath;
  }

  Future<void> push({
    required String otsFilePath,
    String? tag,
    required void Function(int sizeByByte, String digest) onStart,
    required void Function(int percent) onUpload,
    required void Function() onDone,
  }) async {
    /// 1. Read zip file
    final file = File(otsFilePath);
    final bytes = await file.readAsBytes();

    /// 2. Calculate sha256
    final digest = CryptoUtil.sha256Digest(bytes);
    final size = bytes.length;
    onStart(size, digest);

    /// 3. Upload blob
    if (currConfig.auth == null || hubClient == null)
      throw LoginRequiredException();
    final repo = currConfig.auth!.repo;
    await hubClient!.uploadBlob(
      repo,
      digest,
      bytes,
      onProgress: (int sent, int total) {
        onUpload((sent / total * 100).round());
      },
    );

    /// 4. Submit manifest
    final manifest = Manifest(
      fileName: file.path.split(Platform.pathSeparator).last,
      config: ManifestConfig(digest: digest, size: size),
    );

    await hubClient!.pushManifest(repo, tag ?? NULL_TAG, manifest);

    onDone();
  }

  Future<UserInfo> getUserInfo() async {
    return UserInfo(
      registry: currConfig.registry,
      username: currConfig.username,
    );
  }

  Future<UserInfo> logout() async {
    Map<String, dynamic> configJson = await JsonFileUtil.readFromFile(
      _configFilePath,
    );
    OpenToolConfig config = OpenToolConfig.fromJson(configJson);
    UserInfo userInfo = UserInfo(
      registry: currConfig.registry,
      username: currConfig.username,
    );

    config = OpenToolConfig(registry: null, username: null, auth: null);

    await JsonFileUtil.saveToFile(
      config.toJson(),
      _dataDir,
      SYSTEM_CONFIG_FILE_NAME,
    );

    return userInfo;
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
