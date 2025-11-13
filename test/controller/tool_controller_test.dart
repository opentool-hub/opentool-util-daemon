import 'dart:convert';
import 'package:opentool_daemon/src/controller/tool_controller.dart';
import 'package:opentool_daemon/src/service/model.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import '../test_doubles.dart';

void main() {
  group('ToolController', () {
    late FakeToolService toolService;
    late FakeServerService serverService;
    late ToolController controller;

    setUp(() {
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
      controller = ToolController(toolService, serverService);
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
  });
}
