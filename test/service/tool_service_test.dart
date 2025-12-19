import 'package:opentool_daemon/src/service/exception.dart';
import 'package:opentool_daemon/src/service/model.dart';
import 'package:opentool_daemon/src/service/tool_service.dart';
import 'package:opentool_daemon/src/storage/dao.dart';
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
