import 'dart:convert';
import 'dart:io';

import 'package:opentool_daemon/src/utils/sse_client.dart';
import 'package:test/test.dart';

void main() {
  test(
    'request reassembles SSE frames split across transport chunks',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      String? contentType;
      String? accept;
      String? requestBody;
      final serving = server.listen((request) async {
        contentType = request.headers.contentType?.mimeType;
        accept = request.headers.value(HttpHeaders.acceptHeader);
        requestBody = await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.add(utf8.encode('event:da'));
        await request.response.flush();
        request.response.add(utf8.encode('ta\ndata:{"stage":"down'));
        await request.response.flush();
        request.response.add(utf8.encode('loading"}\n\n'));
        await request.response.close();
      });

      try {
        final client = SseClient(
          baseUrl: 'http://${server.address.host}:${server.port}',
        );
        final stream = await client.request(
          '/events',
          requestBody: {'name': 'demo'},
        );
        final frame = await stream.single;
        final events = <EventData>[];
        SseClient.parse(
          frame,
          (event, data) => events.add(EventData(event, data)),
        );

        expect(events, hasLength(1));
        expect(events.single.event, 'data');
        expect(events.single.data['stage'], 'downloading');
        expect(contentType, 'application/json');
        expect(accept, 'text/event-stream');
        expect(jsonDecode(requestBody!), {'name': 'demo'});
      } finally {
        await server.close(force: true);
        await serving.cancel();
      }
    },
  );
}
