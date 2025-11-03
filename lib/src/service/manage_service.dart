import 'dart:io';
import '../constants.dart';
import '../hub/dto.dart';
import '../hub/hub_client.dart';
import '../utils/crypto_util.dart';
import '../utils/json_file_util.dart';
import 'config.dart';
import 'exception.dart';
import 'model.dart';

class ManageService {
  String version;
  HubClient? hubClient;
  late OpenToolConfig currConfig;

  ManageService(this.version);

  Future<void> init() async {
    String configFilePath = "$OPENTOOL_PATH${Platform.pathSeparator}$SYSTEM_CONFIG_FILE_NAME";
    Map<String, dynamic> configJson = await JsonFileUtil.readFromFile(configFilePath);
    currConfig = OpenToolConfig.fromJson(configJson);
  }

  Future<VersionModel> getVersion() async {
    return VersionModel(
      name: OPENTOOL_DAEMON_NAME,
      version: version,
    );
  }

  Future<void> login(LoginInfoModel loginInfoModel) async {

    hubClient = HubClient(loginInfoModel.registry);
    if(hubClient ==  null) throw LoginFailedException(loginInfoModel.username);

    LoginResult? loginResult = await hubClient!.login(loginInfoModel.username, loginInfoModel.password);
    if(loginResult == null) throw LoginFailedException(loginInfoModel.username);

    currConfig.registry = loginInfoModel.registry;
    currConfig.username = loginInfoModel.username;
    HubAuth currAuth = HubAuth(repo: loginResult.repo, token: loginResult.token);
    currConfig.auth = currAuth;

    await JsonFileUtil.saveToFile(currConfig.toJson(), OPENTOOL_PATH, SYSTEM_CONFIG_FILE_NAME);
  }

  Future<String> pullToTemp({required String name, required String tag, required void Function(int sizeByByte, String digest) onStart, required void Function(int percent) onDownload, required void Function() onDone}) async {
    /// 1. download to temp folder
    if(currConfig.auth == null || hubClient == null) throw LoginRequiredException();
    final tmpDir = await Directory.systemTemp.createTemp('opentool_server_');
    String repo = currConfig.auth!.repo;
    Manifest manifest = await hubClient!.pullManifest(repo, name, tag);
    String otsFileTempPath = "${tmpDir.path}${Platform.pathSeparator}${manifest.fileName}";
    onStart(manifest.config.size, manifest.config.digest);
    await hubClient!.pullBlob(repo, manifest.config.digest, otsFileTempPath, onProgress: (int download, int total) {
      onDownload((download / total * 100).round());
    });
    onDone();

    return otsFileTempPath;
  }

  Future<void> push({required String otsFilePath, String? tag, required void Function(int sizeByByte, String digest) onStart, required void Function(int percent) onUpload, required void Function() onDone}) async {
    /// 1. Read zip file
    final file = File(otsFilePath);
    final bytes = await file.readAsBytes();

    /// 2. Calculate sha256
    final digest = CryptoUtil.sha256Digest(bytes);
    final size = bytes.length;
    onStart(size, digest);

    /// 3. Upload blob
    if(currConfig.auth == null || hubClient == null) throw LoginRequiredException();
    final repo = currConfig.auth!.repo;
    await hubClient!.uploadBlob(repo, digest, bytes, onProgress: (int sent, int total) {
      onUpload((sent / total * 100).round());
    });

    /// 4. Submit manifest
    final manifest = Manifest(
      fileName: file.path.split(Platform.pathSeparator).last,
      config: ManifestConfig(digest: digest, size: size),
    );

    await hubClient!.pushManifest(repo, tag??NULL_TAG, manifest);

    onDone();
  }

  Future<UserInfo> getUserInfo() async {
    return UserInfo(registry: currConfig.registry, username: currConfig.username);
  }

  Future<UserInfo> logout() async {
    String configFilePath = "$OPENTOOL_PATH${Platform.pathSeparator}$SYSTEM_CONFIG_FILE_NAME";
    Map<String, dynamic> configJson = await JsonFileUtil.readFromFile(configFilePath);
    OpenToolConfig config = OpenToolConfig.fromJson(configJson);
    UserInfo userInfo = UserInfo(registry: currConfig.registry, username: currConfig.username);

    config = OpenToolConfig(registry: null, username: null, auth: null);

    await JsonFileUtil.saveToFile(config.toJson(), OPENTOOL_PATH, SYSTEM_CONFIG_FILE_NAME);

    return userInfo;
  }
}