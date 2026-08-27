class ServerNotFoundException implements Exception {
  String id;
  late String message;

  ServerNotFoundException(this.id) {
    this.message = 'Server with id $id not found';
  }

  @override
  String toString() {
    return 'ServerNotFoundException: $message';
  }
}

class ToolNotFoundException implements Exception {
  String id;
  late String message;

  ToolNotFoundException(this.id) {
    this.message = 'Tool with id $id not found';
  }

  @override
  String toString() {
    return 'ToolNotFoundException: $message';
  }
}

class ToolRestartConflictException implements Exception {
  final String toolId;
  final String message;

  ToolRestartConflictException(this.toolId, this.message);

  @override
  String toString() => 'ToolRestartConflictException: $toolId - $message';
}

class ToolEndpointConflictException implements Exception {
  final String toolId;
  final String host;
  final int port;
  final List<int> listeningPids;

  const ToolEndpointConflictException({
    required this.toolId,
    required this.host,
    required this.port,
    this.listeningPids = const [],
  });

  @override
  String toString() {
    final pidDetail = listeningPids.isEmpty
        ? ''
        : ', listeningPids: ${listeningPids.join(',')}';
    return 'ToolEndpointConflictException: $toolId - $host:$port rejected '
        'the Tool credential (HTTP 401)$pidDetail';
  }
}

class OpentoolfileMissingArgumentException implements Exception {
  late String message;

  OpentoolfileMissingArgumentException(String argName) {
    this.message = '$argName is missing';
  }

  @override
  String toString() {
    return 'OpentoolfileMissingArgumentException: $message';
  }
}

class SystemMismatchException extends ArtifactOperationException {
  SystemMismatchException(
    String nativeOs,
    String nativeCpuArch,
    String remoteOs,
    String remoteCpuArch, {
    String? nativeAbi,
    String? remoteAbi,
  }) : super(
         code: 'PLATFORM_MISMATCH',
         message: _platformMismatchMessage(
           nativeOs,
           nativeCpuArch,
           remoteOs,
           remoteCpuArch,
           nativeAbi: nativeAbi,
           remoteAbi: remoteAbi,
         ),
         retryable: false,
       );

  static String _platformMismatchMessage(
    String nativeOs,
    String nativeCpuArch,
    String remoteOs,
    String remoteCpuArch, {
    String? nativeAbi,
    String? remoteAbi,
  }) {
    final nativePlatform = nativeAbi == null
        ? '$nativeOs-$nativeCpuArch'
        : '$nativeOs-$nativeCpuArch-$nativeAbi';
    final remotePlatform = remoteAbi == null
        ? '$remoteOs-$remoteCpuArch'
        : '$remoteOs-$remoteCpuArch-$remoteAbi';
    return 'Server platform $remotePlatform is not compatible with this '
        'device ($nativePlatform). Import an .ots file built for '
        '$nativePlatform.';
  }

  @override
  String toString() => 'SystemMismatchException: $message';
}

class ApiKeyNotFoundException implements Exception {
  final String id;

  ApiKeyNotFoundException(this.id);

  @override
  String toString() => 'ApiKeyNotFoundException: $id';
}

class SudoAuthorizationException implements Exception {
  final String message;

  SudoAuthorizationException(this.message);

  @override
  String toString() => 'SudoAuthorizationException: $message';
}

class ArtifactOperationException implements Exception {
  final String code;
  final String message;
  final bool retryable;
  final String? requestId;

  const ArtifactOperationException({
    required this.code,
    required this.message,
    required this.retryable,
    this.requestId,
  });

  @override
  String toString() => 'ArtifactOperationException($code): $message';
}

class ServerPolicyException extends ArtifactOperationException {
  const ServerPolicyException({required super.code, required super.message})
    : super(retryable: false);
}
