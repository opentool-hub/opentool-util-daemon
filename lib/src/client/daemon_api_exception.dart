import 'dart:convert';

import 'package:dio/dio.dart';

import '../utils/sse_client.dart';

/// Stable public error exposed by [DaemonClient].
///
/// Callers should use [code] for control flow instead of depending on Dio or
/// the daemon's JSON error envelope.
class DaemonApiException implements Exception {
  final String code;
  final String message;
  final bool retryable;
  final int? statusCode;
  final String? requestId;
  final Object? details;
  final Object? cause;

  const DaemonApiException({
    required this.code,
    required this.message,
    required this.retryable,
    this.statusCode,
    this.requestId,
    this.details,
    this.cause,
  });

  factory DaemonApiException.fromDio(DioException error) {
    final response = error.response;
    if (response != null) {
      return DaemonApiException.fromResponse(
        statusCode: response.statusCode,
        body: response.data,
        cause: error,
      );
    }
    return DaemonApiException(
      code: 'DAEMON_UNAVAILABLE',
      message: error.message ?? 'OpenTool daemon is unavailable',
      retryable: true,
      cause: error,
    );
  }

  factory DaemonApiException.fromSseRequest(SseRequestException error) =>
      DaemonApiException.fromResponse(
        statusCode: error.statusCode,
        body: error.body,
        cause: error,
      );

  factory DaemonApiException.fromResponse({
    required int? statusCode,
    required Object? body,
    Object? cause,
  }) {
    final decoded = _decodeBody(body);
    final envelope = decoded is Map ? decoded['error'] : null;
    if (envelope is Map) {
      final code = _nonEmpty(envelope['code']) ?? 'DAEMON_API_ERROR';
      final message =
          _nonEmpty(envelope['message']) ?? 'OpenTool daemon request failed';
      return DaemonApiException(
        code: code,
        message: message,
        retryable:
            envelope['retryable'] as bool? ?? _statusIsRetryable(statusCode),
        statusCode: statusCode,
        requestId: _nonEmpty(envelope['requestId']),
        details: envelope['details'],
        cause: cause,
      );
    }

    final fallback = _nonEmpty(decoded) ?? 'OpenTool daemon request failed';
    return DaemonApiException(
      code: 'DAEMON_HTTP_ERROR',
      message: fallback,
      retryable: _statusIsRetryable(statusCode),
      statusCode: statusCode,
      details: decoded,
      cause: cause,
    );
  }

  @override
  String toString() {
    final status = statusCode == null ? '' : ' HTTP $statusCode';
    final request = requestId == null ? '' : ' (requestId: $requestId)';
    return 'DaemonApiException$status [$code] $message$request';
  }
}

Object? _decodeBody(Object? body) {
  if (body is! String) return body;
  final trimmed = body.trim();
  if (trimmed.isEmpty) return null;
  try {
    return jsonDecode(trimmed);
  } on FormatException {
    return trimmed;
  }
}

String? _nonEmpty(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

bool _statusIsRetryable(int? statusCode) =>
    statusCode == null ||
    statusCode == 408 ||
    statusCode == 429 ||
    statusCode >= 500;
