import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:opentool_daemon/opentool_daemon_utils.dart';
import 'package:opentool_daemon/opentool_daemon_server.dart';
import 'package:opentool_dart/opentool_client.dart';
import '../service/model.dart';
import 'daemon_api_exception.dart';
import 'pull_event.dart';

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

  Future<T> _guardApi<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } catch (error, stackTrace) {
      final normalized = _normalizeError(error);
      if (identical(normalized, error)) rethrow;
      Error.throwWithStackTrace(normalized, stackTrace);
    }
  }

  Object _normalizeError(Object error) {
    if (error is DaemonApiException) return error;
    if (error is DioException) return DaemonApiException.fromDio(error);
    if (error is SseRequestException) {
      return DaemonApiException.fromSseRequest(error);
    }
    if (error is SocketException) {
      return DaemonApiException(
        code: 'DAEMON_UNAVAILABLE',
        message: error.message,
        retryable: true,
        cause: error,
      );
    }
    return error;
  }

  /// Manage API： /opentool-daemon ==========

  Options _sudoOptions(String sudoToken) =>
      Options(headers: {...manageDio.options.headers, _sudoHeader: sudoToken});

  static const String _sudoHeader = 'x-opentool-sudo-token';

  /// GET /version
  Future<VersionDto> getVersion() => _guardApi(() async {
    final response = await manageDio.get('/version');
    return VersionDto.fromJson(response.data as Map<String, dynamic>);
  });

  /// POST /apiKey
  Future<ApiKeyDto> createApiKey({required String sudoToken, String? name}) =>
      _guardApi(() async {
        final data = name == null ? null : CreateApiKeyDto(name: name).toJson();
        final response = await manageDio.post(
          '/apiKey',
          data: data,
          options: _sudoOptions(sudoToken),
        );
        return ApiKeyDto.fromJson(response.data as Map<String, dynamic>);
      });

  /// GET /apiKeys
  Future<List<ApiKeyDto>> listApiKeys({required String sudoToken}) =>
      _guardApi(() async {
        final response = await manageDio.get(
          '/apiKeys',
          options: _sudoOptions(sudoToken),
        );
        final res = response.data as List<dynamic>;
        return res
            .map((e) => ApiKeyDto.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  /// DELETE /apiKey/{apiKey}
  Future<void> deleteApiKey({
    required String sudoToken,
    required String apiKey,
  }) => _guardApi(() async {
    await manageDio.delete('/apiKey/$apiKey', options: _sudoOptions(sudoToken));
  });

  /// Server API： /opentool-daemon/servers ==========

  /// GET /servers/list
  Future<List<OpenToolServerDto>> listServer() => _guardApi(() async {
    Response response = await serverDio.get('/list');
    List<dynamic> res = response.data;
    List<OpenToolServerDto> result = res
        .map((dyn) => OpenToolServerDto.fromJson(dyn as Map<String, dynamic>))
        .toList();
    return result;
  });

  /// POST /servers/build
  Future<void> buildServer(
    BuildInfoDto buildInfoDto, {
    required void Function(EventMessageDto startMessage) onStart,
    required void Function(CommandOutputDto commandOutput) onData,
    required void Function(EventMessageDto doneMessage) onDone,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    try {
      final sseStream = await serverSse.request(
        '/build',
        queryParameters: buildInfoDto.toJson(),
      );
      var terminalReceived = false;
      await for (final chunk in sseStream) {
        DaemonApiException? terminalError;
        SseClient.parse(chunk, (event, data) {
          switch (event) {
            case EventType.START:
              onStart(EventMessageDto.fromJson(data));
            case EventType.DATA:
              onData(CommandOutputDto.fromJson(data));
            case EventType.DONE:
              terminalReceived = true;
              onDone(EventMessageDto.fromJson(data));
            case EventType.ERROR:
              terminalReceived = true;
              terminalError = DaemonApiException.fromResponse(
                statusCode: data['status'] as int?,
                body: {'error': data},
              );
          }
        });
        if (terminalError != null) throw terminalError!;
        if (terminalReceived) return;
      }
      if (!terminalReceived) {
        throw const SseProtocolException(
          'Build stream closed before a terminal done or error event',
        );
      }
    } catch (error, stackTrace) {
      final normalized = _normalizeError(error);
      if (onError != null) {
        onError(normalized, stackTrace);
        return;
      }
      if (identical(normalized, error)) rethrow;
      Error.throwWithStackTrace(normalized, stackTrace);
    }
  }

  /// DELETE /servers/{server_id}
  Future<ServerIdDto> deleteServer(String serverId) => _guardApi(() async {
    final response = await serverDio.delete('/$serverId');
    return ServerIdDto.fromJson(response.data as Map<String, dynamic>);
  });

  /// DELETE /servers/{server_id}, including artifact cleanup information.
  Future<ServerDeleteResultDto> deleteServerDetailed(String serverId) =>
      _guardApi(() async {
        final response = await serverDio.delete('/$serverId');
        return ServerDeleteResultDto.fromJson(
          response.data as Map<String, dynamic>,
        );
      });

  /// POST /servers/pull
  Future<void> pullServer(
    PullInfoDto pullInfo, {
    required void Function(PullStartDto pullStart) onStart,
    required void Function(PullDownloadDto pullDownload) onDownload,
    required void Function(PullDoneDto result) onDone,
    required void Function(PullErrorDto error) onPullError,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    try {
      await for (final event in pullServerEvents(pullInfo)) {
        switch (event) {
          case PullStarted(:final data):
            onStart(data);
          case PullProgress(:final data):
            onDownload(data);
          case PullCompleted(:final data):
            onDone(data);
          case PullFailed(:final data):
            onPullError(data);
        }
      }
    } catch (error, stackTrace) {
      final normalized = _normalizeError(error);
      if (onError != null) {
        onError(normalized, stackTrace);
        return;
      }
      if (identical(normalized, error)) rethrow;
      Error.throwWithStackTrace(normalized, stackTrace);
    }
  }

  /// A typed pull stream. Cancelling the subscription closes the underlying
  /// HTTP request, which in turn triggers daemon-side pull cancellation.
  Stream<PullEvent> pullServerEvents(PullInfoDto pullInfo) async* {
    final Stream<String> sseStream;
    try {
      sseStream = await serverSse.request(
        '/pull',
        requestBody: pullInfo.toJson(),
      );
    } catch (error, stackTrace) {
      final normalized = _normalizeError(error);
      if (identical(normalized, error)) rethrow;
      Error.throwWithStackTrace(normalized, stackTrace);
    }

    var terminalReceived = false;
    try {
      await for (final chunk in sseStream) {
        final events = <PullEvent>[];
        SseClient.parse(chunk, (event, data) {
          switch (event) {
            case EventType.START:
              events.add(PullStarted(PullStartDto.fromJson(data)));
            case EventType.DATA:
              events.add(PullProgress(PullDownloadDto.fromJson(data)));
            case EventType.DONE:
              terminalReceived = true;
              events.add(PullCompleted(PullDoneDto.fromJson(data)));
            case EventType.ERROR:
              terminalReceived = true;
              events.add(PullFailed(PullErrorDto.fromJson(data)));
          }
        });
        for (final event in events) {
          yield event;
        }
        if (terminalReceived) return;
      }
    } catch (error, stackTrace) {
      final normalized = _normalizeError(error);
      if (identical(normalized, error)) rethrow;
      Error.throwWithStackTrace(normalized, stackTrace);
    }
    if (!terminalReceived) {
      throw const SseProtocolException(
        'Pull stream closed before a terminal done or error event',
      );
    }
  }

  /// GET /servers/{serverId}/export
  Future<ServerIdDto> exportServer(String serverId, String targetPath) =>
      _guardApi(() async {
        PathDto pathDto = PathDto(path: targetPath);
        Response response = await serverDio.get(
          '/$serverId/export',
          data: pathDto.toJson(),
        );
        return ServerIdDto.fromJson(response.data as Map<String, dynamic>);
      });

  /// POST /servers/import
  Future<OpenToolServerDto> importServer(
    String sourcePath,
  ) => _guardApi(() async {
    PathDto pathDto = PathDto(path: sourcePath);
    Response response = await serverDio.post('/import', data: pathDto.toJson());
    return OpenToolServerDto.fromJson(response.data as Map<String, dynamic>);
  });

  /// POST /servers/{serverId}/alias?alias=<target_alias>
  Future<OpenToolServerDto> setAliasServer(String serverId, String? alias) =>
      _guardApi(() async {
        Map<String, dynamic>? queryParameters;
        if (alias != null && alias.isNotEmpty) {
          queryParameters = {'alias': alias};
        }
        Response response = await serverDio.post(
          '/$serverId/alias',
          queryParameters: queryParameters,
        );
        return OpenToolServerDto.fromJson(
          response.data as Map<String, dynamic>,
        );
      });

  /// Tool API： /opentool-daemon/tools ==========

  /// GET /tools/list?all=0
  Future<List<ToolDto>> listTool(String? all) => _guardApi(() async {
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
  });

  /// GET /tools/listWithApiKeys?all=0
  Future<List<ToolWithApiKeyDto>> listToolWithApiKeys(
    String? all, {
    required String daemonApiKey,
  }) => _guardApi(() async {
    Map<String, dynamic>? queryParameters;
    if (all != null && all.isNotEmpty) {
      queryParameters = {'all': all};
    }
    final response = await toolDio.get(
      '/listWithApiKeys',
      queryParameters: queryParameters,
      options: Options(
        headers: {
          ...toolDio.options.headers,
          TOOL_API_KEY_HEADER: daemonApiKey,
        },
      ),
    );
    final res = response.data as List<dynamic>;
    return res
        .map((dyn) => ToolWithApiKeyDto.fromJson(dyn as Map<String, dynamic>))
        .toList();
  });

  /// GET /tools/events?snapshot=1
  Future<Stream<ToolLifecycleEventDto>> subscribeToolEvents({
    String? daemonApiKey,
    String? hostToken,
    bool snapshot = true,
  }) => _guardApi(() async {
    if ((daemonApiKey == null || daemonApiKey.isEmpty) &&
        (hostToken == null || hostToken.isEmpty)) {
      throw ArgumentError('daemonApiKey or hostToken is required');
    }
    final sseStream = await toolSse.request(
      '/events',
      queryParameters: {'snapshot': snapshot ? '1' : '0'},
      method: 'GET',
      headers: {
        if (daemonApiKey != null && daemonApiKey.isNotEmpty)
          TOOL_API_KEY_HEADER: daemonApiKey,
        if (hostToken != null && hostToken.isNotEmpty)
          HOST_MANAGEMENT_TOKEN_HEADER: hostToken,
      },
    );

    return sseStream.transform(
      StreamTransformer<String, ToolLifecycleEventDto>.fromHandlers(
        handleData: (chunk, sink) {
          SseClient.parse(chunk, (event, data) {
            if (event == 'ready') return;
            if (event == ToolLifecycleEventType.SNAPSHOT ||
                event == ToolLifecycleEventType.READY ||
                event == ToolLifecycleEventType.DRAINING ||
                event == ToolLifecycleEventType.UNAVAILABLE ||
                event == ToolLifecycleEventType.REMOVED) {
              sink.add(ToolLifecycleEventDto.fromJson(data));
            }
          });
        },
      ),
    );
  });

  /// POST /tools/create
  Future<CommandResultDto> runServer(
    String serverId,
    String? hostType, {
    int timeoutSeconds = -1,
    List<String>? extraCmds,
  }) async {
    final Map<String, dynamic> queryParameters = {
      'serverId': serverId,
      if (hostType != null && hostType.isNotEmpty) 'hostType': hostType,
      if (timeoutSeconds >= 0) 'timeout': '$timeoutSeconds',
    };
    final Map<String, dynamic>? requestBody =
        extraCmds != null && extraCmds.isNotEmpty ? {'args': extraCmds} : null;
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
        requestBody: requestBody,
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

    try {
      return await completer.future;
    } catch (error, stackTrace) {
      final normalized = _normalizeError(error);
      if (identical(normalized, error)) rethrow;
      Error.throwWithStackTrace(normalized, stackTrace);
    }
  }

  /// POST /tools/{toolId}/start
  Future<void> startTool(
    String toolId, {
    required void Function(CommandResultDto commandOutput) onData,
    required void Function(CommandResultDto commandError) onError,
    void Function(Object error, StackTrace stackTrace)? onStreamError,
    int timeoutSeconds = -1,
  }) async {
    var terminalErrorReported = false;
    try {
      final queryParameters = <String, dynamic>{
        if (timeoutSeconds >= 0) 'timeout': '$timeoutSeconds',
      };
      final sseStream = await toolSse.request(
        '/${toolId}/start',
        queryParameters: queryParameters,
      );
      var terminalReceived = false;
      await for (final chunk in sseStream) {
        DaemonApiException? terminalError;
        SseClient.parse(chunk, (event, data) {
          final result = CommandResultDto.fromJson(data);
          if (event == EventType.DATA) {
            onData(result);
          } else if (event == EventType.DONE) {
            terminalReceived = true;
          } else if (event == EventType.ERROR) {
            terminalReceived = true;
            terminalErrorReported = true;
            onError(result);
            terminalError = DaemonApiException(
              code: 'TOOL_START_FAILED',
              message: result.error ?? 'OpenTool start failed',
              retryable: false,
              details: result.toJson(),
            );
          }
        });
        if (terminalError != null) throw terminalError!;
        if (terminalReceived) return;
      }
      if (!terminalReceived) {
        throw const SseProtocolException(
          'Start stream closed before a terminal done or error event',
        );
      }
    } catch (error, stackTrace) {
      final normalized = _normalizeError(error);
      if (!terminalErrorReported && onStreamError != null) {
        onStreamError(normalized, stackTrace);
      }
      if (identical(normalized, error)) rethrow;
      Error.throwWithStackTrace(normalized, stackTrace);
    }
  }

  /// POST /tools/{toolId}/stop
  Future<ToolIdDto> stopTool(String toolId) => _guardApi(() async {
    Response response = await toolDio.post('/${toolId}/stop');
    return ToolIdDto.fromJson(response.data as Map<String, dynamic>);
  });

  /// DELETE /tools/{toolId}
  Future<ToolIdDto> deleteTool(String toolId) => _guardApi(() async {
    Response response = await toolDio.delete('/${toolId}');
    return ToolIdDto.fromJson(response.data as Map<String, dynamic>);
  });

  /// POST /tools/{toolId}/call
  Future<ToolReturn> callTool(String toolId, FunctionCall functionCall) =>
      _guardApi(() async {
        Response response = await toolDio.post(
          '/${toolId}/call',
          data: jsonEncode(functionCall.toJson()),
        );
        return ToolReturn.fromJson(response.data as Map<String, dynamic>);
      });

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
          onError?.call(_normalizeError(error), stackTrace);
        },
        cancelOnError: true,
      );
    } catch (error, stackTrace) {
      final normalized = _normalizeError(error);
      if (onError != null) {
        onError(normalized, stackTrace);
        return;
      }
      if (identical(normalized, error)) rethrow;
      Error.throwWithStackTrace(normalized, stackTrace);
    }
  }

  /// GET /tools/{toolId}/load
  Future<OpenTool?> loadTool(String toolId) => _guardApi(() async {
    Response response = await toolDio.get('/${toolId}/load');
    return OpenTool.fromJson(response.data as Map<String, dynamic>);
  });

  /// POST /tools/{toolId}/alias?alias=<target_alias>
  Future<ToolDto> setAliasTool(String toolId, String alias) =>
      _guardApi(() async {
        Response response = await toolDio.post(
          '/${toolId}/alias',
          queryParameters: {'alias': alias},
        );
        return ToolDto.fromJson(response.data as Map<String, dynamic>);
      });
}
