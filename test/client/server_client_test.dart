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
  });
}
