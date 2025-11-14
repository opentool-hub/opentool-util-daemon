import 'dart:convert';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'constants.dart';
import 'utils/logger.dart';

Middleware exceptionHandler() {
  return (Handler innerHandler) {
    return (Request request) async {
      try {
        return await innerHandler(request);
      } catch (e, stack) {
        String url = request.url.toString();
        logger.log(
          LogModule.http,
          "URL: $url",
          detail: 'error: ${e.toString()}\n$stack',
          level: Level.WARNING,
        );
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
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
      String uri = request.requestedUri.toString();
      String body = await request.readAsString();
      logger.log(LogModule.http, "logRequest", detail: "[$method] $uri $body", level: Level.FINE);
      Request newRequest = request.change(body: Stream.value(utf8.encode(body)));
      return innerHandler(newRequest);
    };
  };
}
