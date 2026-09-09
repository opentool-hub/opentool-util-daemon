import 'dart:convert';

import 'package:opentool_daemon/src/middleware.dart';
import 'package:opentool_daemon/src/service/exception.dart';
import 'package:opentool_daemon/src/utils/command_util.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  test('maps a Server platform mismatch to an actionable 422 error', () async {
    final handler = exceptionHandler()((_) async {
      throw SystemMismatchException(
        'macos',
        'arm64',
        'windows',
        'arm64',
        nativeAbi: 'native',
        remoteAbi: 'native',
      );
    });

    final response = await handler(
      Request('POST', Uri.parse('http://localhost/servers/import')),
    );
    final body = jsonDecode(await response.readAsString());

    expect(response.statusCode, 422);
    expect(body, {
      'error': {
        'code': 'PLATFORM_MISMATCH',
        'message':
            'Server platform windows-arm64-native is not compatible with '
            'this device (macos-arm64-native). Import an .ots file built for '
            'macos-arm64-native.',
        'retryable': false,
      },
    });
  });

  test('maps a failed build command to an actionable 422 error', () async {
    final handler = exceptionHandler()((_) async {
      throw CommandException(
        'dart compile exe bin/main.dart',
        'compile failed',
        exitCode: 254,
        stdout: 'compiler context',
        stderr: 'No named parameter with the name cliTool',
      );
    });

    final response = await handler(
      Request('POST', Uri.parse('http://localhost/servers/build')),
    );
    final body = jsonDecode(await response.readAsString());

    expect(response.statusCode, 422);
    expect(body, {
      'error': {
        'code': 'BUILD_COMMAND_FAILED',
        'message': 'Build command failed',
        'retryable': false,
        'details': {
          'exitCode': 254,
          'stderr': 'No named parameter with the name cliTool',
          'stdout': 'compiler context',
        },
      },
    });
  });

  test('maps a Tool stop timeout to a retryable conflict', () async {
    final handler = exceptionHandler()((_) async {
      throw const ArtifactOperationException(
        code: 'TOOL_STOP_TIMEOUT',
        message: 'Tool tool-1 did not release 127.0.0.1:9010',
        retryable: true,
      );
    });

    final response = await handler(
      Request('DELETE', Uri.parse('http://localhost/tools/tool-1')),
    );
    final body = jsonDecode(await response.readAsString());

    expect(response.statusCode, 409);
    expect(body, {
      'error': {
        'code': 'TOOL_STOP_TIMEOUT',
        'message': 'Tool tool-1 did not release 127.0.0.1:9010',
        'retryable': true,
      },
    });
  });

  test('maps a Tool endpoint conflict with diagnostics', () async {
    final handler = exceptionHandler()((_) async {
      throw const ToolEndpointConflictException(
        toolId: 'tool-1',
        host: '127.0.0.1',
        port: 9010,
        listeningPids: [1234],
      );
    });

    final response = await handler(
      Request('POST', Uri.parse('http://localhost/tools/tool-1/start')),
    );
    final body = jsonDecode(await response.readAsString());

    expect(response.statusCode, 409);
    expect(body, {
      'error': {
        'code': 'TOOL_ENDPOINT_CONFLICT',
        'message': 'Tool endpoint is already in use',
        'retryable': false,
        'details': {
          'host': '127.0.0.1',
          'port': 9010,
          'pids': [1234],
        },
      },
    });
  });
}
