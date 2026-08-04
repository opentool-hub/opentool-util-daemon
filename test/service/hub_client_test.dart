import 'dart:convert';
import 'dart:io';

import 'package:opentool_daemon/src/hub/exception.dart';
import 'package:opentool_daemon/src/hub/hub_client.dart';
import 'package:test/test.dart';

void main() {
  group('HubClient registry validation', () {
    test('normalizes host, default port, and trailing slash', () {
      final uri = HubClient.canonicalizeRegistry(
        'https://EXAMPLE.COM:443/base/',
      );

      expect(uri.toString(), 'https://example.com/base');
    });

    test('allows loopback HTTP without enabling arbitrary insecure hosts', () {
      expect(
        HubClient.canonicalizeRegistry('http://LOCALHOST:8080/').toString(),
        'http://localhost:8080',
      );
      expect(
        HubClient.canonicalizeRegistry('http://127.0.0.1:8080').toString(),
        'http://127.0.0.1:8080',
      );
    });

    test('rejects credentials, query strings, and insecure registries', () {
      for (final value in [
        'https://user:secret@hub.example',
        'https://hub.example?token=secret',
        'http://hub.example',
      ]) {
        expect(
          () => HubClient.canonicalizeRegistry(value),
          throwsFormatException,
        );
      }
      expect(
        HubClient.canonicalizeRegistry(
          'http://hub.example',
          allowInsecure: true,
        ).toString(),
        'http://hub.example',
      );
    });
  });

  test(
    'resolve sends the canonical path, platform query, and client headers',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      HttpRequest? observed;
      final serving = server.listen((request) async {
        observed = request;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'tool': {'namespace': 'litevar', 'name': 'demo'},
            'version': '1.2.3',
            'versionDigest': 'sha256:${List.filled(64, 'a').join()}',
            'artifact': {
              'id': 'artifact-1',
              'os': 'linux',
              'arch': 'x64',
              'abi': 'glibc',
              'fileName': 'demo.ots',
              'mediaType': 'application/vnd.opentool.ots',
              'size': 42,
              'digest': 'sha256:${List.filled(64, 'b').join()}',
              'downloadUrl': 'https://objects.example/demo.ots',
              'downloadUrlExpiresAt': '2030-01-01T00:00:00Z',
            },
          }),
        );
        await request.response.close();
      });
      try {
        final base = 'http://${server.address.host}:${server.port}/api/';
        final result =
            await HubClient(
              base,
              daemonVersion: '0.3.0',
              allowInsecureHub: true,
            ).resolve(
              namespace: 'litevar',
              name: 'demo',
              version: '1.2.3',
              os: 'linux',
              arch: 'x64',
              abi: 'glibc',
              client: 'cli',
            );

        expect(
          observed?.uri.path,
          '/api/v1/tools/litevar/demo/versions/1.2.3/resolve',
        );
        expect(observed?.uri.queryParameters, {
          'os': 'linux',
          'arch': 'x64',
          'abi': 'glibc',
        });
        expect(observed?.headers.value('user-agent'), 'opentool-daemon/0.3.0');
        expect(observed?.headers.value('x-agentos-client'), 'cli');
        expect(result.artifact.id, 'artifact-1');
      } finally {
        await server.close(force: true);
        await serving.cancel();
      }
    },
  );

  test('resolve preserves structured Hub errors and request ids', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = server.listen((request) async {
      request.response.statusCode = HttpStatus.notFound;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'error': {
            'code': 'VERSION_NOT_FOUND',
            'message': 'No such version',
            'requestId': 'req-123',
          },
        }),
      );
      await request.response.close();
    });
    try {
      final client = HubClient(
        'http://${server.address.host}:${server.port}',
        allowInsecureHub: true,
      );
      await expectLater(
        client.resolve(
          namespace: 'litevar',
          name: 'missing',
          version: '1.0.0',
          os: 'linux',
          arch: 'x64',
          abi: 'glibc',
          client: 'embedded',
        ),
        throwsA(
          isA<HubApiException>()
              .having((error) => error.code, 'code', 'VERSION_NOT_FOUND')
              .having((error) => error.requestId, 'requestId', 'req-123')
              .having((error) => error.retryable, 'retryable', isFalse),
        ),
      );
    } finally {
      await server.close(force: true);
      await serving.cancel();
    }
  });

  test(
    'resolve maps unstructured 5xx responses to retryable failure',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serving = server.listen((request) async {
        request.response.statusCode = HttpStatus.badGateway;
        request.response.headers.contentType = ContentType.html;
        request.response.write('<html>proxy error</html>');
        await request.response.close();
      });
      try {
        final client = HubClient(
          'http://${server.address.host}:${server.port}',
          allowInsecureHub: true,
        );
        await expectLater(
          client.resolve(
            namespace: 'litevar',
            name: 'demo',
            version: '1.0.0',
            os: 'linux',
            arch: 'arm64',
            abi: 'glibc',
            client: 'embedded',
          ),
          throwsA(
            isA<HubApiException>()
                .having((error) => error.code, 'code', 'HUB_UNAVAILABLE')
                .having((error) => error.statusCode, 'statusCode', 502)
                .having((error) => error.retryable, 'retryable', isTrue),
          ),
        );
      } finally {
        await server.close(force: true);
        await serving.cancel();
      }
    },
  );
}
