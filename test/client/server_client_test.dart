import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:opentool_daemon/opentool_daemon_client.dart';
import 'package:test/test.dart';
import 'dio_stub.dart';

void main() {
  group('DaemonClient server APIs', () {
    test('listServer fetches and parses server DTOs', () async {
      RequestOptions? captured;
      final stub = createStubDio({
        'GET /list': (options) {
          captured = options;
          return [
            {
              'id': 'srv-1',
              'alias': 'alpha',
              'registry': 'hub.local',
              'namespace': 'hub/opentool',
              'name': 'demo',
              'version': 'latest',
              'schemaVersion': 2,
            },
          ];
        },
      });

      final client = DaemonClient();
      client.serverDio = stub;

      final servers = await client.listServer();

      expect(captured?.method, equals('GET'));
      expect(servers, hasLength(1));
      expect(servers.first.name, equals('demo'));
      expect(servers.first.namespace, equals('hub/opentool'));
      expect(servers.first.version, equals('latest'));
    });

    test('legacy-only Server payload is rejected', () {
      expect(
        () => OpenToolServerDto.fromJson({
          'id': 'srv-1',
          'alias': 'alpha',
          'registry': 'hub.local',
          'repo': 'hub/opentool',
          'name': 'demo',
          'tag': 'latest',
        }),
        throwsA(anything),
      );
    });

    test(
      'deleteServer issues a DELETE request and returns the id DTO',
      () async {
        RequestOptions? captured;
        final stub = createStubDio({
          'DELETE /srv-1': (options) {
            captured = options;
            return {'id': 'srv-1'};
          },
        });

        final client = DaemonClient();
        client.serverDio = stub;

        final dto = await client.deleteServer('srv-1');

        expect(captured?.method, equals('DELETE'));
        expect(dto.id, equals('srv-1'));
      },
    );

    test('deleteServerDetailed preserves artifact cleanup result', () async {
      final stub = createStubDio({
        'DELETE /srv-1': (_) => {
          'id': 'srv-1',
          'serverId': 'srv-1',
          'artifactRemoved': true,
        },
      });
      final client = DaemonClient()..serverDio = stub;

      final result = await client.deleteServerDetailed('srv-1');

      expect(result.id, 'srv-1');
      expect(result.serverId, 'srv-1');
      expect(result.artifactRemoved, isTrue);
    });

    test('structured HTTP errors become DaemonApiException', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException(
              requestOptions: options,
              response: Response<dynamic>(
                requestOptions: options,
                statusCode: 409,
                data: const {
                  'error': {
                    'code': 'SERVER_IN_USE',
                    'message': 'Server is used by a tool',
                    'retryable': false,
                  },
                },
              ),
            ),
          ),
        ),
      );
      final client = DaemonClient()..serverDio = dio;

      await expectLater(
        client.deleteServerDetailed('srv-1'),
        throwsA(
          isA<DaemonApiException>()
              .having((error) => error.code, 'code', 'SERVER_IN_USE')
              .having((error) => error.statusCode, 'statusCode', 409)
              .having((error) => error.retryable, 'retryable', isFalse),
        ),
      );
    });

    test('buildServer waits for a terminal done event', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final release = Completer<void>();
      final serving = server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write('event:start\ndata:{"message":"started"}\n\n');
        await request.response.flush();
        await release.future;
        request.response.write('event:done\ndata:{"message":"done"}\n\n');
        await request.response.close();
      });
      try {
        final client = DaemonClient(
          host: server.address.host,
          port: server.port,
        );
        var completed = false;
        final build = client.buildServer(
          BuildInfoDto(
            opentoolfile: 'Opentoolfile',
            name: 'demo',
            tag: '1.0.0',
          ),
          onStart: (_) {},
          onData: (_) {},
          onDone: (_) => completed = true,
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(completed, isFalse);
        release.complete();
        await build;
        expect(completed, isTrue);
      } finally {
        await server.close(force: true);
        await serving.cancel();
      }
    });

    test('buildServer turns a terminal error event into diagnostics', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serving = server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          'event:error\n'
          'data:{"status":422,"code":"BUILD_COMMAND_FAILED",'
          '"message":"Build command failed","retryable":false,'
          '"details":{"command":"mv input output","exitCode":1,'
          '"stderr":"command not found"}}\n\n',
        );
        await request.response.close();
      });
      try {
        final client = DaemonClient(
          host: server.address.host,
          port: server.port,
        );

        await expectLater(
          client.buildServer(
            BuildInfoDto(
              opentoolfile: 'Opentoolfile',
              name: 'demo',
              tag: '1.0.0',
            ),
            onStart: (_) {},
            onData: (_) {},
            onDone: (_) {},
          ),
          throwsA(
            isA<DaemonApiException>()
                .having((error) => error.statusCode, 'statusCode', 422)
                .having((error) => error.code, 'code', 'BUILD_COMMAND_FAILED')
                .having(
                  (error) => error.details,
                  'details',
                  containsPair('command', 'mv input output'),
                ),
          ),
        );
      } finally {
        await server.close(force: true);
        await serving.cancel();
      }
    });

    test('pullServer sends the install request and waits for done', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      Map<String, dynamic>? requestBody;
      final serving = server.listen((request) async {
        requestBody =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          'event:start\ndata:{"stage":"resolving","ref":"litevar/demo:1.2.3"}\n\n',
        );
        request.response.write(
          'event:done\ndata:{"stage":"ready","server":{"schemaVersion":2,"id":"srv-1","alias":"demo","registry":"https://www.opentool-hub.com","namespace":"litevar","name":"demo","version":"1.2.3"}}\n\n',
        );
        await request.response.close();
      });
      try {
        final client = DaemonClient(
          host: server.address.host,
          port: server.port,
        );
        PullDoneDto? done;
        await client.pullServer(
          PullInfoDto(
            namespace: 'litevar',
            name: 'demo',
            version: '1.2.3',
            client: 'cli',
          ),
          onStart: (_) {},
          onDownload: (_) {},
          onDone: (value) => done = value,
          onPullError: (_) {},
        );

        expect(requestBody, {
          'registry': 'https://www.opentool-hub.com',
          'namespace': 'litevar',
          'name': 'demo',
          'version': '1.2.3',
          'client': 'cli',
        });
        expect(done?.server.id, 'srv-1');
      } finally {
        await server.close(force: true);
        await serving.cancel();
      }
    });

    test(
      'pullServer rejects a stream that closes before a terminal event',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final serving = server.listen((request) async {
          await request.drain<void>();
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          request.response.write(
            'event:start\ndata:{"stage":"resolving","ref":"litevar/demo:1.2.3"}\n\n',
          );
          await request.response.close();
        });
        try {
          final client = DaemonClient(
            host: server.address.host,
            port: server.port,
          );
          await expectLater(
            client.pullServer(
              PullInfoDto(namespace: 'litevar', name: 'demo', version: '1.2.3'),
              onStart: (_) {},
              onDownload: (_) {},
              onDone: (_) {},
              onPullError: (_) {},
            ),
            throwsA(isA<SseProtocolException>()),
          );
        } finally {
          await server.close(force: true);
          await serving.cancel();
        }
      },
    );

    test('pullServerEvents exposes typed terminal events', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serving = server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          'event:start\ndata:{"stage":"resolving","ref":"litevar/demo:1.2.3"}\n\n',
        );
        request.response.write(
          'event:data\ndata:{"stage":"downloading","percent":50}\n\n',
        );
        request.response.write(
          'event:error\ndata:{"code":"HUB_UNAVAILABLE","message":"offline","retryable":true}\n\n',
        );
        await request.response.close();
      });
      try {
        final client = DaemonClient(
          host: server.address.host,
          port: server.port,
        );
        final events = await client
            .pullServerEvents(
              PullInfoDto(namespace: 'litevar', name: 'demo', version: '1.2.3'),
            )
            .toList();

        expect(events, [
          isA<PullStarted>(),
          isA<PullProgress>(),
          isA<PullFailed>(),
        ]);
        expect((events.last as PullFailed).data.code, 'HUB_UNAVAILABLE');
      } finally {
        await server.close(force: true);
        await serving.cancel();
      }
    });

    test('cancelling pullServerEvents cancels the SSE subscription', () async {
      final sse = _CancellableSseClient();
      final client = DaemonClient()..serverSse = sse;
      final firstEvent = Completer<void>();
      final subscription = client
          .pullServerEvents(
            PullInfoDto(namespace: 'litevar', name: 'demo', version: '1.2.3'),
          )
          .listen((_) => firstEvent.complete());

      await firstEvent.future;
      await subscription.cancel();

      expect(sse.cancelled.isCompleted, isTrue);
    });
  });
}

class _CancellableSseClient extends SseClient {
  _CancellableSseClient() : super(baseUrl: 'http://localhost');

  final cancelled = Completer<void>();

  @override
  Future<Stream<String>> request(
    String path, {
    Map<String, dynamic>? requestBody,
    Map<String, dynamic>? queryParameters,
    String method = 'POST',
    Map<String, String>? headers,
  }) async {
    late final StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () => controller.add(
        'event:start\ndata:{"stage":"resolving","ref":"litevar/demo:1.2.3"}\n\n',
      ),
      onCancel: () {
        if (!cancelled.isCompleted) cancelled.complete();
      },
    );
    return controller.stream;
  }
}
