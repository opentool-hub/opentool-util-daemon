import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

class SseRequestException implements Exception {
  final int statusCode;
  final String body;

  const SseRequestException(this.statusCode, this.body);

  @override
  String toString() => 'SseRequestException($statusCode, $body)';
}

class SseProtocolException implements Exception {
  final String message;

  const SseProtocolException(this.message);

  @override
  String toString() => message;
}

class EventData {
  final String event;
  final Map<String, dynamic> data;

  EventData(this.event, this.data);
}

class SseClient {
  String baseUrl;
  String? apiKey;
  Map<String, String>? headers;

  SseClient({required this.baseUrl, this.headers, this.apiKey});

  Future<Stream<String>> request(
    String path, {
    Map<String, dynamic>? requestBody,
    Map<String, dynamic>? queryParameters,
    String method = 'POST',
    Map<String, String>? headers,
  }) async {
    Uri uri = Uri.parse(
      "$baseUrl$path",
    ).replace(queryParameters: queryParameters);

    io.HttpClient httpClient = io.HttpClient();
    io.HttpClientRequest request = await httpClient.openUrl(method, uri);

    this.headers?.forEach((key, value) {
      request.headers.set(key, value);
    });
    headers?.forEach((key, value) {
      request.headers.set(key, value);
    });
    request.headers.set(io.HttpHeaders.acceptHeader, 'text/event-stream');
    if (apiKey != null)
      request.headers.add(io.HttpHeaders.authorizationHeader, 'Bearer $apiKey');

    if (requestBody != null) {
      request.headers.set(io.HttpHeaders.contentTypeHeader, 'application/json');
      request.add(utf8.encode(jsonEncode(requestBody)));
    }

    io.HttpClientResponse response = await request.close();

    if (response.statusCode >= 400) {
      final errorBody = await response.transform(utf8.decoder).join();
      httpClient.close(force: true);
      throw SseRequestException(response.statusCode, errorBody);
    }

    var buffer = '';
    final responseStream = response
        .transform(utf8.decoder)
        .transform(
          StreamTransformer<String, String>.fromHandlers(
            handleData: (chunk, sink) {
              buffer += chunk.replaceAll('\r\n', '\n');
              var boundary = buffer.indexOf('\n\n');
              while (boundary >= 0) {
                sink.add('${buffer.substring(0, boundary)}\n\n');
                buffer = buffer.substring(boundary + 2);
                boundary = buffer.indexOf('\n\n');
              }
            },
          ),
        );
    StreamSubscription<String>? subscription;
    late final StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () {
        subscription = responseStream.listen(
          controller.add,
          onError: (Object error, StackTrace stackTrace) {
            httpClient.close(force: true);
            controller.addError(error, stackTrace);
          },
          onDone: () async {
            httpClient.close(force: true);
            await controller.close();
          },
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        httpClient.close(force: true);
        return subscription?.cancel();
      },
    );
    return controller.stream;
  }

  static void parse(
    String data,
    void Function(String event, Map<String, dynamic> data) onEvent,
  ) {
    final eventRegex = RegExp(r'event:([^\n]+)\ndata:(.*?)\n\n');
    final matches = eventRegex.allMatches(data);

    for (var match in matches) {
      final eventName = match.group(1);
      final eventData = match.group(2);

      if (eventName != null && eventData != null) {
        onEvent(eventName, jsonDecode(eventData));
      }
    }
  }
}
