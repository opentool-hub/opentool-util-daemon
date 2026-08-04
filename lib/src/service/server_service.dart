import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:opentool_daemon/opentool_daemon_utils.dart';
import 'package:unique_id_dart/unique_id_dart.dart';
import 'package:path/path.dart' as p;
import '../constants.dart';
import '../storage/cache_storage.dart';
import '../storage/dao.dart';
import '../storage/hive_storage.dart';
import '../utils/platform_detector.dart';
import 'config.dart';
import 'exception.dart';
import 'model.dart';

class ServerService {
  late CacheServerStorage _cacheServerStorage;
  late HiveInternalServerStorage _internalServerStorage;
  final CacheToolStorage? _toolStorage;
  final Future<void> Function(List<ServerModel>)? _onServersChanged;
  final Map<ServerIdentity, Future<void>> _identityTails = {};

  ServerService(
    HiveServerStorage hiveTag,
    HiveInternalServerStorage hiveServer, {
    CacheServerStorage? cacheServerStorage,
    CacheToolStorage? toolStorage,
    Future<void> Function(List<ServerModel>)? onServersChanged,
  }) : _toolStorage = toolStorage,
       _onServersChanged = onServersChanged {
    _cacheServerStorage = cacheServerStorage ?? CacheServerStorage(hiveTag);
    _internalServerStorage = hiveServer;
  }

  Future<List<ServerModel>> list() async {
    logger.log(LogModule.server, "list.input");
    List<ServerDao> daoList = await _cacheServerStorage.list();
    logger.log(
      LogModule.server,
      "list.result",
      detail: "count: ${daoList.length}",
    );
    return daoList.map((dao) => ServerModel.fromDao(dao)).toList();
  }

  Future<ServerModel> get(String serverId) async {
    logger.log(LogModule.server, "get.input", detail: "serverId: $serverId");
    ServerDao? serverDao = await _cacheServerStorage.get(serverId);
    if (serverDao == null) throw ServerNotFoundException(serverId);
    logger.log(LogModule.server, "get.result", detail: "serverId: $serverId");
    return ServerModel.fromDao(serverDao);
  }

  Future<ServerModel?> findHubSource({
    required String registry,
    required String namespace,
    required String name,
    required String version,
  }) async {
    for (final dao in await _cacheServerStorage.list()) {
      if (dao.registry == registry &&
          dao.namespace == namespace &&
          dao.name == name &&
          dao.version == version) {
        return ServerModel.fromDao(dao);
      }
    }
    return null;
  }

  Future<ServerModel> installHubArtifact(
    String sourcePath,
    HubArtifactMetadata metadata, {
    required void Function() onImporting,
  }) {
    final identity = ServerIdentity(
      registry: metadata.registry,
      namespace: metadata.namespace,
      name: metadata.name,
      version: metadata.version,
    );
    return _withIdentityLock(identity, () async {
      final existing = await findHubSource(
        registry: metadata.registry,
        namespace: metadata.namespace,
        name: metadata.name,
        version: metadata.version,
      );
      if (existing != null) {
        if (existing.artifactDigest == metadata.artifactDigest) return existing;
        throw InstallException(
          code: 'ARTIFACT_VERSION_CONFLICT',
          message:
              'The requested published version is already installed with a different digest',
          retryable: false,
        );
      }

      try {
        final inspection = await ZipUtil.inspect(sourcePath);
        final config = OpentoolfileConfig.fromJson(inspection.manifest);
        _validateHubManifest(config, inspection.files, metadata);
        onImporting();

        final internalId = uniqueId();
        final serverId = uniqueId();
        final serverDirectory = Directory(p.join(OPENTOOL_PATH, SERVER_FOLDER));
        await serverDirectory.create(recursive: true);
        final targetPath = p.join(
          serverDirectory.path,
          '${metadata.name}-$internalId.ots',
        );
        final pendingPath = '$targetPath.pending';
        var internalWritten = false;
        var serverWritten = false;
        try {
          await File(sourcePath).copy(pendingPath);
          await File(pendingPath).rename(targetPath);
          await _internalServerStorage.add(
            InternalServerDao(id: internalId, file: targetPath),
          );
          internalWritten = true;
          final dao = ServerDao(
            id: serverId,
            alias: metadata.name,
            registry: metadata.registry,
            namespace: metadata.namespace,
            name: metadata.name,
            version: metadata.version,
            internalId: internalId,
            artifactId: metadata.artifactId,
            versionDigest: metadata.versionDigest,
            artifactDigest: metadata.artifactDigest,
            artifactMediaType: metadata.artifactMediaType,
            artifactSize: metadata.artifactSize,
            platformOs: metadata.platform.os,
            platformArch: metadata.platform.arch,
            platformAbi: metadata.platform.abi,
            installedAt: DateTime.now().toUtc(),
          );
          await _cacheServerStorage.add(dao);
          serverWritten = true;
          await _notifyServersChanged();
          return ServerModel.fromDao(dao);
        } catch (_) {
          if (serverWritten) await _cacheServerStorage.remove(serverId);
          if (internalWritten) await _internalServerStorage.remove(internalId);
          await DirectoryUtil.deleteFile(pendingPath);
          await DirectoryUtil.deleteFile(targetPath);
          rethrow;
        }
      } on InstallException {
        rethrow;
      } on FormatException catch (error) {
        throw InstallException(
          code: 'ARTIFACT_INVALID',
          message: error.message,
          retryable: false,
        );
      } on FileSystemException catch (error) {
        throw InstallException(
          code: 'DISK_WRITE_FAILED',
          message: error.message,
          retryable: true,
        );
      } on Object catch (error) {
        throw InstallException(
          code: 'INSTALL_FAILED',
          message: 'Unable to register the artifact: $error',
          retryable: true,
        );
      }
    });
  }

  void _validateHubManifest(
    OpentoolfileConfig config,
    Set<String> files,
    HubArtifactMetadata metadata,
  ) {
    String normalizedName(String value) => value
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^opentool-server-'), '');
    if (normalizedName(config.name) != normalizedName(metadata.name) ||
        config.tag?.trim() != metadata.version ||
        config.os.toLowerCase() != metadata.platform.os ||
        config.cpuArch.toLowerCase() != metadata.platform.arch) {
      throw const FormatException(
        'Opentoolfile.json does not match the resolved Hub artifact',
      );
    }
    final resolved = OpentoolfileConfigUtil.resolve(config);
    final workdir = resolved.run.workdir.trim().isEmpty
        ? '.'
        : resolved.run.workdir.trim();
    final entrypoint = resolved.run.entrypoint.trim();
    if (workdir.contains(r'\') ||
        entrypoint.contains(r'\') ||
        p.posix.isAbsolute(workdir) ||
        p.posix.isAbsolute(entrypoint)) {
      throw const FormatException(
        'Tool entrypoint is not a safe relative path',
      );
    }
    final executable = p.posix.normalize(p.posix.join(workdir, entrypoint));
    if (executable == '.' ||
        executable == '..' ||
        executable.startsWith('../')) {
      throw const FormatException('Tool entrypoint escapes the artifact');
    }
    final candidates = <String>[executable];
    if (metadata.platform.os == 'windows' &&
        p.posix.extension(executable).isEmpty) {
      candidates.addAll([
        '$executable.exe',
        '$executable.cmd',
        '$executable.bat',
      ]);
    }
    if (!candidates.any(files.contains)) {
      throw const FormatException(
        'Tool entrypoint is missing from the artifact',
      );
    }
  }

  Future<void> reconcileInstallations() async {
    final serverDirectory = Directory(p.join(OPENTOOL_PATH, SERVER_FOLDER));
    final serverRoot = p.normalize(serverDirectory.absolute.path);
    bool isManagedServerFile(String path) =>
        p.isWithin(serverRoot, p.normalize(File(path).absolute.path));
    final servers = await _cacheServerStorage.list();
    final internals = await _internalServerStorage.list();
    final internalById = {for (final item in internals) item.id: item};
    for (final server in servers) {
      final internal = internalById[server.internalId];
      if (internal == null || !await File(internal.file).exists()) {
        await _cacheServerStorage.remove(server.id);
      }
    }

    final referenced = (await _cacheServerStorage.list())
        .map((server) => server.internalId)
        .toSet();
    for (final internal in await _internalServerStorage.list()) {
      if (!referenced.contains(internal.id)) {
        await _internalServerStorage.remove(internal.id);
        if (isManagedServerFile(internal.file)) {
          await DirectoryUtil.deleteFile(internal.file);
        }
      }
    }

    final trackedPaths = (await _internalServerStorage.list())
        .map((item) => p.normalize(File(item.file).absolute.path))
        .toSet();
    if (await serverDirectory.exists()) {
      await for (final entity in serverDirectory.list()) {
        if (entity is! File) continue;
        final absolute = p.normalize(entity.absolute.path);
        if (entity.path.endsWith('.pending') ||
            (entity.path.endsWith('.ots') &&
                !trackedPaths.contains(absolute))) {
          await entity.delete();
        }
      }
    }
    final downloads = Directory(p.join(OPENTOOL_PATH, 'downloads'));
    if (await downloads.exists()) {
      await for (final entity in downloads.list()) {
        if (entity is File && entity.path.endsWith('.part')) {
          await entity.delete();
        }
      }
    }
  }

  Future<void> buildServer(
    String path,
    String name,
    String? tag,
    void Function(String command, String output) onRun,
    void Function() onDone,
  ) async {
    logger.log(
      LogModule.server,
      "build.input",
      detail: "path: $path, name: $name, tag: ${tag ?? NULL_TAG}",
    );

    /// 1. parse Opentoolfile
    String opentoolfilePath = path;
    bool isDir = await FileSystemEntity.isDirectory(opentoolfilePath);
    if (isDir) {
      opentoolfilePath =
          '$opentoolfilePath${Platform.pathSeparator}$OPENTOOL_FILE_NAME';
    }
    OpentoolfileConfig rawConfig = await OpentoolfileConfigUtil.fromFile(
      name,
      opentoolfilePath,
      tag: tag ?? NULL_TAG,
    );

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
    Directory tempDirectory = await Directory.systemTemp.createTemp(
      'OpentoolServer_$internalId',
    );
    final String relativeWorkdir = config.run.workdir;
    String workDirectory =
        "$currFolder${Platform.pathSeparator}$relativeWorkdir";
    Directory targetWorkdir = Directory(
      p.join(tempDirectory.path, relativeWorkdir),
    );
    await DirectoryUtil.copyDirectory(Directory(workDirectory), targetWorkdir);

    /// 4. save Opentoolfile config in temp folder
    await JsonFileUtil.saveToFile(
      rawConfig.toJson(),
      tempDirectory.path,
      OPENTOOL_FILE_JSON_NAME,
    );

    /// 5. zip, and save to .opentool/servers/{name}-{serverId}.ots
    String otsFilePath =
        "$OPENTOOL_PATH${Platform.pathSeparator}$SERVER_FOLDER${Platform.pathSeparator}${name}-$internalId.ots";
    await ZipUtil.zipDirectory(tempDirectory.path, otsFilePath);

    /// 6. save to db
    InternalServerDao serverDao = InternalServerDao(
      id: internalId,
      file: otsFilePath,
    );
    await _internalServerStorage.add(serverDao);
    final server = await _upsertServerIdentity(
      ServerIdentity(
        registry: LOCAL_REGISTRY,
        namespace: LOCAL_NAMESPACE,
        name: name,
        version: tag ?? NULL_TAG,
      ),
      internalId,
    );
    final artifactFile = File(otsFilePath);
    final digest = await sha256.bind(artifactFile.openRead()).first;
    server.artifactDigest = 'sha256:$digest';
    server.artifactMediaType = 'application/vnd.opentool.ots';
    server.artifactSize = await artifactFile.length();
    server.platform = await PlatformDetector().detect();
    server.installedAt = DateTime.now().toUtc();
    await _cacheServerStorage.update(server.toDao());

    /// 7. remove temp folder
    DirectoryUtil.deleteDirectory(tempDirectory.path);
    logger.log(
      LogModule.server,
      "build.result",
      detail: "name: $name, tag: ${tag ?? NULL_TAG}, serverId: ${server.id}",
    );
  }

  Future<void> delete(String serverId) async {
    logger.log(LogModule.server, "delete.input", detail: "serverId: $serverId");

    /// 1. get server info
    ServerDao? serverDao = await _cacheServerStorage.get(serverId);
    if (serverDao == null) throw ServerNotFoundException(serverId);

    /// 2. remove from server cache
    await _cacheServerStorage.remove(serverId);

    /// 3. remove from internal and file if NOT any Server ref to InternalServer
    bool isInternalServerUsed = await _checkInternalIdReference(
      serverDao.internalId,
    );
    if (!isInternalServerUsed) {
      final internal = await _internalServerStorage.remove(
        serverDao.internalId,
      );
      if (internal != null) await DirectoryUtil.deleteFile(internal.file);
    }
    logger.log(
      LogModule.server,
      "delete.result",
      detail: "serverId: $serverId removed",
    );
  }

  Future<void> export(String serverId, String exportFolder) async {
    logger.log(
      LogModule.server,
      "export.input",
      detail: "serverId: $serverId, target: $exportFolder",
    );

    /// 1. get server info
    ServerDao? serverDao = await _cacheServerStorage.get(serverId);
    if (serverDao == null) {
      throw ServerNotFoundException(serverId);
    }

    /// 2. get internal server info
    String internalId = serverDao.internalId;
    InternalServerDao? internalServerDao = await _internalServerStorage.get(
      internalId,
    );
    if (internalServerDao == null) throw ServerNotFoundException(serverId);

    /// 3. copy to export folder and rename to {repo}-{name}-{tag}-{os}-{cpu}.ots
    String sourcePath = internalServerDao.file;
    String os = SystemUtil.getOS();
    String cpuArch = SystemUtil.getCpuArch();
    String targetPath =
        "$exportFolder${Platform.pathSeparator}${serverDao.namespace}-${serverDao.name}-${serverDao.version}-${os}-${cpuArch}.ots";
    await DirectoryUtil.copyAndRenameFile(sourcePath, targetPath);
    logger.log(
      LogModule.server,
      "export.result",
      detail: "targetPath: $targetPath",
    );
  }

  Future<ServerModel> import(String otsFilePath) async {
    logger.log(
      LogModule.server,
      "import.input",
      detail: "source: $otsFilePath",
    );

    /// 1. inspect and parse `Opentoolfile.json`
    final sourceFile = File(otsFilePath);
    final inspection = await ZipUtil.inspect(otsFilePath);
    Map<String, dynamic> opentoolFileJson = inspection.manifest;
    OpentoolfileConfig opentoolfileConfig = OpentoolfileConfig.fromJson(
      opentoolFileJson,
    );

    /// 3. check os and cpuArch matching
    final platform = await PlatformDetector().detect();
    String os = platform.os;
    String cpuArch = platform.arch;

    if (opentoolfileConfig.os != os || opentoolfileConfig.cpuArch != cpuArch)
      throw SystemMismatchException(
        os,
        cpuArch,
        opentoolfileConfig.os,
        opentoolfileConfig.cpuArch,
      );

    /// 4. new internalId, and save to .opentool/servers/{name}-{internalId}.ots
    String internalId = uniqueId();
    String otsFileTargetPath =
        "$OPENTOOL_PATH${Platform.pathSeparator}$SERVER_FOLDER${Platform.pathSeparator}${opentoolfileConfig.name}-$internalId.ots";
    await DirectoryUtil.copyAndRenameFile(otsFilePath, otsFileTargetPath);

    /// 5. save to db
    InternalServerDao internalServerDao = InternalServerDao(
      id: internalId,
      file: otsFileTargetPath,
    );
    await _internalServerStorage.add(internalServerDao);

    final serverModel = await _upsertServerIdentity(
      ServerIdentity(
        registry: LOCAL_REGISTRY,
        namespace: LOCAL_NAMESPACE,
        name: opentoolfileConfig.name,
        version: opentoolfileConfig.tag ?? NULL_TAG,
      ),
      internalId,
    );
    final digest = await sha256.bind(sourceFile.openRead()).first;
    serverModel.artifactDigest = 'sha256:$digest';
    serverModel.artifactMediaType = 'application/vnd.opentool.ots';
    serverModel.artifactSize = await sourceFile.length();
    serverModel.platform = platform;
    serverModel.installedAt = DateTime.now().toUtc();
    await _cacheServerStorage.update(serverModel.toDao());

    logger.log(
      LogModule.server,
      "import.result",
      detail: "serverId: ${serverModel.id}",
    );
    return serverModel;
  }

  Future<ServerModel> tag(String serverId, String? tag) async {
    logger.log(
      LogModule.server,
      "tag.input",
      detail: "serverId: $serverId, tag: ${tag ?? NULL_TAG}",
    );

    ServerDao? serverDao = await _cacheServerStorage.get(serverId);
    if (serverDao == null) throw ServerNotFoundException(serverId);
    if (serverDao.versionDigest != null) {
      throw const InstallException(
        code: 'HUB_VERSION_IMMUTABLE',
        message: 'Hub-installed server versions cannot be retagged locally',
        retryable: false,
      );
    }
    final newTag = tag ?? NULL_TAG;
    if (serverDao.tag == newTag) {
      logger.log(
        LogModule.server,
        "tag.noop",
        detail: "serverId: ${serverDao.id}, tag: ${serverDao.tag}",
      );
      return ServerModel.fromDao(serverDao);
    }

    final taggedServer = await _upsertServerIdentity(
      ServerIdentity(
        registry: serverDao.registry,
        namespace: serverDao.namespace,
        name: serverDao.name,
        version: newTag,
      ),
      serverDao.internalId,
      artifactSource: serverDao,
    );

    logger.log(
      LogModule.server,
      "tag.updated",
      detail: "serverId: ${taggedServer.id}, tag: ${taggedServer.tag}",
    );
    return taggedServer;
  }

  Future<void> setAlias(String serverId, String newName) async {
    logger.log(
      LogModule.server,
      "setAlias.input",
      detail: "serverId: $serverId, alias: $newName",
    );

    /// modify alias
    ServerDao? serverDao = await _cacheServerStorage.get(serverId);
    if (serverDao == null) throw ServerNotFoundException(serverId);
    ServerDao newServerDao = serverDao;
    newServerDao.alias = newName;
    await _cacheServerStorage.update(newServerDao);
    logger.log(
      LogModule.server,
      "setAlias.result",
      detail: "serverId: $serverId, alias: $newName",
    );
  }

  Future<void> _removeServersByNameAndTag(
    String name,
    String tag, {
    String? excludeServerId,
  }) async {
    final servers = await _cacheServerStorage.list();
    final duplicates = servers
        .where(
          (dao) =>
              dao.name == name && dao.tag == tag && dao.id != excludeServerId,
        )
        .toList();

    for (final serverDao in duplicates) {
      await _cacheServerStorage.remove(serverDao.id);
      final stillUsed = await _checkInternalIdReference(serverDao.internalId);
      if (!stillUsed) {
        final otsFilePath =
            "$OPENTOOL_PATH${Platform.pathSeparator}$SERVER_FOLDER${Platform.pathSeparator}${serverDao.name}-${serverDao.internalId}.ots";
        await DirectoryUtil.deleteFile(otsFilePath);
        await _internalServerStorage.remove(serverDao.internalId);
      }
      logger.log(
        LogModule.server,
        "dedupe.removed",
        detail: "serverId: ${serverDao.id}, tag: $tag",
      );
    }
  }

  Future<ServerModel> _upsertServerIdentity(
    ServerIdentity identity,
    String internalId, {
    ServerDao? artifactSource,
  }) {
    return _withIdentityLock(identity, () async {
      await _cacheServerStorage.list();
      final matching =
          (await _cacheServerStorage.list())
              .where((dao) => ServerModel.fromDao(dao).identity == identity)
              .toList()
            ..sort((a, b) => a.id.compareTo(b.id));

      final ServerDao canonical;
      String? replacedInternalId;
      if (matching.isEmpty) {
        final serverId = uniqueId();
        canonical = ServerDao(
          id: serverId,
          alias: serverId,
          registry: identity.registry,
          namespace: identity.namespace,
          name: identity.name,
          version: identity.version,
          internalId: internalId,
          artifactId: artifactSource?.artifactId,
          versionDigest: artifactSource?.versionDigest,
          artifactDigest: artifactSource?.artifactDigest,
          artifactMediaType: artifactSource?.artifactMediaType,
          artifactSize: artifactSource?.artifactSize,
          platformOs: artifactSource?.platformOs,
          platformArch: artifactSource?.platformArch,
          platformAbi: artifactSource?.platformAbi,
          installedAt: artifactSource?.installedAt,
        );
        await _cacheServerStorage.add(canonical);
      } else {
        final existing = matching.first;
        replacedInternalId = existing.internalId == internalId
            ? null
            : existing.internalId;
        canonical = ServerDao(
          id: existing.id,
          alias: existing.alias,
          registry: identity.registry,
          namespace: identity.namespace,
          name: identity.name,
          version: identity.version,
          internalId: internalId,
          artifactId: artifactSource?.artifactId,
          versionDigest: artifactSource?.versionDigest,
          artifactDigest: artifactSource?.artifactDigest,
          artifactMediaType: artifactSource?.artifactMediaType,
          artifactSize: artifactSource?.artifactSize,
          platformOs: artifactSource?.platformOs,
          platformArch: artifactSource?.platformArch,
          platformAbi: artifactSource?.platformAbi,
          installedAt: artifactSource?.installedAt,
        );
        await _cacheServerStorage.update(canonical);
      }

      await _consolidateIdentity(identity, canonical.id);
      if (replacedInternalId != null) {
        await _removeInternalServerIfUnused(identity.name, replacedInternalId);
      }
      await _notifyServersChanged();
      return ServerModel.fromDao(canonical);
    });
  }

  Future<void> _consolidateIdentity(
    ServerIdentity identity,
    String canonicalServerId,
  ) async {
    final duplicates = (await _cacheServerStorage.list())
        .where(
          (dao) =>
              dao.id != canonicalServerId &&
              ServerModel.fromDao(dao).identity == identity,
        )
        .toList();

    for (final duplicate in duplicates) {
      final toolStorage = _toolStorage;
      if (toolStorage != null) {
        final tools = await toolStorage.list();
        for (final tool in tools.where(
          (tool) => tool.serverId == duplicate.id,
        )) {
          tool.serverId = canonicalServerId;
          _applyIdentitySnapshot(tool, identity);
          await toolStorage.update(tool);
        }
      }
      await _cacheServerStorage.remove(duplicate.id);
      await _removeInternalServerIfUnused(duplicate.name, duplicate.internalId);
      logger.log(
        LogModule.server,
        "identityDedup.removed",
        detail:
            "serverId: ${duplicate.id}, canonicalServerId: $canonicalServerId, identity: $identity",
      );
    }
  }

  void _applyIdentitySnapshot(ToolDao tool, ServerIdentity identity) {
    tool.serverRegistry = identity.registry;
    tool.serverRepo = identity.repo;
    tool.serverName = identity.name;
    tool.serverTag = identity.tag;
  }

  Future<void> _removeInternalServerIfUnused(
    String serverName,
    String internalId,
  ) async {
    if (await _checkInternalIdReference(internalId)) return;
    final internal = await _internalServerStorage.remove(internalId);
    final path =
        internal?.file ??
        "$OPENTOOL_PATH${Platform.pathSeparator}$SERVER_FOLDER${Platform.pathSeparator}$serverName-$internalId.ots";
    await DirectoryUtil.deleteFile(path);
  }

  Future<void> _notifyServersChanged() async {
    final callback = _onServersChanged;
    if (callback != null) await callback(await list());
  }

  Future<T> _withIdentityLock<T>(
    ServerIdentity identity,
    Future<T> Function() action,
  ) async {
    final previous = _identityTails[identity] ?? Future<void>.value();
    final completer = Completer<void>();
    _identityTails[identity] = completer.future;
    try {
      await previous.catchError((_) {});
      return await action();
    } finally {
      completer.complete();
      if (identical(_identityTails[identity], completer.future)) {
        _identityTails.remove(identity);
      }
    }
  }

  Future<void> removeServersByNameAndTagForTest(
    String name,
    String tag, {
    String? excludeServerId,
  }) async {
    await _removeServersByNameAndTag(
      name,
      tag,
      excludeServerId: excludeServerId,
    );
  }

  Future<bool> _checkInternalIdReference(String internalId) async {
    List<ServerDao> serverDaoList = await _cacheServerStorage.list();
    for (final serverDao in serverDaoList) {
      if (serverDao.internalId == internalId) {
        return true;
      }
    }
    return false;
  }
}
