import 'dart:io';
import 'package:opentool_dart/opentool_dart.dart';
import '../constants.dart';
import '../storage/cache_storage.dart';
import '../storage/dao.dart';
import '../storage/hive_storage.dart';
import '../utils/command_util.dart';
import '../utils/directory_util.dart';
import '../utils/json_file_util.dart';
import '../utils/system_util.dart';
import '../utils/zip_util.dart';
import 'config.dart';
import 'exception.dart';
import 'model.dart';

class ServerService {
  late CacheServerStorage _cacheServerStorage;
  late HiveInternalServerStorage _internalServerStorage;

  ServerService(HiveServerStorage hiveTag, HiveInternalServerStorage hiveServer) {
    _cacheServerStorage = CacheServerStorage(hiveTag);
    _internalServerStorage = hiveServer;
  }

  Future<List<ServerModel>> list() async {
    List<ServerDao> daoList = await _cacheServerStorage.list();
    return daoList.map((dao) => ServerModel.fromDao(dao)).toList();
  }

  Future<ServerModel> get(String serverId) async {
    ServerDao? serverDao = await _cacheServerStorage.get(serverId);
    if(serverDao == null) throw ServerNotFoundException(serverId);
    return ServerModel.fromDao(serverDao);
  }

  Future<void> buildServer(String path, String name, String? tag, void Function(String command, String output) onRun, void Function() onDone ) async {
    /// 1. parse Opentoolfile
    String opentoolfilePath = path;
    bool isDir = await FileSystemEntity.isDirectory(opentoolfilePath);
    if(isDir) {
      opentoolfilePath = '$opentoolfilePath${Platform.pathSeparator}$OPENTOOL_FILE_NAME';
    }
    OpentoolfileConfig rawConfig = await OpentoolfileConfigUtil.fromFile(name, opentoolfilePath);

    /// 2. run commands
    OpentoolfileConfig config = await OpentoolfileConfigUtil.resolve(rawConfig);
    String currFolder = DirectoryUtil.getParentDir(opentoolfilePath);
    for (final command in config.build.runs) {
      String output = await CommandUtil.runCommand(currFolder, command);
      onRun(command, output);
    }
    onDone();

    /// 3. copy to temp folder
    String internalId = uniqueId();
    Directory tempDirectory = await Directory.systemTemp.createTemp('OpentoolServer_$internalId');
    String workDirectory = "$currFolder${Platform.pathSeparator}${config.run.workdir}";
    await DirectoryUtil.copyDirectory(Directory(workDirectory), tempDirectory);

    /// 4. save Opentoolfile config in temp folder
    await JsonFileUtil.saveToFile(rawConfig.toJson(), tempDirectory.path, OPENTOOL_FILE_JSON_NAME);

    /// 5. zip, and save to .opentool/servers/{name}-{serverId}.ots
    String otsFilePath = "$OPENTOOL_PATH${Platform.pathSeparator}$SERVER_FOLDER${Platform.pathSeparator}${name}-$internalId.ots";
    await ZipUtil.zipDirectory(tempDirectory.path, otsFilePath);

    /// 6. save to db
    InternalServerDao serverDao = InternalServerDao(
      id: internalId,
      file: otsFilePath,
    );
    await _internalServerStorage.add(serverDao);
    String tagId = uniqueId();

    ServerDao tagDao = ServerDao(
      id: tagId,
      alias: tagId,
      registry: NULL_REGISTRY,
      repo: NULL_REPO,
      name: name,
      tag: tag??NULL_TAG,
      internalId: internalId,
    );
    await _cacheServerStorage.add(tagDao);

    /// 7. remove temp folder
    DirectoryUtil.deleteDirectory(tempDirectory.path);
  }

  Future<void> delete(String serverId) async {
    /// 1. get server info
    ServerDao? serverDao = await _cacheServerStorage.get(serverId);
    if(serverDao == null) throw ServerNotFoundException(serverId);

    /// 2. remove from server cache
    await _cacheServerStorage.remove(serverId);

    /// 3. remove from internal and file if NOT any Server ref to InternalServer
    bool isInternalServerUsed = await _checkInternalIdReference(serverDao.internalId);
    if(!isInternalServerUsed) {
      String otsFilePath = "$OPENTOOL_PATH${Platform.pathSeparator}$SERVER_FOLDER${Platform.pathSeparator}${serverDao.name}-$serverId.ots";
      await DirectoryUtil.deleteFile(otsFilePath);
      await _internalServerStorage.remove(serverDao.internalId);
    }
  }
  
  Future<void> afterPullToTemp(String otsFileTempPath) async {
    /// 1. parse ots info
    String unzipFolder = await ZipUtil.unzipToTemp(otsFileTempPath);
    String opentoolfileJsonPath = "$unzipFolder${Platform.pathSeparator}$OPENTOOL_FILE_JSON_NAME";
    Map<String, dynamic> opentoolfileJson = await JsonFileUtil.readFromFile(opentoolfileJsonPath);
    OpentoolfileConfig opentoolConfig = OpentoolfileConfig.fromJson(opentoolfileJson);

    /// 2. check os and cpuArch matching
    String os = SystemUtil.getOS();
    String cpuArch = SystemUtil.getCpuArch();

    if(opentoolConfig.os != os && opentoolConfig.cpuArch != cpuArch) throw SystemMismatchException(os, cpuArch, opentoolConfig.os, opentoolConfig.cpuArch);

    String internalId = uniqueId();
    String targetPath = "$OPENTOOL_PATH${Platform.pathSeparator}$SERVER_FOLDER${Platform.pathSeparator}${opentoolConfig.name}-$internalId.ots";
    await DirectoryUtil.copyAndRenameFile(otsFileTempPath, targetPath);
  }

  Future<String> beforePush(String serverId) async {
    /// 1. get server info
    ServerDao? serverDao = await _cacheServerStorage.get(serverId);
    if(serverDao == null) {throw ServerNotFoundException(serverId);}

    /// 2. get internal server info
    String internalId = serverDao.internalId;
    InternalServerDao? internalServerDao = await _internalServerStorage.get(internalId);
    if(internalServerDao == null) throw ServerNotFoundException(serverId);

    /// 3. copy to temp folder and rename to {repo}-{name}-{tag}-{os}-{cpu}.ots
    String sourcePath = internalServerDao.file;
    Directory tempDirectory = await Directory.systemTemp.createTemp('OpentoolServer_$internalId');
    String os = await SystemUtil.getOS();
    String cpuArch = await SystemUtil.getCpuArch();
    String otsFileTargetPath = "$tempDirectory${Platform.pathSeparator}${serverDao.repo}-${serverDao.name}-${serverDao.tag}-${os}-${cpuArch}.ots";
    await DirectoryUtil.copyAndRenameFile(sourcePath, otsFileTargetPath);

    return otsFileTargetPath;
  }

  Future<void> afterPush(String otsFilePath) async {
    File otsFile = File(otsFilePath);
    await DirectoryUtil.deleteDirectory(otsFile.parent.path);
  }

  Future<void> export(String serverId, String exportFolder) async {
    /// 1. get server info
    ServerDao? serverDao = await _cacheServerStorage.get(serverId);
    if(serverDao == null) {
      throw ServerNotFoundException(serverId);
    }

    /// 2. get internal server info
    String internalId = serverDao.internalId;
    InternalServerDao? internalServerDao = await _internalServerStorage.get(internalId);
    if(internalServerDao == null) throw ServerNotFoundException(serverId);

    /// 3. copy to export folder and rename to {repo}-{name}-{tag}-{os}-{cpu}.ots
    String sourcePath = internalServerDao.file;
    String os = await SystemUtil.getOS();
    String cpuArch = await SystemUtil.getCpuArch();
    String targetPath = "$exportFolder${Platform.pathSeparator}${serverDao.repo}-${serverDao.name}-${serverDao.tag}-${os}-${cpuArch}.ots";
    await DirectoryUtil.copyAndRenameFile(sourcePath, targetPath);
  }

  Future<ServerModel> import(String otsFilePath) async {
    /// 1. unzip otpkgFile to system temp folder to otsFileName folder
    String tempFolder = await ZipUtil.unzipToTemp(otsFilePath);

    /// 2. parse `Opentoolfile.json`
    String opentoolFileJsonPath = "$tempFolder${Platform.pathSeparator}$OPENTOOL_FILE_JSON_NAME";
    Map<String, dynamic> opentoolFileJson =await JsonFileUtil.readFromFile(opentoolFileJsonPath);
    OpentoolfileConfig opentoolFileConfig = OpentoolfileConfig.fromJson(opentoolFileJson);

    /// 3. new internalId, and save to .opentool/servers/{name}-{internalId}.ots
    String internalId = uniqueId();
    String otsFileTargetPath = "$OPENTOOL_PATH${Platform.pathSeparator}$SERVER_FOLDER${Platform.pathSeparator}${opentoolFileConfig.name}-$internalId.ots";
    await DirectoryUtil.copyAndRenameFile(otsFilePath, otsFileTargetPath);

    /// 4. save to db
    InternalServerDao internalServerDao = InternalServerDao(
      id: internalId,
      file: otsFileTargetPath,
    );
    await _internalServerStorage.add(internalServerDao);

    String serverId = uniqueId();
    ServerDao serverDao = ServerDao(
      id: serverId,
      alias: serverId,
      registry: NULL_REGISTRY,
      repo: NULL_REPO,
      name: opentoolFileConfig.name,
      tag: NULL_TAG,
      internalId: internalId,
    );
    await _cacheServerStorage.add(serverDao);

    ServerModel serverModel = ServerModel.fromDao(serverDao);
    return serverModel;
  }

  Future<ServerModel> tag(String serverId, String? tag) async {
    /// add tag
    ServerDao? serverDao = await _cacheServerStorage.get(serverId);
    if(serverDao == null) throw ServerNotFoundException(serverId);
    String newTag = tag??NULL_TAG;
    String internalId = serverDao.internalId;
    List<ServerDao> serverDaoList = await _cacheServerStorage.list();
    List<ServerDao> serverDaoListWithSameInternalId = serverDaoList.where((serverDao)=>serverDao.internalId == internalId).toList();
    int index = serverDaoListWithSameInternalId.indexWhere((currServerDao)=> currServerDao.tag == newTag);
    if(index < 0) {
      String newId = uniqueId();
      ServerDao newServerDao = serverDao;
      newServerDao.id = newId;
      newServerDao.alias = newId;
      newServerDao.tag = newTag;
      await _cacheServerStorage.add(newServerDao);
      return ServerModel.fromDao(newServerDao);
    }
    ServerDao existedServerDao = serverDaoListWithSameInternalId[index];
    return ServerModel.fromDao(existedServerDao);
  }

  Future<void> setAlias(String serverId, String newName) async {
    /// modify alias
    ServerDao? serverDao = await _cacheServerStorage.get(serverId);
    if(serverDao == null) throw ServerNotFoundException(serverId);
    ServerDao newServerDao = serverDao;
    newServerDao.alias = newName;
    await _cacheServerStorage.update(newServerDao);
  }

  Future<bool> _checkInternalIdReference(String internalId) async {
    List<ServerDao> serverDaoList = await _cacheServerStorage.list();
    for (final serverDao in serverDaoList) {
      if(serverDao.internalId == internalId) {
        return true;
      }
    }
    return false;
  }
}