import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

import 'constants.dart';
import 'service/exception.dart';
import 'utils/command_util.dart';
import 'utils/directory_util.dart';

class DaemonErrorDescriptor {
  final int status;
  final String code;
  final String message;
  final bool retryable;
  final String? requestId;
  final Object? details;

  const DaemonErrorDescriptor(
    this.status,
    this.code,
    this.message,
    this.retryable, {
    this.requestId,
    this.details,
  });

  Map<String, dynamic> toJson({bool includeStatus = false}) => {
    if (includeStatus) 'status': status,
    'code': code,
    'message': message,
    'retryable': retryable,
    if (requestId != null) 'requestId': requestId,
    if (details != null) 'details': details,
  };
}

Response daemonErrorResponse(Object error, {required String requestPath}) {
  final mapped = mapDaemonError(error, requestPath: requestPath);
  return Response(
    mapped.status,
    body: jsonEncode({'error': mapped.toJson()}),
    headers: JSON_HEADERS,
  );
}

DaemonErrorDescriptor mapDaemonError(
  Object error, {
  required String requestPath,
}) {
  if (error is ArtifactOperationException) {
    final status = switch (error.code) {
      'INVALID_REQUEST' || 'INVALID_TOOL_REFERENCE' => 400,
      'HOST_AUTH_REQUIRED' => 403,
      'SERVER_NOT_FOUND' || 'TOOL_NOT_FOUND' || 'TOOL_VERSION_NOT_FOUND' => 404,
      'SERVER_PROTECTED' ||
      'SERVER_IN_USE' ||
      'TOOL_DELETE_LOCKED' ||
      'TOOL_STOP_TIMEOUT' ||
      'ARTIFACT_SOURCE_CONFLICT' => 409,
      'ARTIFACT_INVALID' ||
      'ARTIFACT_DIGEST_MISMATCH' ||
      'ARTIFACT_SIZE_MISMATCH' ||
      'PLATFORM_MISMATCH' ||
      'PLATFORM_NOT_SUPPORTED' => 422,
      'HUB_UNAVAILABLE' || 'ARTIFACT_DOWNLOAD_FAILED' => 502,
      'INSUFFICIENT_STORAGE' => 507,
      _ => 500,
    };
    return DaemonErrorDescriptor(
      status,
      error.code,
      error.message,
      error.retryable,
      requestId: error.requestId,
      details: error.details,
    );
  }
  if (error is ServerNotFoundException) {
    return DaemonErrorDescriptor(404, 'SERVER_NOT_FOUND', error.message, false);
  }
  if (error is ToolNotFoundException) {
    return DaemonErrorDescriptor(404, 'TOOL_NOT_FOUND', error.message, false);
  }
  if (error is ApiKeyNotFoundException) {
    return const DaemonErrorDescriptor(
      404,
      'API_KEY_NOT_FOUND',
      'API key not found',
      false,
    );
  }
  if (error is SudoAuthorizationException) {
    return DaemonErrorDescriptor(
      403,
      'HOST_AUTH_REQUIRED',
      error.message,
      false,
    );
  }
  if (error is ToolRestartConflictException) {
    return DaemonErrorDescriptor(
      409,
      'TOOL_RESTART_CONFLICT',
      error.message,
      true,
    );
  }
  if (error is ToolEndpointConflictException) {
    return DaemonErrorDescriptor(
      409,
      'TOOL_ENDPOINT_CONFLICT',
      'Tool endpoint is already in use',
      false,
      details: {
        'host': error.host,
        'port': error.port,
        if (error.listeningPids.isNotEmpty) 'pids': error.listeningPids,
      },
    );
  }
  if (error is CommandException && requestPath.endsWith('servers/build')) {
    return DaemonErrorDescriptor(
      422,
      'BUILD_COMMAND_FAILED',
      'Build command failed',
      false,
      details: {
        'command': _truncateClientDiagnostic(error.command),
        if (error.exitCode != null) 'exitCode': error.exitCode,
        if (error.stderr.trim().isNotEmpty)
          'stderr': _truncateClientDiagnostic(error.stderr),
        if (error.stdout.trim().isNotEmpty)
          'stdout': _truncateClientDiagnostic(error.stdout),
      },
    );
  }
  if (error is OpentoolfileMissingArgumentException) {
    return DaemonErrorDescriptor(
      422,
      'OPENTOOLFILE_INVALID',
      'Invalid Opentoolfile: ${error.message}',
      false,
    );
  }
  if (error is FileNotFoundException) {
    return DaemonErrorDescriptor(404, 'FILE_NOT_FOUND', error.message, false);
  }
  if (error is FileSystemException) {
    final osCode = error.osError?.errorCode;
    final details = error.path == null
        ? null
        : {'path': _truncateClientDiagnostic(error.path!)};
    if (osCode == 2 || osCode == 3) {
      return DaemonErrorDescriptor(
        404,
        'FILE_NOT_FOUND',
        'File or directory not found',
        false,
        details: details,
      );
    }
    if (osCode == 5 || osCode == 13) {
      return DaemonErrorDescriptor(
        403,
        'FILE_ACCESS_DENIED',
        'File or directory access was denied',
        false,
        details: details,
      );
    }
  }
  if (error is FormatException) {
    final message = error.message.toString().trim();
    return DaemonErrorDescriptor(
      400,
      'INVALID_REQUEST',
      message.isEmpty ? 'Invalid request' : message,
      false,
    );
  }
  if (error is ArgumentError) {
    final message = error.message?.toString().trim();
    return DaemonErrorDescriptor(
      400,
      'INVALID_REQUEST',
      message == null || message.isEmpty ? 'Invalid request' : message,
      false,
    );
  }
  return const DaemonErrorDescriptor(
    500,
    'INTERNAL_ERROR',
    'An internal error occurred',
    false,
  );
}

const _maxClientDiagnosticChars = 8192;

String _truncateClientDiagnostic(String value) {
  final trimmed = value.trim();
  if (trimmed.length <= _maxClientDiagnosticChars) return trimmed;
  final sideLength = _maxClientDiagnosticChars ~/ 2;
  final omitted = trimmed.length - (sideLength * 2);
  return '${trimmed.substring(0, sideLength)}\n'
      '...[truncated $omitted chars]...\n'
      '${trimmed.substring(trimmed.length - sideLength)}';
}
