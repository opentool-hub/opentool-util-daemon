import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:opentool_daemon/src/controller/server_controller.dart';
import 'package:opentool_daemon/src/service/artifact_downloader.dart';
import 'package:opentool_daemon/src/service/hub_pull_service.dart';
import 'package:opentool_daemon/src/service/pull_cancellation.dart';
import 'package:opentool_daemon/src/service/model.dart';
import 'package:opentool_daemon/src/service/server_service.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import '../test_doubles.dart';

void main() {
  group('ServerController', () {
    late FakeServerService serverService;
    late ServerController controller;

    setUp(() {
      serverService = FakeServerService(
        initialServers: [
          ServerModel(
            id: 'srv-1',
            alias: 'srv-1',
            registry: 'hub.local',
            namespace: 'hub/opentool',
            name: 'demo-server',
            version: 'latest',
            internalId: 'int-1',
          ),
        ],
      );
      controller = ServerController(serverService);
    });

    test('listServers returns DTOs derived from the service models', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/opentool-daemon/servers/list'),
      );

      final response = await controller.listServers(request);
      final decoded =
          jsonDecode(await response.readAsString()) as List<dynamic>;

      expect(decoded, hasLength(1));
      expect(decoded.first['name'], equals('demo-server'));
      expect(decoded.first['version'], equals('latest'));
      expect(
        (decoded.first as Map<String, dynamic>).keys,
        unorderedEquals([
          'schemaVersion',
          'id',
          'alias',
          'registry',
          'namespace',
          'version',
          'name',
          'source',
          'policy',
          'capabilities',
          'state',
        ]),
      );
    });

    test('setAlias updates the server and returns the updated DTO', () async {
      final request = Request(
        'POST',
        Uri.parse(
          'http://localhost/opentool-daemon/servers/srv-1/alias?alias=web',
        ),
      );

      final response = await controller.setAlias(request, 'srv-1');
      final decoded =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;

      expect(decoded['alias'], equals('web'));
      final updated = await serverService.get('srv-1');
      expect(updated.alias, equals('web'));
    });

    test('deleteServer delegates to the service and echoes the id', () async {
      final request = Request(
        'DELETE',
        Uri.parse('http://localhost/opentool-daemon/servers/srv-1'),
      );

      final response = await controller.deleteServer(request, 'srv-1');
      final payload =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;

      expect(payload['id'], equals('srv-1'));
      expect(serverService.lastDeletedId, equals('srv-1'));
      expect(serverService.list(), completion(isEmpty));
    });

    test('pullServer returns SSE before the registration completes', () async {
      final release = Completer<void>();
      final hubService = _ControlledHubPullService(
        serverService,
        release.future,
      );
      controller = ServerController(serverService, hubPullService: hubService);
      final request = Request(
        'POST',
        Uri.parse('http://localhost/opentool-daemon/servers/pull'),
        body: jsonEncode({
          'registry': 'https://api.opentool-hub.com',
          'namespace': 'litevar',
          'name': 'demo',
          'version': '1.2.3',
          'client': 'embedded',
        }),
      );

      final response = await controller.pullServer(request);
      expect(response.statusCode, 200);
      final responseBody = response.readAsString();
      expect(release.isCompleted, isFalse);
      release.complete();

      final body = await responseBody;
      expect(body, contains('event:start'));
      expect(body, contains('event:done'));
      expect(body.indexOf('event:start'), lessThan(body.indexOf('event:done')));
    });

    test('pullServer rejects an invalid reference before SSE', () async {
      final hubService = _ControlledHubPullService(
        serverService,
        Future<void>.value(),
      );
      controller = ServerController(serverService, hubPullService: hubService);
      final response = await controller.pullServer(
        Request(
          'POST',
          Uri.parse('http://localhost/opentool-daemon/servers/pull'),
          body: jsonEncode({
            'registry': 'https://api.opentool-hub.com',
            'namespace': 'Lite Var',
            'name': 'demo',
            'version': 'latest',
          }),
        ),
      );

      expect(response.statusCode, 400);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final error = body['error'] as Map<String, dynamic>;
      expect(error['code'], 'INVALID_REQUEST');
      expect(error, isNot(contains('legacyCode')));
    });

    test(
      'pullServer cancels registration when the SSE client disconnects',
      () async {
        final release = Completer<void>();
        final hubService = _ControlledHubPullService(
          serverService,
          release.future,
        );
        controller = ServerController(
          serverService,
          hubPullService: hubService,
        );
        final response = await controller.pullServer(
          Request(
            'POST',
            Uri.parse('http://localhost/opentool-daemon/servers/pull'),
            body: jsonEncode({
              'registry': 'http://127.0.0.1:8080',
              'namespace': 'litevar',
              'name': 'demo',
              'version': '1.2.3',
              'client': 'embedded',
            }),
          ),
        );

        final firstChunk = Completer<void>();
        final subscription = response.read().listen((_) {
          if (!firstChunk.isCompleted) firstChunk.complete();
        });
        await firstChunk.future;
        await subscription.cancel();
        await expectLater(
          hubService.cancelled.future.timeout(const Duration(seconds: 1)),
          completes,
        );
        release.complete();
      },
    );
  });
}

class _ControlledHubPullService extends HubPullService {
  final Future<void> release;
  final Completer<void> cancelled = Completer<void>();

  _ControlledHubPullService(ServerService serverService, this.release)
    : super(
        serverService: serverService,
        daemonVersion: 'test',
        downloader: ArtifactDownloader(dataDir: Directory.systemTemp.path),
      );

  @override
  Future<ServerModel> pull(
    HubPullRequest request, {
    required void Function(PullEvent event) onEvent,
    PullCancellationToken? cancellation,
  }) async {
    cancellation?.onCancel(() {
      if (!cancelled.isCompleted) cancelled.complete();
    });
    onEvent(PullEvent('start', {'stage': 'resolving', 'ref': request.ref}));
    await release;
    final server = ServerModel(
      id: 'ready',
      alias: 'demo',
      registry: request.registry,
      namespace: request.namespace,
      name: request.name,
      version: request.version,
      internalId: 'internal',
    );
    onEvent(
      const PullEvent('done', {
        'stage': 'ready',
        'server': {'id': 'ready'},
      }),
    );
    return server;
  }
}
