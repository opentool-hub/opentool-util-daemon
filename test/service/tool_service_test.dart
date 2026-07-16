import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:opentool_daemon/src/constants.dart';
import 'package:opentool_daemon/src/service/config.dart';
import 'package:opentool_daemon/src/service/exception.dart';
import 'package:opentool_daemon/src/service/model.dart';
import 'package:opentool_daemon/src/service/tool_service.dart';
import 'package:opentool_daemon/src/storage/dao.dart';
import 'package:opentool_daemon/src/utils/zip_util.dart';
import 'package:opentool_dart/opentool_client.dart';
import 'package:test/test.dart';
import '../test_doubles.dart';

void main() {
  group('ToolService', () {
    late StubHiveToolStorage hiveToolStorage;
    late ToolService service;

    setUp(() {
      hiveToolStorage = StubHiveToolStorage();
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
      'call marks tool NOT_RUNNING for OpenToolServerNoAccessException',
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
        expect(tool!.status, equals(ToolStatusType.NOT_RUNNING));
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

    test('call emits unavailable when the tool becomes unreachable', () async {
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
      expect(events, hasLength(1));
      expect(events.single.type, equals(ToolLifecycleEventType.UNAVAILABLE));
      expect(
        events.single.reason,
        equals(ToolLifecycleEventReason.HEALTHCHECK_FAILED),
      );
    });

    group('logical server idempotency', () {
      late Directory tempDir;
      late String originalOpenToolPath;
      late StubHiveToolStorage storage;
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
        storage = StubHiveToolStorage();
        clients = {};
        processStarts = 0;
        idempotentService = ToolService(
          storage,
          clientFactory: (tool) => clients.putIfAbsent(
            tool.id,
            () => _MutableHealthClient(healthy: true),
          ),
          portAllocator: (_, startPort) async => startPort,
          portAvailability: (_, _) async => true,
          processLauncher: (_, _, _, _, _, _) {
            processStarts++;
            return Completer<int>().future;
          },
        );
        server = ServerModel(
          id: 'server-current',
          alias: 'server-current',
          registry: NULL_REGISTRY,
          repo: NULL_REPO,
          name: 'demo-tool',
          tag: '1.0.0',
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
          tag: server.tag,
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
        expect(restored.serverTag, server.tag);
      });

      test(
        'workspace version prevents a retagged server misassociation',
        () async {
          final retagged = ServerModel(
            id: 'server-retagged',
            alias: 'server-retagged',
            registry: server.registry,
            repo: server.repo,
            name: server.name,
            tag: '2.0.0',
            internalId: server.internalId,
          );
          final legacy = ToolDao(
            id: 'tool-old-version',
            alias: 'tool-old-version',
            tag: server.tag,
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
          expect(restored.serverTag, server.tag);
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
    if (healthyAfterStop) healthy = true;
    return null;
  }
}

ToolDao _toolDao(String id, ServerModel server, String status) => ToolDao(
  id: id,
  alias: id,
  tag: server.tag,
  host: HostType.LOCALHOST,
  port: 9010,
  apiKey: 'key-$id',
  status: status,
  serverId: server.id,
  serverRegistry: server.registry,
  serverRepo: server.repo,
  serverName: server.name,
  serverTag: server.tag,
);

Future<void> _writeServerBundle(ServerModel server) async {
  final source = await Directory.systemTemp.createTemp('tool_bundle_');
  try {
    await _writeConfigAndEntrypoint(source.path, server);
    final target =
        '$OPENTOOL_PATH/$SERVER_FOLDER/${server.name}-${server.internalId}.ots';
    await ZipUtil.zipDirectory(source.path, target);
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
    tag: server.tag,
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
