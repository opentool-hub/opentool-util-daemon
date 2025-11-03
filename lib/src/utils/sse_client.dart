import 'dart:convert';
import 'dart:io' as io;

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

  Future<Stream<String>> request(String path, {Map<String, dynamic>? requestBody, Map<String, dynamic>? queryParameters}) async {
    Uri uri = Uri.parse(baseUrl).replace(path: path,queryParameters: queryParameters);
    io.HttpClient httpClient = io.HttpClient();
    io.HttpClientRequest request = await httpClient.postUrl(uri);

    headers?.forEach((key, value) {request.headers.set(key, value);});
    if(apiKey != null) request.headers.add(io.HttpHeaders.authorizationHeader, 'Bearer $apiKey');

    request.add(utf8.encode(jsonEncode(requestBody??{})));

    io.HttpClientResponse response = await request.close();

    Stream<String> stream = response.transform(utf8.decoder);
    return stream;
  }

  static Future<void> parse(String data, void Function(String event, Map<String, dynamic> data) onEvent) async {
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