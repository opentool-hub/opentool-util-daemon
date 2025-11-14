import 'dart:convert';
import 'dart:io' as io;

class SseRequestException implements Exception {
  final int statusCode;
  final String body;

  const SseRequestException(this.statusCode, this.body);

  @override
  String toString() => 'SseRequestException($statusCode, $body)';
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
  }) async {
    Uri uri = Uri.parse(
      "$baseUrl$path",
    ).replace(queryParameters: queryParameters);

    io.HttpClient httpClient = io.HttpClient();
    io.HttpClientRequest request = await httpClient.postUrl(uri);

    headers?.forEach((key, value) {
      request.headers.set(key, value);
    });
    if (apiKey != null)
      request.headers.add(io.HttpHeaders.authorizationHeader, 'Bearer $apiKey');

    request.add(utf8.encode(jsonEncode(requestBody ?? {})));

    io.HttpClientResponse response = await request.close();

    if (response.statusCode >= 400) {
      final errorBody = await response.transform(utf8.decoder).join();
      throw SseRequestException(response.statusCode, errorBody);
    }

    Stream<String> stream = response.transform(utf8.decoder);
    return stream;
  }

  static Future<void> parse(
    String data,
    void Function(String event, Map<String, dynamic> data) onEvent,
  ) async {
    final eventRegex = RegExp(r'event:(\w+)\ndata:(.*?)\n\n');
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
