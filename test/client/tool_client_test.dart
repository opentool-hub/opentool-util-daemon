import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:opentool_daemon/opentool_daemon_client.dart';
import 'package:test/test.dart';
import 'dio_stub.dart';

void main() {
  group('DaemonClient tool APIs', () {
    test('listTool forwards the `all` query flag', () async {
      RequestOptions? captured;
      final stub = createStubDio({
        'GET /list': (options) {
          captured = options;
          return [
            {
              'id': 'tool-1',
              'alias': 'alpha',
              'tag': '1.0.0',
              'host': '127.0.0.1',
              'port': 9000,
              'apiKey': 'key-1',
              'status': 'running',
              'serverId': 'server-1',
              'server': {
                'namespace': 'hub/opentool',
                'name': 'demo',
                'version': '1.0.0',
              },
            },
          ];
        },
      });

      final client = DaemonClient();
      client.toolDio = stub;

      final tools = await client.listTool('1');

      expect(captured?.queryParameters['all'], equals('1'));
      expect(tools.single.id, equals('tool-1'));
      expect(tools.single.server?.namespace, equals('hub/opentool'));
      expect(tools.single.server?.name, equals('demo'));
      expect(tools.single.server?.version, equals('1.0.0'));
    });

    test('listToolWithApiKeys sets daemon api key header', () async {
      RequestOptions? captured;
      final stub = createStubDio({
        'GET /listWithApiKeys': (options) {
          captured = options;
          return [
            {
              'id': 'tool-1',
              'alias': 'alpha',
              'tag': '1.0.0',
              'host': '127.0.0.1',
              'port': 9000,
              'apiKey': 'key-1',
              'status': 'running',
              'serverId': 'server-1',
              'server': {
                'namespace': 'hub/opentool',
                'name': 'demo',
                'version': '1.0.0',
              },
            },
          ];
        },
      });

      final client = DaemonClient();
      client.toolDio = stub;

      final tools = await client.listToolWithApiKeys(
        '1',
        daemonApiKey: 'admin',
      );

      expect(captured?.queryParameters['all'], equals('1'));
      expect(captured?.headers['x-opentool-api-key'], equals('admin'));
      expect(tools.single.apiKey, equals('key-1'));
      expect(tools.single.server?.namespace, equals('hub/opentool'));
      expect(tools.single.server?.name, equals('demo'));
      expect(tools.single.server?.version, equals('1.0.0'));
    });

    test('subscribeToolEvents sends the host management token', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      String? capturedToken;
      String? capturedSnapshot;
      final serving = server.listen((request) async {
        capturedToken = request.headers.value(HOST_MANAGEMENT_TOKEN_HEADER);
        capturedSnapshot = request.uri.queryParameters['snapshot'];
        await request.drain<void>();
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          'event:ready\ndata:{"message":"subscribed"}\n\n',
        );
        await request.response.close();
      });
      try {
        final client = DaemonClient(
          host: server.address.host,
          port: server.port,
        );
        final events = await client.subscribeToolEvents(
          hostToken: 'desktop-host-token',
          snapshot: false,
        );

        expect(await events.toList(), isEmpty);
        expect(capturedToken, equals('desktop-host-token'));
        expect(capturedSnapshot, equals('0'));
      } finally {
        await server.close(force: true);
        await serving.cancel();
      }
    });

    test('setAliasTool posts the alias as a query parameter', () async {
      RequestOptions? captured;
      final stub = createStubDio({
        'POST /tool-1/alias': (options) {
          captured = options;
          return {
            'id': 'tool-1',
            'alias': options.queryParameters['alias'],
            'tag': '1.0.0',
            'host': '127.0.0.1',
            'port': 9000,
            'apiKey': 'key-1',
            'status': 'running',
          };
        },
      });

      final client = DaemonClient();
      client.toolDio = stub;

      final dto = await client.setAliasTool('tool-1', 'gamma');

      expect(captured?.queryParameters['alias'], equals('gamma'));
      expect(dto.alias, equals('gamma'));
    });

    test('stopTool hits the stop endpoint and parses the id DTO', () async {
      RequestOptions? captured;
      final stub = createStubDio({
        'POST /tool-1/stop': (options) {
          captured = options;
          return {'id': 'tool-1'};
        },
      });

      final client = DaemonClient();
      client.toolDio = stub;

      final dto = await client.stopTool('tool-1');

      expect(captured?.method, equals('POST'));
      expect(dto.id, equals('tool-1'));
    });

    test('startTool waits for terminal DONE', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final releaseDone = Completer<void>();
      final serving = server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          'event:data\ndata:{"command":"startTool","output":"starting"}\n\n',
        );
        await request.response.flush();
        await releaseDone.future;
        request.response.write(
          'event:done\ndata:{"command":"startTool","output":"ready"}\n\n',
        );
        await request.response.close();
      });
      try {
        final client = DaemonClient(
          host: server.address.host,
          port: server.port,
        );
        final output = <String?>[];
        var completed = false;
        final start = client
            .startTool(
              'tool-1',
              onData: (result) => output.add(result.output),
              onError: (_) {},
            )
            .then((_) => completed = true);

        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(completed, isFalse);
        releaseDone.complete();
        await start;

        expect(output, ['starting']);
        expect(completed, isTrue);
      } finally {
        if (!releaseDone.isCompleted) releaseDone.complete();
        await server.close(force: true);
        await serving.cancel();
      }
    });

    test('startTool handles ERROR as a terminal failure', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serving = server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          'event:error\ndata:{"command":"startTool","error":"boom"}\n\n',
        );
        await request.response.close();
      });
      try {
        final client = DaemonClient(
          host: server.address.host,
          port: server.port,
        );
        CommandResultDto? callbackError;
        Object? streamError;

        await expectLater(
          client.startTool(
            'tool-1',
            onData: (_) {},
            onError: (error) => callbackError = error,
            onStreamError: (error, _) => streamError = error,
          ),
          throwsA(
            isA<DaemonApiException>().having(
              (error) => error.code,
              'code',
              'TOOL_START_FAILED',
            ),
          ),
        );
        expect(callbackError?.error, 'boom');
        expect(streamError, isNull);
      } finally {
        await server.close(force: true);
        await serving.cancel();
      }
    });

    test('startTool rejects a stream that closes before terminal', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serving = server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          'event:data\ndata:{"command":"startTool","output":"starting"}\n\n',
        );
        await request.response.close();
      });
      try {
        final client = DaemonClient(
          host: server.address.host,
          port: server.port,
        );

        await expectLater(
          client.startTool('tool-1', onData: (_) {}, onError: (_) {}),
          throwsA(isA<SseProtocolException>()),
        );
      } finally {
        await server.close(force: true);
        await serving.cancel();
      }
    });
  });
}
