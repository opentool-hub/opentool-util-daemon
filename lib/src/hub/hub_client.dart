import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'dto.dart';

class HubClient {
  final Dio _dio;

  HubClient(String baseUrl) : _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
    headers: {"Content-Type": "application/json"},
  ));

  Future<LoginResult?> login(String username, String password) async {
    LoginInfo loginInfo = LoginInfo(username: username, password: password);
    try {
      final response = await _dio.post("/v1/users/login/",
        data: jsonEncode(loginInfo.toJson()),
      );
      if (response.statusCode == 200) {
        LoginResult result = LoginResult.fromJson(response.data);
        return result;
      }
      return null;
    } on DioException catch (e) {
      print("Login failed: ${e.response?.data ?? e.message}");
      rethrow;
    }
  }


  Future<Manifest> pullManifest(String repo, String name, String tag) async {
    final url = "/v1/$repo/$name/manifests/$tag";
    try {
      final response = await _dio.get(
        url,
        options: Options(
          headers: {
            "Accept": "application/vnd.docker.distribution.manifest.v2+json",
          },
        ),
      );

      Manifest manifest = Manifest.fromJson(response.data);
      return manifest;
    } on DioException {
      rethrow;
    }
  }

  Future<void> pullBlob(String repo, String digest, String savefilePath, {void Function(int download, int total)? onProgress}) async {
    final url = "/v1/$repo/blobs/$digest";

    try {
      final response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            "Accept": "application/octet-stream",
          },
        ),
      );

      final file = File(savefilePath);
      final sink = file.openWrite();

      final total = response.headers["content-length"]?.first;
      int downloaded = 0;

      await for (final chunk in response.data!.stream) {
        downloaded += chunk.length;
        sink.add(chunk);

        if (total != null) {
          onProgress?.call(downloaded, int.parse(total));
        }
      }

      await sink.close();
      print("\n✅ Download complete: $savefilePath");

    } on DioException catch (e) {
      print("❌ Pull blob failed: ${e.response?.statusCode}");
      print("Error body: ${e.response?.data}");
      rethrow;
    }
  }

  Future<void> pushManifest(String repo, String tag, Manifest manifest) async {
    final url = "/v1/$repo/manifests/$tag";
    try {
      final response = await _dio.put(url, data: manifest.toJson());
      print("✅ Push manifest success: ${response.statusCode}");
      print("Response headers: ${response.headers}");
    } on DioException catch (e) {
      print("❌ Push manifest failed: ${e.response?.statusCode}");
      print("Error body: ${e.response?.data}");
      rethrow;
    }
  }

  Future<void> uploadBlob(String repo, String digest, List<int> bytes, {void Function(int sent, int total)? onProgress,}) async {
    final url = "/v1/$repo/blobs/$digest";
    try {
      final response = await _dio.put(
        url,
        data: Stream.fromIterable([bytes]),
        options: Options(
          headers: {
            "Content-Type": "application/octet-stream",
            "Digest": digest,
            "Content-Length": bytes.length.toString(),
          },
        ),
        onSendProgress: onProgress,
      );
      print("✅ Upload blob success: ${response.statusCode}");
    } on DioException catch (e) {
      print("❌ Upload blob failed: ${e.response?.statusCode}");
      print("Error body: ${e.response?.data}");
      rethrow;
    }
  }

}