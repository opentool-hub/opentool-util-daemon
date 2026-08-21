import 'dart:convert';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'constants.dart';
import 'utils/logger.dart';
import 'service/exception.dart';

Middleware exceptionHandler() {
  return (Handler innerHandler) {
    return (Request request) async {
      try {
        return await innerHandler(request);
      } catch (e, stack) {
        final mapped = _mapError(e);
        logger.log(
          LogModule.http,
          'request.error',
          detail:
              'method: ${request.method}, path: ${request.url.path}, code: ${mapped.code}, error: $e\n$stack',
          level: Level.WARNING,
        );
        return Response(
          mapped.status,
          body: jsonEncode({
            'error': {
              'code': mapped.code,
              'message': mapped.message,
              'retryable': mapped.retryable,
            },
          }),
          headers: JSON_HEADERS,
        );
      }
    };
  };
}

Middleware logRequest() {
  return (Handler innerHandler) {
    return (Request request) async {
      String method = request.method;
      logger.log(
        LogModule.http,
        "logRequest",
        detail:
            "[$method] ${request.url.path} contentLength=${request.contentLength ?? -1}",
        level: Level.FINE,
      );
      return innerHandler(request);
    };
  };
}

_HttpError _mapError(Object error) {
  if (error is ArtifactOperationException) {
    final status = switch (error.code) {
      'INVALID_REQUEST' || 'INVALID_TOOL_REFERENCE' => 400,
      'HOST_AUTH_REQUIRED' => 403,
      'SERVER_NOT_FOUND' || 'TOOL_NOT_FOUND' || 'TOOL_VERSION_NOT_FOUND' => 404,
      'SERVER_PROTECTED' ||
      'SERVER_IN_USE' ||
      'ARTIFACT_SOURCE_CONFLICT' => 409,
      'ARTIFACT_INVALID' ||
      'ARTIFACT_DIGEST_MISMATCH' ||
      'ARTIFACT_SIZE_MISMATCH' ||
      'PLATFORM_NOT_SUPPORTED' => 422,
      'HUB_UNAVAILABLE' || 'ARTIFACT_DOWNLOAD_FAILED' => 502,
      'INSUFFICIENT_STORAGE' => 507,
      _ => 500,
    };
    return _HttpError(status, error.code, error.message, error.retryable);
  }
  if (error is ServerNotFoundException) {
    return _HttpError(404, 'SERVER_NOT_FOUND', error.message, false);
  }
  if (error is ToolNotFoundException) {
    return _HttpError(404, 'TOOL_NOT_FOUND', error.message, false);
  }
  if (error is FormatException || error is ArgumentError) {
    return const _HttpError(400, 'INVALID_REQUEST', 'Invalid request', false);
  }
  return const _HttpError(
    500,
    'INTERNAL_ERROR',
    'An internal error occurred',
    false,
  );
}

class _HttpError {
  final int status;
  final String code;
  final String message;
  final bool retryable;
  const _HttpError(this.status, this.code, this.message, this.retryable);
}
