import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:opentool_daemon/src/constants.dart';
import 'package:opentool_daemon/src/service/config.dart';
import 'package:opentool_daemon/src/service/exception.dart';
import 'package:opentool_daemon/src/service/model.dart';
import 'package:opentool_daemon/src/service/tool_service.dart';
import 'package:opentool_daemon/src/storage/dao.dart';
import 'package:opentool_daemon/src/utils/port_reservation_allocator.dart';
import 'package:opentool_daemon/src/utils/zip_util.dart';
import 'package:opentool_dart/opentool_client.dart';
import 'package:test/test.dart';
import '../test_doubles.dart';

void main() {
  group('ToolService', () {
    late MemoryToolStorage hiveToolStorage;
    late ToolService service;

    setUp(() {
      hiveToolStorage = MemoryToolStorage();
      hiveToolStorage.seed([
        ToolDao(
          id: 'tool-1',
          alias: 'alpha',
          tag: '1.0.0',
          host: '127.0.0.1',
          port: 9000,
          apiKey: 'key-1',
          status: ToolStatusType.RUNNING,
        ),
        ToolDao(
          id: 'tool-2',
          alias: 'beta',
          tag: '1.0.0',
          host: '127.0.0.1',
          port: 9001,
          apiKey: 'key-2',
          status: ToolStatusType.NOT_RUNNING,
        ),
      ]);
      service = ToolService(hiveToolStorage);
    });

    test('list only returns running tools by default', () async {
      final tools = await service.list();

      expect(tools, hasLength(1));
      expect(tools.single.id, equals('tool-1'));
    });

    test('list with all=true returns every tool', () async {
      final tools = await service.list(all: true);

      expect(tools, hasLength(2));
    });

    test('get returns the requested tool', () async {
      final tool = await service.get('tool-1');

      expect(tool.alias, equals('alpha'));
      expect(tool.apiKey, equals('key-1'));
    });

    test('get throws ToolNotFoundException for unknown ids', () async {
      expect(
        () => service.get('missing'),
        throwsA(isA<ToolNotFoundException>()),
      );
    });

    test('new tool port allocation always starts from the default port', () {
      expect(preferredPortForNewTool(), equals(9010));
    });

    test(
      'refreshStatusesOnStartup marks unreachable tools as NOT_RUNNING',
      () async {
        service = ToolService(
          hiveToolStorage,
          clientFactory: (toolDao) =>
              _TestOpenToolClient(reachable: toolDao.id == 'tool-1'),
        );

        await service.refreshStatusesOnStartup();

        final running = await hiveToolStorage.get('tool-1');
        final stopped = await hiveToolStorage.get('tool-2');

        expect(running!.status, equals(ToolStatusType.RUNNING));
        expect(stopped!.status, equals(ToolStatusType.NOT_RUNNING));
      },
    );

    test(
      'call does not mark tool NOT_RUNNING for OpenToolServerCallException',
      () async {
        service = ToolService(
          hiveToolStorage,
          clientFactory: (_) =>
              _ThrowingCallClient(OpenToolServerCallException('boom')),
        );

        await expectLater(
          service.call(
            'tool-1',
            FunctionCall(id: 'call-1', name: 'count', arguments: const {}),
          ),
          throwsA(isA<OpenToolServerCallException>()),
        );

        final tool = await hiveToolStorage.get('tool-1');
        expect(tool!.status, equals(ToolStatusType.RUNNING));
      },
    );

    test(
      'call keeps lifecycle state unchanged for OpenToolServerNoAccessException',
      () async {
        service = ToolService(
          hiveToolStorage,
          clientFactory: (_) =>
              _ThrowingCallClient(OpenToolServerNoAccessException()),
        );

        await expectLater(
          service.call(
            'tool-1',
            FunctionCall(id: 'call-1', name: 'count', arguments: const {}),
          ),
          throwsA(isA<OpenToolServerNoAccessException>()),
        );

        final tool = await hiveToolStorage.get('tool-1');
        expect(tool!.status, equals(ToolStatusType.RUNNING));
      },
    );

    test('stop emits draining before marking the tool not running', () async {
      service = ToolService(
        hiveToolStorage,
        clientFactory: (_) => _StoppingClient(),
      );
      final events = <ToolLifecycleEventModel>[];
      final subscription = service.events.listen(events.add);

      await service.stop('tool-1');

      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(events, hasLength(1));
      expect(events.single.type, equals(ToolLifecycleEventType.DRAINING));
      expect(
        events.single.reason,
        equals(ToolLifecycleEventReason.STOP_REQUESTED),
      );
      final tool = await hiveToolStorage.get('tool-1');
      expect(tool!.status, equals(ToolStatusType.NOT_RUNNING));
    });

    test('call does not emit lifecycle events for a request failure', () async {
      service = ToolService(
        hiveToolStorage,
        clientFactory: (_) =>
            _ThrowingCallClient(OpenToolServerNoAccessException()),
      );
      final events = <ToolLifecycleEventModel>[];
      final subscription = service.events.listen(events.add);

      await expectLater(
        service.call(
          'tool-1',
          FunctionCall(id: 'call-1', name: 'count', arguments: const {}),
        ),
        throwsA(isA<OpenToolServerNoAccessException>()),
      );

      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(events, isEmpty);
    });

    group('logical server idempotency', () {
      late Directory tempDir;
      late String originalOpenToolPath;
      late MemoryToolStorage storage;
      late ToolService idempotentService;
      late ServerModel server;
      late Map<String, _MutableHealthClient> clients;
      late int processStarts;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('tool_idempotency_');
        originalOpenToolPath = OPENTOOL_PATH;
        OPENTOOL_PATH = '${tempDir.path}/.opentool';
        await Directory(
          '$OPENTOOL_PATH/$SERVER_FOLDER',
        ).create(recursive: true);
        await Directory('$OPENTOOL_PATH/$TOOL_FOLDER').create(recursive: true);
        storage = MemoryToolStorage();
        clients = {};
        processStarts = 0;
        idempotentService = ToolService(
          storage,
          clientFactory: (tool) => clients.putIfAbsent(
            tool.id,
            () => _MutableHealthClient(healthy: false),
          ),
          portAllocator: (_, startPort) async => startPort,
          portAvailability: (_, _) async => true,
          processLauncher: (_, _, _, _, _, _) {
            processStarts++;
            for (final client in clients.values) {
              client.healthy = true;
            }
            return Completer<int>().future;
          },
        );
        server = ServerModel(
          id: 'server-current',
          alias: 'server-current',
          registry: NULL_REGISTRY,
          namespace: NULL_REPO,
          name: 'demo-tool',
          version: '1.0.0',
          internalId: 'internal-1',
        );
        await _writeServerBundle(server);
      });

      tearDown(() async {
        OPENTOOL_PATH = originalOpenToolPath;
        await tempDir.delete(recursive: true);
      });

      test('sequential runServer calls reuse one tool and process', () async {
        final first = await idempotentService.runServer(
          server,
          HostType.LOCALHOST,
        );
        final second = await idempotentService.runServer(
          server,
          HostType.LOCALHOST,
        );

        expect(second.id, first.id);
        expect(await storage.list(), hasLength(1));
        expect(processStarts, 1);
      });

      test('concurrent runServer calls share workspace and process', () async {
        final results = await Future.wait(
          List.generate(
            8,
            (_) => idempotentService.runServer(server, HostType.LOCALHOST),
          ),
        );

        expect(results.map((tool) => tool.id).toSet(), hasLength(1));
        expect(await storage.list(), hasLength(1));
        expect(processStarts, 1);
        final workspaces = await Directory(
          '$OPENTOOL_PATH/$TOOL_FOLDER',
        ).list().where((entry) => entry is Directory).length;
        expect(workspaces, 1);
      });

      test(
        'healthy running tool is returned without a process start',
        () async {
          storage.seed([
            _toolDao('tool-running', server, ToolStatusType.RUNNING),
          ]);
          clients['tool-running'] = _MutableHealthClient(healthy: true);

          final result = await idempotentService.runServer(
            server,
            HostType.LOCALHOST,
          );

          expect(result.id, 'tool-running');
          expect(processStarts, 0);
          expect(await storage.list(), hasLength(1));
        },
      );

      test('stopped tool is restarted with the same id', () async {
        storage.seed([
          _toolDao('tool-stopped', server, ToolStatusType.NOT_RUNNING),
        ]);
        await _writeToolWorkspace('tool-stopped', server);

        final result = await idempotentService.runServer(
          server,
          HostType.LOCALHOST,
        );

        expect(result.id, 'tool-stopped');
        expect(result.status, ToolStatusType.RUNNING);
        expect(processStarts, 1);
        expect(await storage.list(), hasLength(1));
      });

      test(
        'unhealthy running tool reuses its id instead of duplicating',
        () async {
          storage.seed([
            _toolDao('tool-unhealthy', server, ToolStatusType.RUNNING),
          ]);
          await _writeToolWorkspace('tool-unhealthy', server);
          clients['tool-unhealthy'] = _MutableHealthClient(
            healthy: false,
            healthyAfterStop: true,
          );

          final result = await idempotentService.runServer(
            server,
            HostType.LOCALHOST,
          );

          expect(result.id, 'tool-unhealthy');
          expect(processStarts, 1);
          expect(await storage.list(), hasLength(1));
        },
      );

      test(
        'unhealthy running tool fails instead of starting beside it',
        () async {
          final dao = _toolDao('tool-conflict', server, ToolStatusType.RUNNING);
          storage.seed([dao]);
          clients['tool-conflict'] = _MutableHealthClient(healthy: false);
          idempotentService = ToolService(
            storage,
            clientFactory: (tool) => clients.putIfAbsent(
              tool.id,
              () => _MutableHealthClient(healthy: true),
            ),
            portAllocator: (_, startPort) async => startPort,
            portAvailability: (_, _) async => false,
            processLauncher: (_, _, _, _, _, _) {
              processStarts++;
              return Completer<int>().future;
            },
          );

          await expectLater(
            idempotentService.runServer(server, HostType.LOCALHOST),
            throwsA(isA<ToolRestartConflictException>()),
          );

          expect(processStarts, 0);
          expect(await storage.list(), hasLength(1));
          expect((await storage.get(dao.id))!.id, dao.id);
        },
      );

      test('concurrent startTool calls start one process', () async {
        final dao = _toolDao('tool-start', server, ToolStatusType.NOT_RUNNING);
        storage.seed([dao]);
        await _writeToolWorkspace(dao.id, server);

        await Future.wait([
          idempotentService.startTool(ToolModel.fromDao(dao)),
          idempotentService.startTool(ToolModel.fromDao(dao)),
        ]);

        expect(processStarts, 1);
        expect((await storage.get(dao.id))!.status, ToolStatusType.RUNNING);
      });

      test(
        'different runServer calls reserve distinct ports until ready',
        () async {
          final otherServer = ServerModel(
            id: 'server-other',
            alias: 'server-other',
            registry: NULL_REGISTRY,
            namespace: NULL_REPO,
            name: 'other-tool',
            version: '1.0.0',
            internalId: 'internal-other',
          );
          await _writeServerBundle(otherServer);
          final allocator = PortReservationAllocator(
            (_, startPort) async => startPort,
          );
          final clients = <String, _StartupGateClient>{};
          final registrations = <String, int>{};
          final launchedPorts = <int>[];
          final bothLaunched = Completer<void>();
          final concurrentService = ToolService(
            storage,
            portReservationAllocator: allocator,
            clientFactory: (tool) {
              final client = clients.putIfAbsent(
                tool.id,
                _StartupGateClient.new,
              );
              final count = (registrations[tool.id] ?? 0) + 1;
              registrations[tool.id] = count;
              if (count > 1) client.starting = true;
              return client;
            },
            processLauncher: (_, _, commands, _, _, _) {
              launchedPorts.add(_commandPort(commands));
              if (launchedPorts.length == 2) bothLaunched.complete();
              return Completer<int>().future;
            },
          );

          final first = concurrentService.runServer(server, HostType.LOCALHOST);
          final second = concurrentService.runServer(
            otherServer,
            HostType.LOCALHOST,
          );
          await bothLaunched.future;

          expect(launchedPorts..sort(), [9010, 9011]);
          expect(allocator.isReserved(9010), isTrue);
          expect(allocator.isReserved(9011), isTrue);

          for (final client in clients.values) {
            client.readiness.complete(Version(version: '1.0.0'));
          }
          final tools = await Future.wait([first, second]);

          expect(tools.map((tool) => tool.port).toSet(), {9010, 9011});
          expect(allocator.isReserved(9010), isFalse);
          expect(allocator.isReserved(9011), isFalse);
        },
      );

      test(
        'runServer skips a port reserved by an in-flight startTool',
        () async {
          final existing = _toolDao(
            'tool-existing-start',
            server,
            ToolStatusType.NOT_RUNNING,
          );
          storage.seed([existing]);
          await _writeToolWorkspace(existing.id, server);
          final otherServer = ServerModel(
            id: 'server-concurrent-run',
            alias: 'server-concurrent-run',
            registry: NULL_REGISTRY,
            namespace: NULL_REPO,
            name: 'concurrent-run-tool',
            version: '1.0.0',
            internalId: 'internal-concurrent-run',
          );
          await _writeServerBundle(otherServer);
          final allocator = PortReservationAllocator(
            (_, startPort) async => startPort,
          );
          final clients = <String, _StartupGateClient>{};
          final registrations = <String, int>{};
          final launchedPorts = <int>[];
          final firstLaunched = Completer<void>();
          final secondLaunched = Completer<void>();
          final concurrentService = ToolService(
            storage,
            portReservationAllocator: allocator,
            clientFactory: (tool) {
              final client = clients.putIfAbsent(
                tool.id,
                _StartupGateClient.new,
              );
              final count = (registrations[tool.id] ?? 0) + 1;
              registrations[tool.id] = count;
              if (count > 1) client.starting = true;
              return client;
            },
            processLauncher: (_, _, commands, _, _, _) {
              launchedPorts.add(_commandPort(commands));
              if (launchedPorts.length == 1) firstLaunched.complete();
              if (launchedPorts.length == 2) secondLaunched.complete();
              return Completer<int>().future;
            },
          );

          final start = concurrentService.startTool(
            ToolModel.fromDao(existing),
          );
          await firstLaunched.future;
          expect(allocator.isReserved(9010), isTrue);

          final run = concurrentService.runServer(
            otherServer,
            HostType.LOCALHOST,
          );
          await secondLaunched.future;

          expect(launchedPorts, [9010, 9011]);
          final runDao = (await storage.list()).singleWhere(
            (tool) => tool.serverId == otherServer.id,
          );
          expect(runDao.port, 9011);

          for (final client in clients.values) {
            client.readiness.complete(Version(version: '1.0.0'));
          }
          await Future.wait<void>([start, run.then((_) {})]);
        },
      );

      test('startTool skips an unavailable port and updates ToolDao', () async {
        final dao = _toolDao(
          'tool-port-fallback',
          server,
          ToolStatusType.NOT_RUNNING,
        );
        storage.seed([dao]);
        await _writeToolWorkspace(dao.id, server);
        final client = _MutableHealthClient(healthy: false);
        final launchedPorts = <int>[];
        final fallbackService = ToolService(
          storage,
          clientFactory: (_) => client,
          portAllocator: (_, startPort) async =>
              startPort == 9010 ? 9011 : startPort,
          processLauncher: (_, _, commands, _, _, _) {
            launchedPorts.add(_commandPort(commands));
            client.healthy = true;
            return Completer<int>().future;
          },
        );

        await fallbackService.startTool(ToolModel.fromDao(dao));

        expect(launchedPorts, [9011]);
        expect((await storage.get(dao.id))!.port, 9011);
      });

      test('launch failure releases the reservation for a retry', () async {
        final dao = _toolDao(
          'tool-launch-retry',
          server,
          ToolStatusType.NOT_RUNNING,
        );
        storage.seed([dao]);
        await _writeToolWorkspace(dao.id, server);
        final allocatedStarts = <int>[];
        final allocator = PortReservationAllocator((_, startPort) async {
          allocatedStarts.add(startPort);
          return startPort;
        });
        final client = _MutableHealthClient(healthy: false);
        var failLaunch = true;
        final retryService = ToolService(
          storage,
          portReservationAllocator: allocator,
          clientFactory: (_) => client,
          processLauncher: (_, _, _, _, _, _) {
            if (failLaunch) throw StateError('launch failed');
            client.healthy = true;
            return Completer<int>().future;
          },
        );

        await expectLater(
          retryService.startTool(ToolModel.fromDao(dao)),
          throwsStateError,
        );
        expect(allocator.isReserved(9010), isFalse);

        failLaunch = false;
        await retryService.startTool(ToolModel.fromDao(dao));

        expect(allocatedStarts, [9010, 9010]);
        expect((await storage.get(dao.id))!.port, 9010);
      });

      test('readiness timeout releases the reservation', () async {
        final dao = _toolDao(
          'tool-readiness-timeout',
          server,
          ToolStatusType.NOT_RUNNING,
        );
        storage.seed([dao]);
        await _writeToolWorkspace(dao.id, server);
        final allocator = PortReservationAllocator(
          (_, startPort) async => startPort,
        );
        final timeoutService = ToolService(
          storage,
          portReservationAllocator: allocator,
          clientFactory: (_) => _MutableHealthClient(healthy: false),
          processLauncher: (_, _, _, _, _, _) => Completer<int>().future,
          readyCheckTimeout: Duration.zero,
        );

        await expectLater(
          timeoutService.startTool(ToolModel.fromDao(dao)),
          throwsA(anything),
        );

        expect(allocator.isReserved(9010), isFalse);
        expect((await storage.get(dao.id))!.status, ToolStatusType.NOT_RUNNING);
      });

      test('start persists starting before running', () async {
        final recordingStorage = _RecordingToolStorage();
        final dao = _toolDao(
          'tool-state-transition',
          server,
          ToolStatusType.NOT_RUNNING,
        );
        recordingStorage.seed([dao]);
        await _writeToolWorkspace(dao.id, server);
        final client = _MutableHealthClient(healthy: false);
        final lifecycleService = ToolService(
          recordingStorage,
          clientFactory: (_) => client,
          portAllocator: (_, startPort) async => startPort,
          processLauncher: (_, _, _, _, _, _) {
            client.healthy = true;
            return Completer<int>().future;
          },
        );

        await lifecycleService.startTool(ToolModel.fromDao(dao));

        expect(recordingStorage.statuses, contains(ToolStatusType.STARTING));
        expect(recordingStorage.statuses.last, ToolStatusType.RUNNING);
        final tools = await lifecycleService.list(all: true);
        expect(tools.single.id, dao.id);
        expect(tools.single.status, ToolStatusType.RUNNING);
      });

      test('load failure during startup cannot overwrite starting', () async {
        final dao = _toolDao(
          'tool-load-during-start',
          server,
          ToolStatusType.NOT_RUNNING,
        );
        storage.seed([dao]);
        await _writeToolWorkspace(dao.id, server);
        final client = _ControlledLifecycleClient();
        final processLaunched = Completer<void>();
        final lifecycleService = ToolService(
          storage,
          clientFactory: (_) => client,
          portAllocator: (_, startPort) async => startPort,
          processLauncher: (_, _, _, _, _, _) {
            client.launched = true;
            processLaunched.complete();
            return Completer<int>().future;
          },
        );

        final startFuture = lifecycleService.startTool(ToolModel.fromDao(dao));
        await processLaunched.future;
        expect((await storage.get(dao.id))!.status, ToolStatusType.STARTING);

        final loadFuture = lifecycleService.load(dao.id);
        await client.loadAttempted.future;
        client.loadResult.completeError(const SocketException('not ready'));
        await expectLater(loadFuture, throwsA(isA<SocketException>()));
        expect((await storage.get(dao.id))!.status, ToolStatusType.STARTING);

        client.readiness.complete(Version(version: '1.0.0'));
        await startFuture;
        expect((await storage.get(dao.id))!.status, ToolStatusType.RUNNING);
      });

      test('late load failure cannot overwrite readiness success', () async {
        final dao = _toolDao(
          'tool-late-load-failure',
          server,
          ToolStatusType.NOT_RUNNING,
        );
        storage.seed([dao]);
        await _writeToolWorkspace(dao.id, server);
        final client = _ControlledLifecycleClient();
        final processLaunched = Completer<void>();
        final lifecycleService = ToolService(
          storage,
          clientFactory: (_) => client,
          portAllocator: (_, startPort) async => startPort,
          processLauncher: (_, _, _, _, _, _) {
            client.launched = true;
            processLaunched.complete();
            return Completer<int>().future;
          },
        );

        final startFuture = lifecycleService.startTool(ToolModel.fromDao(dao));
        await processLaunched.future;
        final loadFuture = lifecycleService.load(dao.id);
        await client.loadAttempted.future;
        client.readiness.complete(Version(version: '1.0.0'));
        await startFuture;
        client.loadResult.completeError(const SocketException('late failure'));
        await expectLater(loadFuture, throwsA(isA<SocketException>()));

        expect((await storage.get(dao.id))!.status, ToolStatusType.RUNNING);
      });

      test('notRunning but healthy tool is repaired without launch', () async {
        final dao = _toolDao(
          'tool-stale-status',
          server,
          ToolStatusType.NOT_RUNNING,
        );
        storage.seed([dao]);
        clients[dao.id] = _MutableHealthClient(healthy: true);

        await idempotentService.startTool(ToolModel.fromDao(dao));

        expect(processStarts, 0);
        expect((await storage.get(dao.id))!.status, ToolStatusType.RUNNING);
      });

      test(
        'stop completes before a queued start can publish running',
        () async {
          final dao = _toolDao(
            'tool-stop-start',
            server,
            ToolStatusType.RUNNING,
          );
          storage.seed([dao]);
          await _writeToolWorkspace(dao.id, server);
          final client = _DelayedStopClient();
          var starts = 0;
          final lifecycleService = ToolService(
            storage,
            clientFactory: (_) => client,
            portAllocator: (_, startPort) async => startPort,
            processLauncher: (_, _, _, _, _, _) {
              starts++;
              client.healthy = true;
              return Completer<int>().future;
            },
          );

          final stopFuture = lifecycleService.stop(dao.id);
          await client.stopStarted.future;
          expect((await storage.get(dao.id))!.status, ToolStatusType.STOPPING);
          final startFuture = lifecycleService.startTool(
            ToolModel.fromDao(dao),
          );
          await Future<void>.delayed(Duration.zero);
          expect(starts, 0);

          client.stopRelease.complete();
          await stopFuture;
          await startFuture;

          expect(starts, 1);
          expect((await storage.get(dao.id))!.status, ToolStatusType.RUNNING);
        },
      );

      test('start queued after stop does not reuse the older start', () async {
        final dao = _toolDao(
          'tool-start-stop-start',
          server,
          ToolStatusType.NOT_RUNNING,
        );
        storage.seed([dao]);
        await _writeToolWorkspace(dao.id, server);
        final client = _ControlledLifecycleClient();
        final firstLaunch = Completer<void>();
        var starts = 0;
        final lifecycleService = ToolService(
          storage,
          clientFactory: (_) => client,
          portAllocator: (_, startPort) async => startPort,
          processLauncher: (_, _, _, _, _, _) {
            starts++;
            client.launched = true;
            if (!firstLaunch.isCompleted) firstLaunch.complete();
            return Completer<int>().future;
          },
        );

        final firstStart = lifecycleService.startTool(ToolModel.fromDao(dao));
        await firstLaunch.future;
        final stopFuture = lifecycleService.stop(dao.id);
        final secondStart = lifecycleService.startTool(ToolModel.fromDao(dao));
        client.readiness.complete(Version(version: '1.0.0'));

        await firstStart;
        await stopFuture;
        await secondStart;

        expect(starts, 2);
        expect((await storage.get(dao.id))!.status, ToolStatusType.RUNNING);
      });

      test('old process exit cannot stop a newer generation', () async {
        final dao = _toolDao(
          'tool-old-process-exit',
          server,
          ToolStatusType.NOT_RUNNING,
        );
        storage.seed([dao]);
        await _writeToolWorkspace(dao.id, server);
        final client = _MutableHealthClient(healthy: false);
        final processExits = <Completer<int>>[];
        final lifecycleService = ToolService(
          storage,
          clientFactory: (_) => client,
          portAllocator: (_, startPort) async => startPort,
          processLauncher: (_, _, _, _, _, _) {
            client.healthy = true;
            final exit = Completer<int>();
            processExits.add(exit);
            return exit.future;
          },
        );

        await lifecycleService.startTool(ToolModel.fromDao(dao));
        await lifecycleService.stop(dao.id);
        await lifecycleService.startTool(ToolModel.fromDao(dao));
        expect(processExits, hasLength(2));

        processExits.first.complete(0);
        await Future<void>.delayed(Duration.zero);

        expect((await storage.get(dao.id))!.status, ToolStatusType.RUNNING);
      });

      test('failed startup returns to notRunning once', () async {
        final dao = _toolDao(
          'tool-start-failure',
          server,
          ToolStatusType.NOT_RUNNING,
        );
        storage.seed([dao]);
        await _writeToolWorkspace(dao.id, server);
        final lifecycleService = ToolService(
          storage,
          clientFactory: (_) => _MutableHealthClient(healthy: false),
          portAllocator: (_, startPort) async => startPort,
          processLauncher: (_, _, _, _, _, _) => Completer<int>().future,
          readyCheckInterval: const Duration(milliseconds: 1),
          readyCheckTimeout: const Duration(milliseconds: 5),
        );
        final events = <ToolLifecycleEventModel>[];
        final subscription = lifecycleService.events.listen(events.add);

        await expectLater(
          lifecycleService.startTool(ToolModel.fromDao(dao)),
          throwsA(anything),
        );
        await Future<void>.delayed(Duration.zero);
        await subscription.cancel();

        expect((await storage.get(dao.id))!.status, ToolStatusType.NOT_RUNNING);
        expect(
          events.where(
            (event) => event.type == ToolLifecycleEventType.UNAVAILABLE,
          ),
          hasLength(1),
        );
      });

      test('running status survives service restart reconciliation', () async {
        final dao = _toolDao(
          'tool-restart-persistence',
          server,
          ToolStatusType.NOT_RUNNING,
        );
        storage.seed([dao]);
        await _writeToolWorkspace(dao.id, server);
        final client = _MutableHealthClient(healthy: false);
        final lifecycleService = ToolService(
          storage,
          clientFactory: (_) => client,
          portAllocator: (_, startPort) async => startPort,
          processLauncher: (_, _, _, _, _, _) {
            client.healthy = true;
            return Completer<int>().future;
          },
        );
        await lifecycleService.startTool(ToolModel.fromDao(dao));

        final restartedService = ToolService(
          storage,
          clientFactory: (_) => _MutableHealthClient(healthy: true),
        );
        await restartedService.refreshStatusesOnStartup();

        expect((await storage.get(dao.id))!.status, ToolStatusType.RUNNING);
      });

      test('orphan association is restored from snapshot', () async {
        final orphan = _toolDao(
          'tool-orphan-snapshot',
          server,
          ToolStatusType.RUNNING,
        )..serverId = 'missing-server';
        storage.seed([orphan]);

        final repaired = await idempotentService.repairServerAssociations([
          server,
        ]);

        expect(repaired, 1);
        expect((await storage.get(orphan.id))!.serverId, server.id);
      });

      test('orphan association is restored from workspace metadata', () async {
        final orphan = ToolDao(
          id: 'tool-orphan-workspace',
          alias: 'tool-orphan-workspace',
          tag: server.version,
          host: HostType.LOCALHOST,
          port: 9010,
          apiKey: 'key',
          status: ToolStatusType.RUNNING,
          serverId: 'missing-server',
        );
        storage.seed([orphan]);
        await _writeToolWorkspace(orphan.id, server);

        final repaired = await idempotentService.repairServerAssociations([
          server,
        ]);

        final restored = (await storage.get(orphan.id))!;
        expect(repaired, 1);
        expect(restored.serverId, server.id);
        expect(restored.serverName, server.name);
        expect(restored.serverVersion, server.version);
      });

      test(
        'workspace version prevents a retagged server misassociation',
        () async {
          final retagged = ServerModel(
            id: 'server-retagged',
            alias: 'server-retagged',
            registry: server.registry,
            namespace: server.namespace,
            name: server.name,
            version: '2.0.0',
            internalId: server.internalId,
          );
          final legacy = ToolDao(
            id: 'tool-old-version',
            alias: 'tool-old-version',
            tag: server.version,
            host: HostType.LOCALHOST,
            port: 9010,
            apiKey: 'key',
            status: ToolStatusType.RUNNING,
            serverId: retagged.id,
          );
          storage.seed([legacy]);
          await _writeToolWorkspace(legacy.id, server);

          await idempotentService.repairServerAssociations([server, retagged]);

          final restored = (await storage.get(legacy.id))!;
          expect(restored.serverId, server.id);
          expect(restored.serverVersion, server.version);
        },
      );
    });
  });
}

class _TestOpenToolClient extends OpenToolClient {
  final bool reachable;

  _TestOpenToolClient({required this.reachable})
    : super(toolHost: '127.0.0.1', toolPort: 8080);

  @override
  Future<Version> version() async {
    if (!reachable) {
      throw OpenToolServerNoAccessException();
    }
    return Version(version: '0.0.0');
  }
}

class _ThrowingCallClient extends OpenToolClient {
  final Object error;

  _ThrowingCallClient(this.error)
    : super(toolHost: '127.0.0.1', toolPort: 8080);

  @override
  Future<ToolReturn> call(FunctionCall functionCall) async {
    throw error;
  }
}

class _StoppingClient extends OpenToolClient {
  _StoppingClient() : super(toolHost: '127.0.0.1', toolPort: 8080);

  @override
  Future<StatusInfo?> stop() async => null;
}

class _MutableHealthClient extends OpenToolClient {
  bool healthy;
  final bool healthyAfterStop;

  _MutableHealthClient({required this.healthy, this.healthyAfterStop = false})
    : super(toolHost: '127.0.0.1', toolPort: 9010);

  @override
  Future<Version> version() async {
    if (!healthy) throw OpenToolServerNoAccessException();
    return Version(version: '1.0.0');
  }

  @override
  Future<StatusInfo?> stop() async {
    healthy = healthyAfterStop;
    return null;
  }
}

class _ControlledLifecycleClient extends OpenToolClient {
  bool launched = false;
  final Completer<Version> readiness = Completer<Version>();
  final Completer<void> loadAttempted = Completer<void>();
  final Completer<OpenTool?> loadResult = Completer<OpenTool?>();

  _ControlledLifecycleClient() : super(toolHost: '127.0.0.1', toolPort: 9010);

  @override
  Future<Version> version() {
    if (!launched) {
      throw const SocketException('not launched');
    }
    return readiness.future;
  }

  @override
  Future<OpenTool?> load() {
    if (!loadAttempted.isCompleted) loadAttempted.complete();
    return loadResult.future;
  }

  @override
  Future<StatusInfo?> stop() async {
    launched = false;
    return null;
  }
}

class _StartupGateClient extends OpenToolClient {
  bool starting = false;
  final Completer<Version> readiness = Completer<Version>();

  _StartupGateClient()
    : super(toolHost: '127.0.0.1', toolPort: TOOL_DEFAULT_PORT);

  @override
  Future<Version> version() {
    if (!starting) throw const SocketException('not started');
    return readiness.future;
  }
}

class _DelayedStopClient extends OpenToolClient {
  bool healthy = true;
  final Completer<void> stopStarted = Completer<void>();
  final Completer<void> stopRelease = Completer<void>();

  _DelayedStopClient() : super(toolHost: '127.0.0.1', toolPort: 9010);

  @override
  Future<Version> version() async {
    if (!healthy) throw const SocketException('stopped');
    return Version(version: '1.0.0');
  }

  @override
  Future<StatusInfo?> stop() async {
    if (!stopStarted.isCompleted) stopStarted.complete();
    await stopRelease.future;
    healthy = false;
    return null;
  }
}

class _RecordingToolStorage extends MemoryToolStorage {
  final List<String> statuses = [];

  @override
  Future<void> update(ToolDao toolDao) async {
    statuses.add(toolDao.status);
    await super.update(toolDao);
  }
}

ToolDao _toolDao(String id, ServerModel server, String status) => ToolDao(
  id: id,
  alias: id,
  tag: server.version,
  host: HostType.LOCALHOST,
  port: 9010,
  apiKey: 'key-$id',
  status: status,
  serverId: server.id,
  serverRegistry: server.registry,
  serverNamespace: server.namespace,
  serverName: server.name,
  serverVersion: server.version,
);

Future<void> _writeServerBundle(ServerModel server) async {
  final source = await Directory.systemTemp.createTemp('tool_bundle_');
  try {
    await _writeConfigAndEntrypoint(source.path, server);
    final target =
        '$OPENTOOL_PATH/$SERVER_FOLDER/${server.name}-${server.internalId}.ots';
    await ZipUtil.zipDirectory(source.path, target);
    server.artifactFilePath = target;
  } finally {
    await source.delete(recursive: true);
  }
}

Future<void> _writeToolWorkspace(String toolId, ServerModel server) async {
  final path = '$OPENTOOL_PATH/$TOOL_FOLDER/$toolId';
  await _writeConfigAndEntrypoint(path, server);
}

Future<void> _writeConfigAndEntrypoint(String root, ServerModel server) async {
  final directory = Directory(root);
  await directory.create(recursive: true);
  final config = OpentoolfileConfig(
    name: server.name,
    tag: server.version,
    os: Platform.operatingSystem,
    cpuArch: 'test',
    build: OpenToolBuild(),
    run: OpenToolRun(workdir: 'dist', entrypoint: 'tool-bin'),
  );
  await File(
    '$root/$OPENTOOL_FILE_JSON_NAME',
  ).writeAsString(jsonEncode(config.toJson()));
  final entrypoint = File('$root/dist/tool-bin');
  await entrypoint.create(recursive: true);
  await entrypoint.writeAsString('#!/bin/sh\n');
}

int _commandPort(List<String> commands) {
  final prefix = '--$CLI_ARGUMENT_PORT ';
  final argument = commands.singleWhere(
    (command) => command.startsWith(prefix),
  );
  return int.parse(argument.substring(prefix.length));
}
