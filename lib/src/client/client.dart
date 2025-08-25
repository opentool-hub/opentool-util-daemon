import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:opentool_daemon/opentool_daemon_server.dart';

class DaemonClient {
  String protocol = 'http';
  String host = "localhost";
  int port = DAEMON_DEFAULT_PORT;
  String prefix = DAEMON_DEFAULT_PREFIX;
  late Dio dio;

  DaemonClient({int? port}) {
    if (port != null && port > 0) this.port = port;
    String baseUrl = '$protocol://${host}:${this.port}${prefix}';

    Map<String, String> headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    dio = Dio(BaseOptions(baseUrl: baseUrl, headers: headers));
  }

  Future<VersionDto> getVersion() async {
    Response response = await dio.get('/version');
    return VersionDto.fromJson(response.data);
  }

  Future<List<OpenToolServerDto>> list() async {
    Response response = await dio.get('/list');
    List<dynamic> res = response.data;
    List<OpenToolServerDto> result = res.map((dyn) => OpenToolServerDto.fromJson(dyn as Map<String, dynamic>)).toList();
    return result;
  }

  Future<RegisterResult> register(RegisterInfo registerInfo) async {
    Response response = await dio.post('/register', data: jsonEncode(registerInfo.toJson()),);
    return RegisterResult.fromJson(response.data);
  }

  Future<StatusDto> rename(RenameDto renameDto) async {
    Response response = await dio.post('/rename', data: jsonEncode(renameDto.toJson()),);
    return StatusDto.fromJson(response.data);
  }

  Future<ToolReturnDto> call(ServerFunctionCallDto functionCallDto) async {
    Response response = await dio.post('/call', data: jsonEncode(functionCallDto.toJson()),);
    Map<String, dynamic> responseData = response.data;
    if(responseData.containsKey('error')) {
      return ToolReturnDto( id: functionCallDto.id, result: responseData);
    }
    return ToolReturnDto.fromJson(response.data);
  }

  Future<Map<String, dynamic>> load(String id) async {
    ServerIdDto serverIdDto = ServerIdDto(id: id);
    Response response = await dio.post('/load', data: jsonEncode(serverIdDto.toJson()));
    return response.data;
  }

  Future<StatusDto> stop(String id) async {
    ServerIdDto serverIdDto = ServerIdDto(id: id);
    Response response = await dio.post('/stop', data: jsonEncode(serverIdDto.toJson()));
    return StatusDto.fromJson(response.data);
  }

  Future<StatusDto> remove(String id) async {
    ServerIdDto serverIdDto = ServerIdDto(id: id);
    Response response = await dio.post('/remove', data: jsonEncode(serverIdDto.toJson()));
    return StatusDto.fromJson(response.data);
  }
}