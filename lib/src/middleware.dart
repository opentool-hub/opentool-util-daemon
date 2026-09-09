import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'error_mapper.dart';
import 'utils/logger.dart';

Middleware exceptionHandler() {
  return (Handler innerHandler) {
    return (Request request) async {
      try {
        return await innerHandler(request);
      } catch (e, stack) {
        final mapped = mapDaemonError(e, requestPath: request.url.path);
        logger.log(
          LogModule.http,
          'request.error',
          detail:
              'method: ${request.method}, path: ${request.url.path}, code: ${mapped.code}, error: $e\n$stack',
          level: Level.WARNING,
        );
        return daemonErrorResponse(e, requestPath: request.url.path);
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
