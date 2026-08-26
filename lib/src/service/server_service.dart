import 'dart:io';

import 'package:logging/logging.dart';
import 'package:opentool_daemon/opentool_daemon_utils.dart';
import 'package:path/path.dart' as p;
import 'package:unique_id_dart/unique_id_dart.dart';

import '../constants.dart';
import '../storage/cache_storage.dart';
import '../storage/dao.dart';
import '../storage/storage.dart';
import '../utils/platform_detector.dart';
import 'artifact_registry_service.dart';
import 'config.dart';
import 'exception.dart';
import 'model.dart';

class ServerService {
  final CacheServerStorage _servers;
  final CacheToolStorage? _tools;
  final Future<void> Function(List<ServerModel>)? _onServersChanged;
  final ArtifactRegistryService _registry;
  final PlatformDetector _platformDetector;

  ServerService(
    Storage<ServerDao> serverStorage, {
    CacheServerStorage? cacheServerStorage,
    CacheToolStorage? toolStorage,
    Future<void> Function(List<ServerModel>)? onServersChanged,
    required ArtifactRegistryService artifactRegistry,
    PlatformDetector? platformDetector,
  }) : _servers = cacheServerStorage ?? CacheServerStorage(serverStorage),
       _tools = toolStorage,
       _onServersChanged = onServersChanged,
       _registry = artifactRegistry,
       _platformDetector = platformDetector ?? PlatformDetector();

  Future<List<ServerModel>> list() async {
    logger.log(LogModule.server, 'list.input', level: Level.FINE);
    final daos = await _servers.list();
    final toolServerIds = _tools == null
        ? const <String>{}
        : (await _tools.list())
              .map((tool) => tool.serverId)
              .whereType<String>()
              .toSet();
    final models = <ServerModel>[];
    for (final dao in daos) {
      models.add(await _toModel(dao, inUse: toolServerIds.contains(dao.id)));
    }
    logger.log(
      LogModule.server,
      'list.result',
      detail: 'count: ${models.length}',
      level: Level.FINE,
    );
    return models;
  }

  Future<ServerModel> get(String serverId) async {
    logger.log(LogModule.server, 'get.input', detail: 'serverId: $serverId');
    final dao = await _servers.get(serverId);
    if (dao == null) throw ServerNotFoundException(serverId);
    final inUse =
        _tools != null &&
        (await _tools.list()).any((tool) => tool.serverId == serverId);
    return _toModel(dao, inUse: inUse);
  }

  Future<ServerModel> _toModel(ServerDao dao, {required bool inUse}) async {
    final artifact = await _registry.artifacts.get(dao.artifactDigest);
    final references = (await _servers.list())
        .where((server) => server.artifactDigest == dao.artifactDigest)
        .length;
    final model = ServerModel.fromDao(
      dao,
      artifact: artifact,
      artifactReferenceCount: references,
    );
    model.canRun = dao.state == 'available' && artifact != null;
    model.canRemove = !dao.protected && !inUse;
    return model;
  }

  Future<ServerModel?> findHubSource({
    required String registry,
    required String namespace,
    required String name,
    required String version,
  }) async {
    for (final dao in await _servers.list()) {
      if (dao.registry == registry &&
          dao.namespace == namespace &&
          dao.name == name &&
          dao.version == version) {
        return _toModel(dao, inUse: false);
      }
    }
    return null;
  }

  Future<ServerModel> registerHubArtifact(
    String sourcePath,
    HubArtifactMetadata metadata, {
    required void Function() onImporting,
  }) async {
    onImporting();
    final server = await _registry.registerArtifact(
      sourcePath,
      ServerReferenceInput.hub(
        registry: metadata.registry,
        namespace: metadata.namespace,
        name: metadata.name,
        version: metadata.version,
        versionRevision: metadata.versionRevision,
        versionDigest: metadata.versionDigest,
        hubArtifactId: metadata.artifactId,
      ),
      const RegistrationPolicy(),
      expectedMetadata: ArtifactExpectedMetadata(
        digest: metadata.artifactDigest,
        size: metadata.artifactSize,
        name: metadata.name,
        version: metadata.version,
        platform: metadata.platform,
      ),
    );
    return get(server.id);
  }

  Future<ServerModel> refreshHubSourceMetadata(
    String serverId,
    HubArtifactMetadata metadata,
  ) async {
    final server = await _servers.get(serverId);
    if (server == null) throw ServerNotFoundException(serverId);
    if (server.sourceKind != 'hub' ||
        server.registry != metadata.registry ||
        server.namespace != metadata.namespace ||
        server.name != metadata.name ||
        server.version != metadata.version ||
        server.artifactDigest != metadata.artifactDigest) {
      throw const ArtifactOperationException(
        code: 'ARTIFACT_SOURCE_CONFLICT',
        message: 'The installed Hub source does not match resolved metadata',
        retryable: false,
      );
    }
    server.versionRevision = metadata.versionRevision;
    server.versionDigest = metadata.versionDigest;
    server.hubArtifactId = metadata.artifactId;
    await _servers.update(server);
    await _notifyServersChanged();
    return get(server.id);
  }

  Future<void> reconcileInstallations() => _registry.recover();

  Future<void> buildServer(
    String path,
    String name,
    String? tag,
    void Function(String command, String output) onRun,
    void Function() onDone,
  ) async {
    logger.log(
      LogModule.server,
      'build.input',
      detail: 'name: $name, tag: ${tag ?? NULL_TAG}',
    );
    var opentoolfilePath = path;
    if (await FileSystemEntity.isDirectory(opentoolfilePath)) {
      opentoolfilePath = p.join(opentoolfilePath, OPENTOOL_FILE_NAME);
    }
    final platform = await _platformDetector.detect();
    final rawConfig =
        await OpentoolfileConfigUtil.fromFile(
            name,
            opentoolfilePath,
            tag: tag ?? NULL_TAG,
          )
          ..os = platform.os
          ..cpuArch = platform.arch
          ..abi = platform.abi;
    final config = await OpentoolfileConfigUtil.resolve(rawConfig);
    final sourceDirectory = DirectoryUtil.getParentDir(opentoolfilePath);
    for (final command in config.build.runs) {
      onRun(command, await CommandUtil.runCommand(sourceDirectory, command));
    }
    onDone();

    final operationId = uniqueId();
    final tempDirectory = await Directory.systemTemp.createTemp(
      'OpentoolServer_$operationId',
    );
    final output = p.join(tempDirectory.parent.path, '$operationId.ots');
    try {
      final targetWorkdir = Directory(
        p.join(tempDirectory.path, config.run.workdir),
      );
      await DirectoryUtil.copyDirectory(
        Directory(p.join(sourceDirectory, config.run.workdir)),
        targetWorkdir,
      );
      await JsonFileUtil.saveToFile(
        rawConfig.toJson(),
        tempDirectory.path,
        OPENTOOL_FILE_JSON_NAME,
      );
      await ZipUtil.zipDirectory(tempDirectory.path, output);
      final version = tag ?? NULL_TAG;
      await _registry.registerArtifact(
        output,
        ServerReferenceInput.local(
          kind: 'build',
          namespace: LOCAL_NAMESPACE,
          name: name,
          version: version,
        ),
        const RegistrationPolicy(),
        expectedMetadata: ArtifactExpectedMetadata(
          name: name,
          version: version,
          platform: platform,
        ),
      );
    } finally {
      await DirectoryUtil.deleteFile(output);
      await DirectoryUtil.deleteDirectory(tempDirectory.path);
    }
  }

  Future<void> delete(String serverId) => _registry.removeServer(serverId);

  Future<void> export(String serverId, String exportFolder) async {
    final server = await get(serverId);
    final sourcePath = server.artifactFilePath;
    if (sourcePath == null) throw ServerNotFoundException(serverId);
    final platform = server.platform ?? await _platformDetector.detect();
    final targetPath = p.join(
      exportFolder,
      '${server.namespace}-${server.name}-${server.version}-'
      '${platform.os}-${platform.arch}-${platform.abi}.ots',
    );
    await DirectoryUtil.copyAndRenameFile(sourcePath, targetPath);
  }

  Future<ServerModel> import(String otsFilePath) async {
    final inspection = await ZipUtil.inspect(otsFilePath);
    final config = OpentoolfileConfig.fromJson(inspection.manifest);
    final platform = await _platformDetector.detect();
    final artifactAbi = OpentoolfileConfigUtil.resolvedAbi(
      config.os,
      config.abi,
    );
    if (config.os.toLowerCase() != platform.os ||
        config.cpuArch.toLowerCase() != platform.arch ||
        artifactAbi != platform.abi) {
      throw SystemMismatchException(
        platform.os,
        platform.arch,
        config.os,
        config.cpuArch,
        nativeAbi: platform.abi,
        remoteAbi: artifactAbi,
      );
    }
    final version = config.tag ?? NULL_TAG;
    final server = await _registry.registerArtifact(
      otsFilePath,
      ServerReferenceInput.local(
        kind: 'import',
        namespace: LOCAL_NAMESPACE,
        name: config.name,
        version: version,
      ),
      const RegistrationPolicy(),
      expectedMetadata: ArtifactExpectedMetadata(
        name: config.name,
        version: version,
        platform: platform,
      ),
    );
    return get(server.id);
  }

  Future<void> setAlias(String serverId, String newName) async {
    final server = await _servers.get(serverId);
    if (server == null) throw ServerNotFoundException(serverId);
    server.alias = newName;
    await _servers.update(server);
    await _notifyServersChanged();
  }

  Future<void> _notifyServersChanged() async {
    final callback = _onServersChanged;
    if (callback != null) await callback(await list());
  }
}
