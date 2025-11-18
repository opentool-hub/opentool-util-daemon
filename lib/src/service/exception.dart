class ServerNotFoundException implements Exception {
  String id;
  late String message ;

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
  late String message ;

  ToolNotFoundException(this.id) {
    this.message = 'Tool with id $id not found';
  }

  @override
  String toString() {
    return 'ToolNotFoundException: $message';
  }
}

class OpentoolfileMissingArgumentException implements Exception {
  late String message ;

  OpentoolfileMissingArgumentException(String argName) {
    this.message = '$argName is missing';
  }

  @override
  String toString() {
    return 'OpentoolfileMissingArgumentException: $message';
  }
}

class LoginFailedException implements Exception {
  late String message ;

  LoginFailedException(String username) {
    this.message = 'Login failed: $username';
  }

  @override
  String toString() {
    return 'LoginFailedException: $message';
  }
}

class LoginRequiredException implements Exception {
  late String message ;

  LoginRequiredException() {
    this.message = 'Login Required';
  }

  @override
  String toString() {
    return 'LoginRequiredException: $message';
  }
}

class SystemMismatchException implements Exception {
  late String message ;

  SystemMismatchException(String nativeOs, String nativeCpuArch, String remoteOs, String remoteCpuArch) {
    this.message = 'System mismatch - native: $nativeOs-$nativeCpuArch, remote: $remoteOs-$remoteCpuArch';
  }

  @override
  String toString() {
    return 'SystemMismatchException: $message';
  }
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
