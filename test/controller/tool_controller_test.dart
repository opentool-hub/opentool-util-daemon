import 'dart:convert';
import 'dart:io';
import 'package:opentool_daemon/src/constants.dart';
import 'package:opentool_daemon/src/controller/tool_controller.dart';
import 'package:opentool_daemon/src/service/config.dart';
import 'package:opentool_daemon/src/service/manage_service.dart';
import 'package:opentool_daemon/src/service/model.dart';
import 'package:opentool_dart/opentool_client.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import '../test_doubles.dart';

void main() {
  group('ToolController', () {
    late FakeToolService toolService;
    late FakeServerService serverService;
    late ManageService manageService;
    late String adminApiKey;
    late Directory tempDir;
    late ToolController controller;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tool_controller');
      toolService = FakeToolService(
        initialTools: [
          ToolModel(
            id: 'tool-1',
            alias: 'alpha',
            tag: '1.0.0',
            host: '127.0.0.1',
            port: 9000,
            apiKey: 'key-1',
            status: ToolStatusType.RUNNING,
          ),
          ToolModel(
            id: 'tool-2',
            alias: 'beta',
            tag: '1.0.0',
            host: '127.0.0.1',
            port: 9001,
            apiKey: 'key-2',
            status: ToolStatusType.NOT_RUNNING,
          ),
        ],
        toolReturns: {
          'tool-1': ToolReturn(id: 'call-1', result: {'marker': 'from-tool'}),
        },
      );
      serverService = FakeServerService(
        initialServers: [
          ServerModel(
            id: 'tool-1',
            alias: 'alpha',
            registry: 'hub.local',
            repo: 'hub/opentool',
            name: 'demo',
            tag: '1.0.0',
            internalId: 'int-1',
          ),
        ],
      );
      final apiKeyStorage = InMemoryApiKeyStorage();
      manageService = ManageService(
        'test',
        dataDir: tempDir.path,
        apiKeyStorage: apiKeyStorage,
      );
      manageService.currConfig = OpenToolConfig();
      adminApiKey = (await manageService.createApiKey(name: 'ops')).apiKey;
      controller = ToolController(toolService, serverService, manageService);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('listTools respects the `all` query parameter', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/opentool-daemon/tools/list?all=1'),
      );

      final response = await controller.listTools(request);
      final decoded =
          jsonDecode(await response.readAsString()) as List<dynamic>;

      expect(decoded, hasLength(2));
      expect(decoded.first['alias'], equals('alpha'));
    });

    test('listToolsWithApiKeys enforces daemon api key validation', () async {
      final authedRequest = Request(
        'GET',
        Uri.parse(
          'http://localhost/opentool-daemon/tools/listWithApiKeys?all=1',
        ),
        headers: {TOOL_API_KEY_HEADER: adminApiKey},
      );
      final authedResponse = await controller.listToolsWithApiKeys(
        authedRequest,
      );
      expect(authedResponse.statusCode, equals(200));
      final decoded =
          jsonDecode(await authedResponse.readAsString()) as List<dynamic>;
      expect(decoded.first['apiKey'], equals('key-1'));

      final unauthorizedRequest = Request(
        'GET',
        Uri.parse('http://localhost/opentool-daemon/tools/listWithApiKeys'),
      );
      final unauthorizedResponse = await controller.listToolsWithApiKeys(
        unauthorizedRequest,
      );
      expect(unauthorizedResponse.statusCode, equals(403));
    });

    test('subscribeToolEvents requires daemon api key', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/opentool-daemon/tools/events'),
      );

      final response = await controller.subscribeToolEvents(request);

      expect(response.statusCode, equals(403));
    });

    test('subscribeToolEvents streams snapshot and lifecycle events', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/opentool-daemon/tools/events?snapshot=1'),
        headers: {TOOL_API_KEY_HEADER: adminApiKey},
      );

      final response = await controller.subscribeToolEvents(request);
      final chunks = <String>[];
      final sub = response.read().transform(utf8.decoder).listen(chunks.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      toolService.emitEvent(
        ToolLifecycleEventModel(
          type: ToolLifecycleEventType.DRAINING,
          reason: ToolLifecycleEventReason.STOP_REQUESTED,
          tool: await toolService.get('tool-1'),
          occurredAt: DateTime.utc(2026, 3, 7, 0, 0, 1),
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();
      final body = chunks.join();

      expect(body, contains('event:ready'));
      expect(body, contains('event:tool.snapshot'));
      expect(body, contains('"reason":"snapshot"'));
      expect(body, contains('event:tool.draining'));
      expect(body, contains('"reason":"stop_requested"'));
    });

    test('stopTool delegates to the service and returns the id DTO', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/opentool-daemon/tools/tool-1/stop'),
      );

      final response = await controller.stopTool(request, 'tool-1');
      final decoded =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;

      expect(decoded['id'], equals('tool-1'));
      expect(toolService.lastStoppedId, equals('tool-1'));
    });

    test('setAlias updates the tool alias and echoes it back', () async {
      final request = Request(
        'POST',
        Uri.parse(
          'http://localhost/opentool-daemon/tools/tool-1/alias?alias=gamma',
        ),
      );

      final response = await controller.setAlias(request, 'tool-1');
      final decoded =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;

      expect(decoded['alias'], equals('gamma'));
      final tool = await toolService.get('tool-1');
      expect(tool.alias, equals('gamma'));
    });

    test('streamCallTool streams tool return payloads', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/opentool-daemon/tools/tool-1/streamCall'),
        body: jsonEncode({'id': 'call-1', 'name': 'count', 'arguments': {}}),
      );

      final response = await controller.streamCallTool(request, 'tool-1');
      final body = await response.readAsString();

      expect(body, contains('event:${EventType.DATA}'));
      expect(body, contains('"marker":"from-tool"'));
      expect(body, isNot(contains('"name":"count"')));
    });
  });
}
