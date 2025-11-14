import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:opentool_dart/opentool_dart.dart';
import 'package:opentool_daemon/opentool_daemon_server.dart';
import '../utils/command_util.dart';
import '../utils/sse_client.dart';

class DaemonClient {
  String protocol = 'http';
  late String host;
  late int port;
  String prefix = DAEMON_DEFAULT_PREFIX;
  late Dio manageDio;
  late Dio serverDio;
  late Dio toolDio;
  late SseClient serverSse;
  late SseClient toolSse;

  DaemonClient({
    String host = HostType.LOCALHOST,
    int port = DAEMON_DEFAULT_PORT,
  }) {
    this.host = host;
    this.port = port;
    String baseUrl = '$protocol://${host}:${this.port}${prefix}';

    manageDio = Dio(BaseOptions(baseUrl: baseUrl, headers: JSON_HEADERS));
    serverDio = Dio(
      BaseOptions(baseUrl: '$baseUrl$SERVER_PREFIX', headers: JSON_HEADERS),
    );
    toolDio = Dio(
      BaseOptions(baseUrl: '$baseUrl$TOOL_PREFIX', headers: JSON_HEADERS),
    );

    serverSse = SseClient(
      baseUrl: '$baseUrl$SERVER_PREFIX',
      headers: STREAM_HEADERS,
    );
    toolSse = SseClient(
      baseUrl: '$baseUrl$TOOL_PREFIX',
      headers: STREAM_HEADERS,
    );
  }

  /// Manage API： /opentool-daemon ==========

  /// GET /version
  Future<VersionDto> getVersion() async {
    Response response = await manageDio.get('/version');
    return VersionDto.fromJson(response.data);
  }

  /// POST /opentool-hub/login
  Future<LoginResultDto> loginHub(LoginInfoDto loginInfoDto) async {
    Response response = await manageDio.post(
      '/opentool-hub/login',
      data: loginInfoDto.toJson(),
    );
    return LoginResultDto.fromJson(response.data);
  }

  /// GET /opentool-hub/user
  Future<UserInfoDto> userHub() async {
    Response response = await manageDio.get('/opentool-hub/user');
    return UserInfoDto.fromJson(response.data);
  }

  /// POST /opentool-hub/logout
  Future<UserInfoDto> logoutHub() async {
    Response response = await manageDio.post('/opentool-hub/logout');
    return UserInfoDto.fromJson(response.data);
  }

  /// Server API： /opentool-daemon/servers ==========

  /// GET /servers/list
  Future<List<OpenToolServerDto>> listServer() async {
    Response response = await serverDio.get('/list');
    List<dynamic> res = response.data;
    List<OpenToolServerDto> result = res
        .map((dyn) => OpenToolServerDto.fromJson(dyn as Map<String, dynamic>))
        .toList();
    return result;
  }

  /// POST /servers/build
  Future<void> buildServer(
    BuildInfoDto buildInfoDto, {
    required void Function(EventMessageDto startMessage) onStart,
    required void Function(CommandOutputDto commandOutput) onData,
    required void Function(EventMessageDto doneMessage) onDone,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    try {
      Stream<String> sseStream = await serverSse.request(
        '/build',
        queryParameters: buildInfoDto.toJson(),
      );
      void Function(String event, Map<String, dynamic> data) onEvent =
          (String event, Map<String, dynamic> data) {
            if (event == EventType.START) {
              onStart(EventMessageDto.fromJson(data));
            } else if (event == EventType.DATA) {
              onData(CommandOutputDto.fromJson(data));
            } else if (event == EventType.DONE) {
              onDone(EventMessageDto.fromJson(data));
            }
          };
      sseStream.listen(
        (data) => SseClient.parse(data, onEvent),
        onError: (error, stackTrace) {
          onError?.call(error, stackTrace);
        },
        cancelOnError: true,
      );
    } catch (error, stackTrace) {
      if (onError != null) {
        onError(error, stackTrace);
        return;
      }
      rethrow;
    }
  }

  /// DELETE /servers/{server_id}
  Future<ServerIdDto> deleteServer(String serverId) async {
    Response response = await serverDio.delete('/$serverId');
    return ServerIdDto.fromJson(response.data);
  }

  /// POST /servers/{server_id}/tag?tag=<target_tag>
  Future<OpenToolServerDto> tagServer(String serverId, String? tag) async {
    Map<String, dynamic>? queryParameters;
    if (tag != null && tag.isNotEmpty) {
      queryParameters = {'tag': tag};
    }
    Response response = await serverDio.post(
      '/$serverId/tag',
      queryParameters: queryParameters,
    );
    return OpenToolServerDto.fromJson(response.data);
  }

  /// POST /servers/pull?name=<target_name>&tag=<target_tag>
  Future<void> pullServer(
    PullInfoDto pullInfo, {
    required void Function(PullStartDto pullStart) onStart,
    required void Function(PullDownloadDto pullDownload) onDownload,
    required void Function(PullInfoDto pullInfo) onDone,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    try {
      Stream<String> sseStream = await serverSse.request(
        '/pull',
        queryParameters: pullInfo.toJson(),
      );
      void Function(String event, Map<String, dynamic> data) onEvent =
          (String event, Map<String, dynamic> data) {
            if (event == EventType.START) {
              onStart(PullStartDto.fromJson(data));
            } else if (event == EventType.DATA) {
              onDownload(PullDownloadDto.fromJson(data));
            } else if (event == EventType.DONE) {
              onDone(PullInfoDto.fromJson(data));
            }
          };
      sseStream.listen(
        (data) => SseClient.parse(data, onEvent),
        onError: (error, stackTrace) {
          onError?.call(error, stackTrace);
        },
        cancelOnError: true,
      );
    } catch (error, stackTrace) {
      if (onError != null) {
        onError(error, stackTrace);
        return;
      }
      rethrow;
    }
  }

  /// POST /servers/{serverId}/push
  Future<void> pushServer(
    String serverId, {
    required void Function(PushStartDto pushStart) onStart,
    required void Function(PushUploadDto pushUpload) onUpload,
    required void Function(ServerIdDto serverId) onDone,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    try {
      Stream<String> sseStream = await serverSse.request('/$serverId/push');
      void Function(String event, Map<String, dynamic> data) onEvent =
          (String event, Map<String, dynamic> data) {
            if (event == EventType.START) {
              onStart(PushStartDto.fromJson(data));
            } else if (event == EventType.DATA) {
              onUpload(PushUploadDto.fromJson(data));
            } else if (event == EventType.DONE) {
              onDone(ServerIdDto.fromJson(data));
            }
          };
      sseStream.listen(
        (data) => SseClient.parse(data, onEvent),
        onError: (error, stackTrace) {
          onError?.call(error, stackTrace);
        },
        cancelOnError: true,
      );
    } catch (error, stackTrace) {
      if (onError != null) {
        onError(error, stackTrace);
        return;
      }
      rethrow;
    }
  }

  /// GET /servers/{serverId}/export
  Future<ServerIdDto> exportServer(String serverId, String targetPath) async {
    PathDto pathDto = PathDto(path: targetPath);
    Response response = await serverDio.post(
      '/$serverId/export',
      data: pathDto.toJson(),
    );
    return ServerIdDto.fromJson(response.data);
  }

  /// POST /servers/import
  Future<OpenToolServerDto> importServer(String sourcePath) async {
    PathDto pathDto = PathDto(path: sourcePath);
    Response response = await serverDio.post('/import', data: pathDto.toJson());
    return OpenToolServerDto.fromJson(response.data);
  }

  /// POST /servers/{serverId}/alias?alias=<target_alias>
  Future<OpenToolServerDto> setAliasServer(
    String serverId,
    String? alias,
  ) async {
    Map<String, dynamic>? queryParameters;
    if (alias != null && alias.isNotEmpty) {
      queryParameters = {'alias': alias};
    }
    Response response = await serverDio.post(
      '/$serverId/alias',
      queryParameters: queryParameters,
    );
    return OpenToolServerDto.fromJson(response.data);
  }

  /// Tool API： /opentool-daemon/tools ==========

  /// GET /tools/list?all=0
  Future<List<ToolDto>> listTool(String? all) async {
    Map<String, dynamic>? queryParameters;
    if (all != null && all.isNotEmpty) {
      queryParameters = {'all': all};
    }
    Response response = await toolDio.get(
      '/list',
      queryParameters: queryParameters,
    );
    List<dynamic> res = response.data;
    List<ToolDto> result = res
        .map((dyn) => ToolDto.fromJson(dyn as Map<String, dynamic>))
        .toList();
    return result;
  }

  /// POST /tools/create
  Future<CommandResultDto> runServer(
    String serverId,
    String? hostType, {
    int timeoutSeconds = -1,
  }) async {
    final Map<String, dynamic> queryParameters = {
      'serverId': serverId,
      if (hostType != null && hostType.isNotEmpty) 'hostType': hostType,
      if (timeoutSeconds >= 0) 'timeout': '$timeoutSeconds',
    };
    final completer = Completer<CommandResultDto>();
    StreamSubscription<String>? subscription;
    void completeWithError(Object error, [StackTrace? stack]) {
      if (!completer.isCompleted) {
        completer.completeError(error, stack ?? StackTrace.current);
      }
    }

    try {
      Stream<String> sseStream = await toolSse.request(
        '/create',
        queryParameters: queryParameters,
      );
      void onEvent(String event, Map<String, dynamic> data) {
        if (event == EventType.DATA && !completer.isCompleted) {
          final result = CommandResultDto.fromJson(data);
          completer.complete(result);
          subscription?.cancel();
        } else if (event == EventType.ERROR && !completer.isCompleted) {
          final result = CommandResultDto.fromJson(data);
          completeWithError(CommandException('runServer', result.error ?? ''));
          subscription?.cancel();
        }
      }

      subscription = sseStream.listen(
        (chunk) => SseClient.parse(chunk, onEvent),
        onError: completeWithError,
        cancelOnError: true,
        onDone: () {
          if (!completer.isCompleted) {
            completeWithError(
              CommandException(
                'runServer',
                'Connection closed before response',
              ),
            );
          }
        },
      );
    } catch (error, stackTrace) {
      completeWithError(error, stackTrace);
    }

    return completer.future;
  }

  /// POST /tools/{toolId}/start
  Future<void> startTool(
    String toolId, {
    required void Function(CommandResultDto commandOutput) onData,
    required void Function(CommandResultDto commandError) onError,
    void Function(Object error, StackTrace stackTrace)? onStreamError,
    int timeoutSeconds = -1,
  }) async {
    try {
      Map<String, dynamic>? queryParameters;
      if (timeoutSeconds >= 0) {
        queryParameters = {'timeout': '$timeoutSeconds'};
      }
      Stream<String> sseStream = await toolSse.request(
        '/${toolId}/start',
        queryParameters: queryParameters,
      );
      void Function(String event, Map<String, dynamic> data) onEvent =
          (String event, Map<String, dynamic> data) {
            if (event == EventType.DATA) {
              onData(CommandResultDto.fromJson(data));
            } else if (event == EventType.DONE) {
              onError(CommandResultDto.fromJson(data));
            }
          };
      sseStream.listen(
        (data) => SseClient.parse(data, onEvent),
        onError: (error, stackTrace) {
          onStreamError?.call(error, stackTrace);
        },
        cancelOnError: true,
      );
    } catch (error, stackTrace) {
      if (onStreamError != null) {
        onStreamError(error, stackTrace);
        return;
      }
      rethrow;
    }
  }

  /// POST /tools/{toolId}/stop
  Future<ToolIdDto> stopTool(String toolId) async {
    Response response = await toolDio.post('/${toolId}/stop');
    return ToolIdDto.fromJson(response.data);
  }

  /// DELETE /tools/{toolId}
  Future<ToolIdDto> deleteTool(String toolId) async {
    Response response = await toolDio.delete('/${toolId}');
    return ToolIdDto.fromJson(response.data);
  }

  /// POST /tools/{toolId}/call
  Future<ToolReturn> callTool(String toolId, FunctionCall functionCall) async {
    Response response = await toolDio.post(
      '/${toolId}/call',
      data: jsonEncode(functionCall.toJson()),
    );
    return ToolReturn.fromJson(response.data);
  }

  /// POST /tools/{toolId}/streamCall
  Future<void> streamCallTool(
    String toolId,
    FunctionCall functionCall, {
    required void Function(String event, Map<String, dynamic> data) onEvent,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    try {
      Stream<String> sseStream = await toolSse.request(
        '/${toolId}/streamCall',
        requestBody: functionCall.toJson(),
      );
      sseStream.listen(
        (data) => SseClient.parse(data, onEvent),
        onError: (error, stackTrace) {
          onError?.call(error, stackTrace);
        },
        cancelOnError: true,
      );
    } catch (error, stackTrace) {
      if (onError != null) {
        onError(error, stackTrace);
        return;
      }
      rethrow;
    }
  }

  /// GET /tools/{toolId}/load
  Future<OpenTool?> loadTool(String toolId) async {
    Response response = await toolDio.get('/${toolId}/load');
    return OpenTool.fromJson(response.data);
  }

  /// POST /tools/{toolId}/alias?alias=<target_alias>
  Future<ToolDto> setAliasTool(String toolId, String alias) async {
    Response response = await toolDio.post(
      '/${toolId}/alias',
      queryParameters: {'alias': alias},
    );
    return ToolDto.fromJson(response.data);
  }
}
