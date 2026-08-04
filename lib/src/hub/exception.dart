class HubApiException implements Exception {
  final String code;
  final String message;
  final int? statusCode;
  final bool retryable;
  final String? requestId;

  const HubApiException({
    required this.code,
    required this.message,
    required this.retryable,
    this.statusCode,
    this.requestId,
  });

  @override
  String toString() => 'HubApiException($code): $message';
}
