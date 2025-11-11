import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'constants.dart';

Middleware exceptionHandler() {
  return (Handler innerHandler) {
    return (Request request) async {
      try {
        return await innerHandler(request);
      } catch (e, stack) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: JSON_HEADERS,
        );
      }
    };
  };
}