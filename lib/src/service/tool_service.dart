import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:opentool_daemon/opentool_daemon_utils.dart';
import 'package:unique_id_dart/unique_id_dart.dart';
import 'package:opentool_dart/opentool_client.dart';
import 'package:path/path.dart' as p;
import '../constants.dart';
import '../storage/cache_storage.dart';
import '../storage/dao.dart';
import '../storage/storage.dart';
import '../utils/executable_util.dart';
import '../utils/port_reservation_allocator.dart';
import 'config.dart';
import 'exception.dart';
import 'model.dart';
import 'tool_materialization_service.dart';

int preferredPortForNewTool() => TOOL_DEFAULT_PORT;

typedef ToolProcessLauncher =
    Future<int> Function(
      String workdir,
      String entrypoint,
      List<String> commands,
      void Function(String command, String output)? onStdout,
      void Function(String command, String error)? onStderr,
      bool printStd,
    );

typedef ToolDirectoryDeleter = Future<void> Function(String path);

class ToolService {
  late CacheToolStorage _cacheToolStorage;
  final Map<String, OpenToolClient> _clients = {};
  final StreamController<ToolLifecycleEventModel> _eventController =
      StreamController<ToolLifecycleEventModel>.broadcast();
  late final OpenToolClient Function(ToolDao toolDao) _clientFactory;
  late final PortReservationAllocator _portReservationAllocator;
  late final Future<bool> Function(String host, int port) _portAvailability;
  late final ToolProcessLauncher _processLauncher;
  late final ToolDirectoryDeleter _directoryDeleter;
  final Future<ServerModel> Function(String serverId)? _serverGetter;
  final Future<List<ServerModel>> Function()? _serverLister;
  final Map<String, Future<ToolModel>> _runFlights = {};
  final Map<String, _StartFlight> _startFlights = {};
  final Map<String, _AsyncMutex> _lifecycleLocks = {};
  final Map<String, int> _lifecycleGenerations = {};
  final Map<String, int> _lifecycleRequestEpochs = {};
  final Duration _readyCheckInterval;
  final Duration _readyCheckTimeout;
  final Duration _lifecycleRequestTimeout;
  final ToolMaterializationService? _materializationService;
  final Duration _stopCheckInterval;
  final Duration _stopCheckTimeout;

  Stream<ToolLifecycleEventModel> get events => _eventController.stream;

  ToolService(
    Storage<ToolDao> hive, {
    CacheToolStorage? cacheToolStorage,
    OpenToolClient Function(ToolDao toolDao)? clientFactory,
    Future<int> Function(String host, int startPort)? portAllocator,
    PortReservationAllocator? portReservationAllocator,
    Future<bool> Function(String host, int port)? portAvailability,
    ToolProcessLauncher? processLauncher,
    ToolDirectoryDeleter? directoryDeleter,
    Future<ServerModel> Function(String serverId)? serverGetter,
    Future<List<ServerModel>> Function()? serverLister,
    ToolMaterializationService? materializationService,
    Duration readyCheckInterval = const Duration(milliseconds: 500),
    Duration readyCheckTimeout = const Duration(seconds: 180),
    Duration lifecycleRequestTimeout = const Duration(seconds: 5),
    Duration stopCheckInterval = const Duration(milliseconds: 100),
    Duration stopCheckTimeout = const Duration(seconds: 2),
  }) : _serverGetter = serverGetter,
       _serverLister = serverLister,
       _materializationService = materializationService,
       _readyCheckInterval = readyCheckInterval,
       _readyCheckTimeout = readyCheckTimeout,
       _lifecycleRequestTimeout = lifecycleRequestTimeout,
       _stopCheckInterval = stopCheckInterval,
       _stopCheckTimeout = stopCheckTimeout {
    _cacheToolStorage = cacheToolStorage ?? CacheToolStorage(hive);
    _clientFactory = clientFactory ?? _buildClient;
    _portReservationAllocator =
        portReservationAllocator ??
        PortReservationAllocator(portAllocator ?? findAvailablePort);
    _portAvailability = portAvailability ?? isPortAvailable;
    _processLauncher =
        processLauncher ??
        (workdir, entrypoint, commands, onStdout, onStderr, printStd) =>
            CommandUtil.runStream(
              workdir,
              entrypoint,
              commands,
              onStdout: onStdout,
              onStderr: onStderr,
              printStd: printStd,
            );
    _directoryDeleter =
        directoryDeleter ?? ((path) => DirectoryUtil.deleteDirectory(path));
  }

  Future<void> refreshStatusesOnStartup({bool autoRestore = false}) async {
    logger.log(
      LogModule.tool,
      "refreshStatusesOnStartup.start",
      detail: "initializing tool status cache, autoRestore: $autoRestore",
    );
    final List<ToolDao> toolDaos = await _cacheToolStorage.list();
    int restored = 0;
    int markedNotRunning = 0;
    for (final toolDao in toolDaos) {
      final persistedStatus = toolDao.status;
      if (persistedStatus == ToolStatusType.STOPPING) {
        final client = _clients[toolDao.id] ?? _registerClient(toolDao);
        try {
          await _stopWithTimeout(client);
        } catch (_) {
          // A persisted stopping state is completed as notRunning on restart.
        }
        toolDao.status = ToolStatusType.NOT_RUNNING;
        await _cacheToolStorage.update(toolDao);
        _clients.remove(toolDao.id);
        markedNotRunning++;
        continue;
      }

      if (await _isHealthy(toolDao)) {
        if (toolDao.status != ToolStatusType.RUNNING) {
          toolDao.status = ToolStatusType.RUNNING;
          await _cacheToolStorage.update(toolDao);
        }
        continue;
      }

      _clients.remove(toolDao.id);
      final shouldRestore =
          autoRestore &&
          (persistedStatus == ToolStatusType.RUNNING ||
              persistedStatus == ToolStatusType.STARTING);
      if (shouldRestore) {
        try {
          logger.log(
            LogModule.tool,
            "refreshStatusesOnStartup.restoring",
            detail: "toolId: ${toolDao.id}",
          );
          await startTool(ToolModel.fromDao(toolDao), printStd: false);
          restored++;
          logger.log(
            LogModule.tool,
            "refreshStatusesOnStartup.restored",
            detail: "toolId: ${toolDao.id}",
          );
        } catch (restoreError, restoreStackTrace) {
          markedNotRunning++;
          logger.log(
            LogModule.tool,
            "refreshStatusesOnStartup.restoreFailed",
            detail:
                "toolId: ${toolDao.id}, error: $restoreError\n$restoreStackTrace",
            level: Level.WARNING,
          );
        }
      } else {
        if (toolDao.status != ToolStatusType.NOT_RUNNING) {
          toolDao.status = ToolStatusType.NOT_RUNNING;
          await _cacheToolStorage.update(toolDao);
          markedNotRunning++;
          logger.log(
            LogModule.tool,
            "refreshStatusesOnStartup.markNotRunning",
            detail: "toolId: ${toolDao.id}",
            level: Level.WARNING,
          );
        }
      }
    }
    logger.log(
      LogModule.tool,
      "refreshStatusesOnStartup.done",
      detail:
          "checked: ${toolDaos.length}, restored: $restored, markedNotRunning: $markedNotRunning",
    );
  }

  /// Lists tools known to the daemon. Set [all] to true to include stopped tools.
  Future<List<ToolModel>> list({bool all = false}) async {
    logger.log(
      LogModule.tool,
      "list.input",
      detail: "all: $all",
      level: Level.FINE,
    );
    List<ToolDao> daoList = await _cacheToolStorage.list();
    if (!all) {
      daoList = daoList
          .where((dao) => dao.status == ToolStatusType.RUNNING)
          .toList();
    }
    logger.log(
      LogModule.tool,
      "list.result",
      detail: "count: ${daoList.length}",
      level: Level.FINE,
    );
    final models = <ToolModel>[];
    for (final dao in daoList) {
      models.add(await _toModelWithContentState(dao));
    }
    return models;
  }

  Future<ToolModel> get(String toolId) async {
    logger.log(LogModule.tool, "get.input", detail: "toolId: $toolId");
    ToolDao? toolDao = await _cacheToolStorage.get(toolId);
    if (toolDao == null) throw ToolNotFoundException(toolId);
    logger.log(LogModule.tool, "get.result", detail: "toolId: $toolId");
    return _toModelWithContentState(toolDao);
  }

  Future<int> repairServerAssociations(List<ServerModel> servers) async {
    final serversById = {for (final server in servers) server.id: server};
    final serversByIdentity = <ServerIdentity, List<ServerModel>>{};
    for (final server in servers) {
      serversByIdentity.putIfAbsent(server.identity, () => []).add(server);
    }

    int repaired = 0;
    for (final tool in await _cacheToolStorage.list()) {
      final referencedServer = serversById[tool.serverId];
      if (referencedServer != null) {
        if (_materializationService != null) {
          final snapshot = _snapshotIdentity(tool);
          if (snapshot != referencedServer.identity) {
            _applyIdentitySnapshot(tool, referencedServer.identity);
            await _cacheToolStorage.update(tool);
            repaired++;
          }
          continue;
        }
        final snapshot = _snapshotIdentity(tool);
        final identity =
            snapshot ??
            await _readWorkspaceIdentity(tool.id) ??
            referencedServer.identity;
        var changed = snapshot == null;
        if (identity != referencedServer.identity) {
          final matches = serversByIdentity[identity] ?? const <ServerModel>[];
          if (matches.length == 1) {
            tool.serverId = matches.single.id;
            changed = true;
          }
        }
        if (changed) {
          _applyIdentitySnapshot(tool, identity);
          await _cacheToolStorage.update(tool);
          repaired++;
        }
        continue;
      }

      final identity =
          _snapshotIdentity(tool) ?? await _readWorkspaceIdentity(tool.id);
      if (identity == null) continue;
      final matches = serversByIdentity[identity] ?? const <ServerModel>[];
      if (matches.length != 1) {
        logger.log(
          LogModule.tool,
          "repairServerAssociations.ambiguous",
          detail:
              "toolId: ${tool.id}, identity: $identity, matches: ${matches.length}",
          level: Level.WARNING,
        );
        continue;
      }

      tool.serverId = matches.single.id;
      _applyIdentitySnapshot(tool, identity);
      await _cacheToolStorage.update(tool);
      repaired++;
      logger.log(
        LogModule.tool,
        "repairServerAssociations.repaired",
        detail: "toolId: ${tool.id}, serverId: ${tool.serverId}",
      );
    }
    return repaired;
  }

  /// Returns the single daemon-managed tool for a logical server identity.
  Future<ToolModel> runServer(
    ServerModel server,
    String hostType, {
    List<String>? extraCmds,
    void Function(String script, String output)? onStdout,
    void Function(String script, String error)? onStderr,
    bool printStd = true,
  }) {
    final key = server.id;
    final existingFlight = _runFlights[key];
    if (existingFlight != null) return existingFlight;

    late Future<ToolModel> flight;
    flight =
        _runServerLocked(
          server,
          hostType,
          extraCmds: extraCmds,
          onStdout: onStdout,
          onStderr: onStderr,
          printStd: printStd,
        ).whenComplete(() {
          if (identical(_runFlights[key], flight)) {
            _runFlights.remove(key);
          }
        });
    _runFlights[key] = flight;
    return flight;
  }

  Future<ToolModel> _runServerLocked(
    ServerModel requestedServer,
    String hostType, {
    List<String>? extraCmds,
    void Function(String script, String output)? onStdout,
    void Function(String script, String error)? onStderr,
    required bool printStd,
  }) async {
    final server = await _refreshServer(requestedServer);
    final identity = server.identity;
    logger.log(
      LogModule.tool,
      "runServer.input",
      detail:
          "serverId: ${server.id}, identity: $identity, versionDigest: ${server.versionDigest}, artifactId: ${server.artifactId}, artifactDigest: ${server.artifactDigest}, hostType: $hostType",
    );

    final servers = await _serverLister?.call();
    if (servers != null) await repairServerAssociations(servers);

    final matching =
        (await _cacheToolStorage.list())
            .where((tool) => _toolMatchesServer(tool, server))
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));

    for (final tool in matching.where(
      (tool) => tool.status == ToolStatusType.RUNNING,
    )) {
      if (await _isHealthy(tool)) {
        logger.log(
          LogModule.tool,
          "runServer.reuseRunning",
          detail: "toolId: ${tool.id}, identity: $identity",
        );
        return ToolModel.fromDao(tool);
      }
    }

    if (matching.isNotEmpty) {
      final tool = matching.first;
      await startTool(
        ToolModel.fromDao(tool),
        onStdout: onStdout,
        onStderr: onStderr,
        printStd: printStd,
      );
      return get(tool.id);
    }

    final toolId = uniqueId();
    final toolDao = ToolDao(
      id: toolId,
      alias: toolId,
      tag: server.version,
      host: hostType,
      port: preferredPortForNewTool(),
      apiKey: uniqueId(shorter: false),
      status: ToolStatusType.NOT_RUNNING,
      serverId: server.id,
      extraCmds: extraCmds == null || extraCmds.isEmpty
          ? null
          : List<String>.from(extraCmds),
    );
    _applyIdentitySnapshot(toolDao, identity);
    await _cacheToolStorage.add(toolDao);
    final materializer = _materializationService;
    if (materializer != null) {
      try {
        await materializer.ensureMaterialized(toolDao, server);
      } catch (_) {
        await _cacheToolStorage.remove(toolId);
        await DirectoryUtil.deleteDirectory(
          p.join(OPENTOOL_PATH, TOOL_FOLDER, toolId),
        );
        rethrow;
      }
    } else {
      final otsFilePath = server.artifactFilePath;
      if (otsFilePath == null) {
        throw StateError('Server artifact is unavailable: ${server.id}');
      }
      final tempFolder = await ZipUtil.unzipToTemp(otsFilePath);
      final toolFolder =
          "$OPENTOOL_PATH${Platform.pathSeparator}$TOOL_FOLDER${Platform.pathSeparator}$toolId";
      await DirectoryUtil.copyDirectory(
        Directory(tempFolder),
        Directory(toolFolder),
      );
      await DirectoryUtil.deleteDirectory(tempFolder);
      toolDao.materializedArtifactDigest = server.artifactDigest;
      await _cacheToolStorage.update(toolDao);
    }

    await _startToolSingleFlight(
      ToolModel.fromDao(toolDao),
      ToolLifecycleEventReason.CREATED,
      onStdout: onStdout,
      onStderr: onStderr,
      printStd: printStd,
    );
    final result = await get(toolId);
    logger.log(
      LogModule.tool,
      "runServer.result",
      detail: "toolId: $toolId, port: ${result.port}",
    );
    return result;
  }

  /// Starts one existing tool process at most once for concurrent callers.
  Future<void> startTool(
    ToolModel tool, {
    void Function(String script, String output)? onStdout,
    void Function(String script, String error)? onStderr,
    bool printStd = true,
  }) => _startToolSingleFlight(
    tool,
    ToolLifecycleEventReason.STARTED,
    onStdout: onStdout,
    onStderr: onStderr,
    printStd: printStd,
  );

  Future<void> _startToolSingleFlight(
    ToolModel tool,
    String readyReason, {
    void Function(String script, String output)? onStdout,
    void Function(String script, String error)? onStderr,
    required bool printStd,
  }) {
    final requestEpoch = _lifecycleRequestEpochs[tool.id] ?? 0;
    final existingFlight = _startFlights[tool.id];
    if (existingFlight != null && existingFlight.epoch == requestEpoch) {
      return existingFlight.future;
    }

    late Future<void> flight;
    flight =
        _withLifecycleLock(tool.id, () {
          _ensureCurrentLifecycleRequestEpoch(tool.id, requestEpoch);
          return _startToolLocked(
            tool.id,
            readyReason,
            onStdout: onStdout,
            onStderr: onStderr,
            printStd: printStd,
          );
        }).whenComplete(() {
          if (identical(_startFlights[tool.id]?.future, flight)) {
            _startFlights.remove(tool.id);
          }
        });
    _startFlights[tool.id] = _StartFlight(requestEpoch, flight);
    return flight;
  }

  Future<void> _startToolLocked(
    String toolId,
    String readyReason, {
    void Function(String script, String output)? onStdout,
    void Function(String script, String error)? onStderr,
    required bool printStd,
  }) async {
    var toolDao = await _cacheToolStorage.get(toolId);
    if (toolDao == null) throw ToolNotFoundException(toolId);
    logger.log(LogModule.tool, "startTool.input", detail: "toolId: $toolId");

    if (await _isHealthy(toolDao)) {
      if (toolDao.status != ToolStatusType.RUNNING) {
        toolDao.status = ToolStatusType.RUNNING;
        await _cacheToolStorage.update(toolDao);
        _emitLifecycleEvent(
          ToolLifecycleEventType.READY,
          readyReason,
          ToolModel.fromDao(toolDao),
        );
      }
      logger.log(
        LogModule.tool,
        "startTool.reuseRunning",
        detail: "toolId: $toolId",
      );
      return;
    }

    final serverId = toolDao.serverId;
    if (_materializationService != null &&
        serverId != null &&
        _serverGetter != null) {
      final server = await _serverGetter(serverId);
      await _materializationService.ensureMaterialized(toolDao, server);
      toolDao = (await _cacheToolStorage.get(toolId))!;
    }

    final generation = _nextLifecycleGeneration(toolId);
    int? reservedPort;
    try {
      if (toolDao.status == ToolStatusType.RUNNING) {
        await _prepareUnhealthyToolForRestart(toolDao);
        toolDao = (await _cacheToolStorage.get(toolId))!;
      }

      toolDao.status = ToolStatusType.STARTING;
      await _cacheToolStorage.update(toolDao);
      _emitLifecycleEvent(
        ToolLifecycleEventType.STARTING,
        readyReason,
        ToolModel.fromDao(toolDao),
      );

      final toolFolder =
          "$OPENTOOL_PATH${Platform.pathSeparator}$TOOL_FOLDER${Platform.pathSeparator}$toolId";
      final opentoolFileJsonPath =
          "$toolFolder${Platform.pathSeparator}$OPENTOOL_FILE_JSON_NAME";
      final opentoolFileJson = await JsonFileUtil.readFromFile(
        opentoolFileJsonPath,
      );
      final rawConfig = OpentoolfileConfig.fromJson(opentoolFileJson);
      final config = OpentoolfileConfigUtil.resolve(rawConfig);
      final workdir = _resolveWorkdir(toolFolder, config.run.workdir);
      final entrypoint = ExecutableUtil.resolveEntrypoint(
        workdir,
        config.run.entrypoint,
      );
      final commands = List<String>.from(config.run.cmds);
      if (toolDao.extraCmds != null) commands.addAll(toolDao.extraCmds!);
      commands.add("--$CLI_ARGUMENT_TAG ${toolDao.tag}");
      commands.add("--$CLI_ARGUMENT_HOST ${toolDao.host}");
      final port = await _allocateAndReservePort(toolDao.host, toolDao.port);
      reservedPort = port;
      commands.add("--$CLI_ARGUMENT_PORT $port");
      commands.add("--$CLI_ARGUMENT_APIKEYS ${toolDao.apiKey}");

      _ensureCurrentGeneration(toolId, generation);
      toolDao.port = port;
      toolDao.status = ToolStatusType.STARTING;
      await _cacheToolStorage.update(toolDao);
      _clients.remove(toolId);
      _registerClient(toolDao);

      await ExecutableUtil.ensureExecutable(entrypoint, workdir);
      final processFuture = _processLauncher(
        workdir,
        entrypoint,
        commands,
        onStdout,
        onStderr,
        printStd,
      );
      unawaited(
        processFuture.then<void>(
          (_) => _handleProcessExit(toolId, generation),
          onError: (Object error, StackTrace stackTrace) => _handleProcessExit(
            toolId,
            generation,
            error: error,
            stackTrace: stackTrace,
          ),
        ),
      );

      await _waitUntilReady(toolId, generation);
      _ensureCurrentGeneration(toolId, generation);
      final current = await _cacheToolStorage.get(toolId);
      if (current == null) throw ToolNotFoundException(toolId);
      _ensureCurrentGeneration(toolId, generation);
      current.status = ToolStatusType.RUNNING;
      await _cacheToolStorage.update(current);
      _ensureCurrentGeneration(toolId, generation);
      _clients[toolId] ??= _clientFactory(current);
      _emitLifecycleEvent(
        ToolLifecycleEventType.READY,
        readyReason,
        ToolModel.fromDao(current),
      );
      logger.log(
        LogModule.tool,
        "startTool.result",
        detail: "toolId: $toolId, port: $port",
      );
    } catch (error, stackTrace) {
      if (_isCurrentGeneration(toolId, generation)) {
        final current = await _cacheToolStorage.get(toolId);
        if (current != null) {
          current.status = ToolStatusType.NOT_RUNNING;
          await _cacheToolStorage.update(current);
          _clients.remove(toolId);
          _emitLifecycleEvent(
            ToolLifecycleEventType.UNAVAILABLE,
            ToolLifecycleEventReason.HEALTHCHECK_FAILED,
            ToolModel.fromDao(current),
          );
        }
        _invalidateGeneration(toolId, generation);
      }
      logger.log(
        LogModule.tool,
        "startTool.error",
        detail: "toolId: $toolId, error: $error\n$stackTrace",
        level: Level.WARNING,
      );
      rethrow;
    } finally {
      if (reservedPort != null) {
        await _portReservationAllocator.release(reservedPort);
      }
    }
  }

  Future<int> _allocateAndReservePort(String host, int startPort) =>
      _portReservationAllocator.allocateAndReserve(host, startPort);

  /// Verifies the tool process is alive by calling its /version endpoint.
  Future<void> check(String toolId) async {
    await _checkThenRun(toolId, (client) async {
      Version version = await client.version();
      logger.log(
        LogModule.tool,
        "check.version",
        detail: "toolId: $toolId version: ${version.version}",
      );
    });
  }

  Future<void> stop(String toolId) {
    _advanceLifecycleRequestEpoch(toolId);
    return _withLifecycleLock(toolId, () => _stopLocked(toolId));
  }

  Future<void> _stopLocked(String toolId) async {
    logger.log(LogModule.tool, "stop.input", detail: "toolId: $toolId");
    final toolDao = await _cacheToolStorage.get(toolId);
    if (toolDao == null) throw ToolNotFoundException(toolId);
    final generation = _nextLifecycleGeneration(toolId);
    toolDao.status = ToolStatusType.STOPPING;
    await _cacheToolStorage.update(toolDao);
    _emitLifecycleEvent(
      ToolLifecycleEventType.DRAINING,
      ToolLifecycleEventReason.STOP_REQUESTED,
      ToolModel.fromDao(toolDao),
    );
    final client = _clients[toolId] ?? _registerClient(toolDao);
    try {
      await _stopWithTimeout(client);
    } on OpenToolServerNoAccessException {
      // An unreachable process is already stopped from the daemon's view.
    } on SocketException {
      // An unreachable process is already stopped from the daemon's view.
    }
    _ensureCurrentGeneration(toolId, generation);
    final current = await _cacheToolStorage.get(toolId);
    if (current == null) throw ToolNotFoundException(toolId);
    _ensureCurrentGeneration(toolId, generation);
    current.status = ToolStatusType.NOT_RUNNING;
    await _cacheToolStorage.update(current);
    _ensureCurrentGeneration(toolId, generation);
    _clients.remove(toolId);
    logger.log(LogModule.tool, "stop.result", detail: "toolId: $toolId");
  }

  Future<void> delete(String toolId) {
    _cancelStartRequests(toolId);
    return _withLifecycleLock(toolId, () => _deleteLocked(toolId));
  }

  Future<void> _deleteLocked(String toolId) async {
    logger.log(LogModule.tool, "delete.input", detail: "toolId: $toolId");
    final existingToolDao = await _cacheToolStorage.get(toolId);
    final previousStatus =
        existingToolDao?.status ?? ToolStatusType.NOT_RUNNING;
    final shouldStop =
        existingToolDao != null && previousStatus != ToolStatusType.NOT_RUNNING;
    final generation = _nextLifecycleGeneration(toolId);
    if (existingToolDao != null) {
      existingToolDao.status = ToolStatusType.STOPPING;
      await _cacheToolStorage.update(existingToolDao);
      _emitLifecycleEvent(
        ToolLifecycleEventType.DRAINING,
        ToolLifecycleEventReason.DELETE_REQUESTED,
        ToolModel.fromDao(existingToolDao),
      );
    }
    OpenToolClient? client = _clients.remove(toolId);
    if (shouldStop) {
      final toolDao = existingToolDao;
      client ??= _clientFactory(toolDao);
      try {
        await _stopWithTimeout(client);
      } catch (error) {
        logger.log(
          LogModule.tool,
          "delete.stop.error",
          detail: "toolId: $toolId, error: $error",
          level: Level.WARNING,
        );
      }

      if (!await _waitForPortAvailable(toolDao.host, toolDao.port)) {
        toolDao.status = previousStatus;
        await _cacheToolStorage.update(toolDao);
        throw ArtifactOperationException(
          code: 'TOOL_STOP_TIMEOUT',
          message:
              'Tool $toolId did not release '
              '${toolDao.host}:${toolDao.port}',
          retryable: true,
        );
      }
    }

    _ensureCurrentGeneration(toolId, generation);
    final String toolFolder = p.join(OPENTOOL_PATH, TOOL_FOLDER, toolId);
    try {
      await _directoryDeleter(toolFolder);
    } on FileSystemException catch (error, stackTrace) {
      if (existingToolDao != null) {
        existingToolDao.status = ToolStatusType.NOT_RUNNING;
        await _cacheToolStorage.update(existingToolDao);
      }
      final locked = DirectoryUtil.isRetryableWindowsDeleteError(error);
      logger.log(
        LogModule.tool,
        "delete.workspace.error",
        detail: "toolId: $toolId, error: $error\n$stackTrace",
        level: Level.WARNING,
      );
      throw ArtifactOperationException(
        code: locked ? 'TOOL_DELETE_LOCKED' : 'TOOL_DELETE_FAILED',
        message: locked
            ? 'Tool files are in use by another process'
            : 'Tool files could not be deleted',
        retryable: locked,
      );
    }

    _ensureCurrentGeneration(toolId, generation);
    if (existingToolDao != null) {
      await _cacheToolStorage.remove(toolId);
      _ensureCurrentGeneration(toolId, generation);
      _emitLifecycleEvent(
        ToolLifecycleEventType.REMOVED,
        ToolLifecycleEventReason.DELETED,
        ToolModel.fromDao(existingToolDao),
      );
    }
    logger.log(LogModule.tool, "delete.result", detail: "toolId: $toolId");
  }

  Future<ToolReturn> call(String toolId, FunctionCall functionCall) async {
    logger.log(
      LogModule.tool,
      "call.input",
      detail: "toolId: $toolId, function: ${functionCall.name}",
    );
    ToolReturn? toolReturn = await _checkThenRun<ToolReturn?>(toolId, (
      client,
    ) async {
      ToolReturn? toolReturn = await client.call(functionCall);
      return toolReturn;
    });
    logger.log(LogModule.tool, "call.result", detail: "toolId: $toolId");
    return toolReturn ??
        ToolReturn(id: functionCall.id, result: {"result": null});
  }

  Future<void> streamCall(
    String toolId,
    FunctionCall functionCall,
    void Function(String event, ToolReturn toolReturn) onToolReturn,
  ) async {
    logger.log(
      LogModule.tool,
      "streamCall.input",
      detail: "toolId: $toolId, function: ${functionCall.name}",
    );
    await _checkThenRun(toolId, (client) async {
      await client.streamCall(functionCall, onToolReturn);
    });
  }

  Future<OpenTool?> load(String toolId) async {
    logger.log(LogModule.tool, "load.input", detail: "toolId: $toolId");
    OpenTool? tool = await _checkThenRun(toolId, (client) async {
      OpenTool? tool = await client.load();
      return tool;
    });
    logger.log(
      LogModule.tool,
      "load.result",
      detail: "toolId: $toolId, loaded: ${tool != null}",
    );
    return tool;
  }

  Future<void> setAlias(String toolId, String newAlias) async {
    logger.log(
      LogModule.tool,
      "setAlias.input",
      detail: "toolId: $toolId, alias: $newAlias",
    );
    await _checkThenRun(toolId, (client) async {
      ToolDao? toolDao = await _cacheToolStorage.get(toolId);
      if (toolDao == null) throw ToolNotFoundException(toolId);
      toolDao.alias = newAlias;
      await _cacheToolStorage.update(toolDao);
    });
    logger.log(
      LogModule.tool,
      "setAlias.result",
      detail: "toolId: $toolId, alias: $newAlias",
    );
  }

  Future<T> _checkThenRun<T>(
    String toolId,
    Future<T> Function(OpenToolClient client) onRun,
  ) async {
    logger.log(LogModule.tool, "check.input", detail: "toolId: $toolId");
    ToolDao? toolDao = await _cacheToolStorage.get(toolId);
    if (toolDao == null) {
      logger.log(LogModule.tool, "check.missing", detail: "toolId: $toolId");
      throw ToolNotFoundException(toolId);
    }
    OpenToolClient client = _clients[toolId] ?? _registerClient(toolDao);
    try {
      return await onRun(client);
    } catch (error, stackTrace) {
      logger.log(
        LogModule.tool,
        "check.error",
        detail: "toolId: $toolId, error: $error\n$stackTrace",
      );
      rethrow;
    }
  }

  Future<ServerModel> _refreshServer(ServerModel requested) async {
    final getter = _serverGetter;
    if (getter != null) {
      try {
        return await getter(requested.id);
      } catch (_) {
        // A same-version native sync may have repaired the catalog. Resolve by
        // logical identity before giving up on the caller's stale id.
      }
    }
    final lister = _serverLister;
    if (lister != null) {
      final matches = (await lister())
          .where((server) => server.identity == requested.identity)
          .toList();
      if (matches.length == 1) return matches.single;
    }
    return requested;
  }

  bool _toolMatchesServer(ToolDao tool, ServerModel server) {
    return tool.serverId == server.id;
  }

  Future<ToolModel> _toModelWithContentState(ToolDao dao) async {
    final model = ToolModel.fromDao(dao);
    final manifest = File(
      p.join(OPENTOOL_PATH, TOOL_FOLDER, dao.id, OPENTOOL_FILE_JSON_NAME),
    );
    if (!await manifest.exists()) {
      model.contentState = 'broken';
      return model;
    }
    final serverId = dao.serverId;
    if (serverId == null || _serverGetter == null) {
      model.contentState = dao.materializedArtifactDigest == null
          ? 'unknown'
          : 'current';
      return model;
    }
    try {
      final server = await _serverGetter(serverId);
      if (server.state == 'broken') {
        model.contentState = 'broken';
      } else if (dao.materializedArtifactDigest == null) {
        model.contentState = 'unknown';
      } else if (dao.materializedArtifactDigest == server.artifactDigest) {
        model.contentState = 'current';
      } else {
        model.contentState = 'updatePending';
      }
    } catch (_) {
      model.contentState = 'broken';
    }
    return model;
  }

  ServerIdentity? _snapshotIdentity(ToolDao tool) {
    final registry = tool.serverRegistry;
    final namespace = tool.serverNamespace;
    final name = tool.serverName;
    final version = tool.serverVersion;
    if (registry == null ||
        namespace == null ||
        name == null ||
        version == null) {
      return null;
    }
    return ServerIdentity(
      registry: registry,
      namespace: namespace,
      name: name,
      version: version,
    );
  }

  void _applyIdentitySnapshot(ToolDao tool, ServerIdentity identity) {
    tool.serverRegistry = identity.registry;
    tool.serverNamespace = identity.namespace;
    tool.serverName = identity.name;
    tool.serverVersion = identity.version;
  }

  Future<ServerIdentity?> _readWorkspaceIdentity(String toolId) async {
    final jsonPath = p.join(
      OPENTOOL_PATH,
      TOOL_FOLDER,
      toolId,
      OPENTOOL_FILE_JSON_NAME,
    );
    final file = File(jsonPath);
    if (!await file.exists()) return null;
    try {
      final json = await JsonFileUtil.readFromFile(jsonPath);
      final config = OpentoolfileConfig.fromJson(json);
      return ServerIdentity(
        registry: NULL_REGISTRY,
        namespace: LOCAL_NAMESPACE,
        name: config.name,
        version: config.tag ?? NULL_TAG,
      );
    } catch (error, stackTrace) {
      logger.log(
        LogModule.tool,
        "repairServerAssociations.workspaceError",
        detail: "toolId: $toolId, error: $error\n$stackTrace",
        level: Level.WARNING,
      );
      return null;
    }
  }

  Future<bool> _isHealthy(ToolDao toolDao) async {
    final client = _clients[toolDao.id] ?? _registerClient(toolDao);
    try {
      await _versionWithTimeout(client);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _prepareUnhealthyToolForRestart(ToolDao toolDao) async {
    final client = _clients[toolDao.id] ?? _registerClient(toolDao);
    try {
      await _stopWithTimeout(client);
    } catch (_) {
      // Readiness already failed. The port check below is the authoritative
      // guard against starting a second process.
    }
    _clients.remove(toolDao.id);
    if (!await _waitForPortAvailable(toolDao.host, toolDao.port)) {
      throw ToolRestartConflictException(
        toolDao.id,
        'existing process did not release ${toolDao.host}:${toolDao.port}',
      );
    }
    toolDao.status = ToolStatusType.NOT_RUNNING;
    await _cacheToolStorage.update(toolDao);
  }

  Future<bool> _waitForPortAvailable(String host, int port) async {
    final stopwatch = Stopwatch()..start();
    while (true) {
      if (await _portAvailability(host, port)) return true;
      if (stopwatch.elapsed >= _stopCheckTimeout) return false;
      await Future<void>.delayed(_stopCheckInterval);
    }
  }

  Future<void> _handleProcessExit(
    String toolId,
    int generation, {
    Object? error,
    StackTrace? stackTrace,
  }) => _withLifecycleLock(toolId, () async {
    if (!_isCurrentGeneration(toolId, generation)) return;
    final toolDao = await _cacheToolStorage.get(toolId);
    if (toolDao == null || !_isCurrentGeneration(toolId, generation)) return;
    toolDao.status = ToolStatusType.NOT_RUNNING;
    await _cacheToolStorage.update(toolDao);
    if (!_isCurrentGeneration(toolId, generation)) return;
    _clients.remove(toolId);
    _emitLifecycleEvent(
      ToolLifecycleEventType.UNAVAILABLE,
      ToolLifecycleEventReason.HEALTHCHECK_FAILED,
      ToolModel.fromDao(toolDao),
    );
    logger.log(
      LogModule.tool,
      "tool.processExited",
      detail: "toolId: $toolId, error: $error\n$stackTrace",
      level: Level.WARNING,
    );
  });

  OpenToolClient _registerClient(ToolDao toolDao) {
    final client = _clientFactory(toolDao);
    _clients[toolDao.id] = client;
    return client;
  }

  Future<void> _waitUntilReady(String toolId, int generation) async {
    final stopwatch = Stopwatch()..start();
    while (true) {
      _ensureCurrentGeneration(toolId, generation);
      final toolDao = await _cacheToolStorage.get(toolId);
      if (toolDao == null) throw ToolNotFoundException(toolId);
      _ensureCurrentGeneration(toolId, generation);
      final client = _clients[toolId] ?? _registerClient(toolDao);
      try {
        await _versionWithTimeout(client);
        _ensureCurrentGeneration(toolId, generation);
        return;
      } on OpenToolServerUnauthorizedException {
        final listeningPids = await findListeningProcessIds(toolDao.port);
        final conflict = ToolEndpointConflictException(
          toolId: toolId,
          host: toolDao.host,
          port: toolDao.port,
          listeningPids: listeningPids,
        );
        logger.log(
          LogModule.tool,
          'readyCheck.endpointConflict',
          detail: conflict.toString(),
          level: Level.WARNING,
        );
        throw conflict;
      } catch (_) {
        _ensureCurrentGeneration(toolId, generation);
        if (stopwatch.elapsed >= _readyCheckTimeout) rethrow;
        await Future<void>.delayed(_readyCheckInterval);
      }
    }
  }

  Future<T> _withLifecycleLock<T>(String toolId, Future<T> Function() action) =>
      _lifecycleLocks.putIfAbsent(toolId, _AsyncMutex.new).run(action);

  Future<Version> _versionWithTimeout(OpenToolClient client) =>
      client.version().timeout(_lifecycleRequestTimeout);

  Future<StatusInfo?> _stopWithTimeout(OpenToolClient client) =>
      client.stop().timeout(_lifecycleRequestTimeout);

  int _nextLifecycleGeneration(String toolId) {
    final generation = (_lifecycleGenerations[toolId] ?? 0) + 1;
    _lifecycleGenerations[toolId] = generation;
    return generation;
  }

  void _advanceLifecycleRequestEpoch(String toolId) {
    _lifecycleRequestEpochs[toolId] =
        (_lifecycleRequestEpochs[toolId] ?? 0) + 1;
  }

  void _cancelStartRequests(String toolId) {
    _advanceLifecycleRequestEpoch(toolId);
    final generation = _lifecycleGenerations[toolId];
    if (generation != null) {
      _lifecycleGenerations[toolId] = generation + 1;
    }
  }

  void _ensureCurrentLifecycleRequestEpoch(String toolId, int epoch) {
    if ((_lifecycleRequestEpochs[toolId] ?? 0) != epoch) {
      throw _LifecycleRequestSupersededException(toolId, epoch);
    }
  }

  bool _isCurrentGeneration(String toolId, int generation) =>
      _lifecycleGenerations[toolId] == generation;

  void _ensureCurrentGeneration(String toolId, int generation) {
    if (!_isCurrentGeneration(toolId, generation)) {
      throw _LifecycleSupersededException(toolId, generation);
    }
  }

  void _invalidateGeneration(String toolId, int generation) {
    if (_isCurrentGeneration(toolId, generation)) {
      _lifecycleGenerations[toolId] = generation + 1;
    }
  }

  void _emitLifecycleEvent(String type, String reason, ToolModel tool) {
    if (_eventController.isClosed) return;
    _eventController.add(
      ToolLifecycleEventModel(
        type: type,
        reason: reason,
        tool: tool,
        occurredAt: DateTime.now().toUtc(),
      ),
    );
  }

  OpenToolClient _buildClient(ToolDao toolDao) {
    final String resolvedHost =
        toolDao.host.isEmpty || toolDao.host == HostType.ANY
        ? HostType.LOCALHOST
        : toolDao.host;
    final client = OpenToolClient(
      toolHost: resolvedHost,
      toolPort: toolDao.port,
      toolApiKey: toolDao.apiKey,
    );
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == '/version' || options.path == '/stop') {
            options
              ..connectTimeout = _lifecycleRequestTimeout
              ..sendTimeout = _lifecycleRequestTimeout
              ..receiveTimeout = _lifecycleRequestTimeout;
          }
          handler.next(options);
        },
      ),
    );
    return client;
  }

  String _resolveWorkdir(String baseFolder, String configuredWorkdir) {
    if (configuredWorkdir.isEmpty || configuredWorkdir == '.') {
      return baseFolder;
    }
    final String candidate = p.normalize(p.join(baseFolder, configuredWorkdir));
    if (Directory(candidate).existsSync()) {
      return candidate;
    }
    return baseFolder;
  }
}

class _AsyncMutex {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    return previous.then((_) => action()).whenComplete(() {
      if (!release.isCompleted) release.complete();
    });
  }
}

class _StartFlight {
  final int epoch;
  final Future<void> future;

  const _StartFlight(this.epoch, this.future);
}

class _LifecycleSupersededException implements Exception {
  final String toolId;
  final int generation;

  const _LifecycleSupersededException(this.toolId, this.generation);

  @override
  String toString() =>
      'Tool lifecycle operation superseded: $toolId generation $generation';
}

class _LifecycleRequestSupersededException implements Exception {
  final String toolId;
  final int epoch;

  const _LifecycleRequestSupersededException(this.toolId, this.epoch);

  @override
  String toString() =>
      'Tool lifecycle request superseded: $toolId request epoch $epoch';
}
