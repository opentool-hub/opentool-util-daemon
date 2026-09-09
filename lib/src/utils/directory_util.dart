import 'dart:io';
import 'package:path/path.dart' as p;

class UserHomeDirectoryNotFoundException implements Exception {
  int code = 404;
  late String message;

  UserHomeDirectoryNotFoundException() {
    this.message = 'User Home Directory NOT found';
  }

  @override
  String toString() {
    return 'UserHomeDirectoryNotFoundException: $message';
  }
}

class FileNotFoundException implements Exception {
  int code = 404;
  late String message;

  FileNotFoundException(String filePath) {
    this.message = 'File NOT found: $filePath';
  }

  @override
  String toString() {
    return 'FileNotFoundException: $message';
  }
}

class DirectoryUtil {
  static const int _windowsDeleteMaxAttempts = 7;
  static const Duration _windowsDeleteInitialDelay = Duration(milliseconds: 50);

  static String getBaseDir() {
    // Debug mode check using assert
    String? debugDir;

    assert(() {
      debugDir = Directory.current.path;
      return true;
    }());

    // Debug return project directory
    if (debugDir != null) return debugDir!;

    // Release return user home directory
    return getUserHomeDir();
  }

  static String getUserHomeDir() {
    // macOS / Linux
    if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) return home;
    }

    // Windows
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) return userProfile;

      // Compatibility
      final homeDrive = Platform.environment['HOMEDRIVE'];
      final homePath = Platform.environment['HOMEPATH'];
      if (homeDrive != null && homePath != null) {
        return '$homeDrive$homePath';
      }
    }
    throw UserHomeDirectoryNotFoundException();
  }

  static Future<void> deleteDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    var retryDelay = _windowsDeleteInitialDelay;
    for (var attempt = 1; attempt <= _windowsDeleteMaxAttempts; attempt++) {
      if (!await dir.exists()) return;
      try {
        await dir.delete(recursive: true);
        return;
      } on FileSystemException catch (error) {
        if (!isRetryableWindowsDeleteError(error) ||
            attempt == _windowsDeleteMaxAttempts) {
          rethrow;
        }
        await Future<void>.delayed(retryDelay);
        retryDelay = Duration(milliseconds: retryDelay.inMilliseconds * 2);
      }
    }
  }

  static bool isRetryableWindowsDeleteError(FileSystemException error) {
    if (!Platform.isWindows) return false;
    // ERROR_ACCESS_DENIED, ERROR_SHARING_VIOLATION, ERROR_DIR_NOT_EMPTY.
    // All three can be transient while a just-stopped process releases its
    // executable, loaded DLLs, or working directory.
    return const {5, 32, 145}.contains(error.osError?.errorCode);
  }

  static String getParentDir(String filePath) {
    return Directory(filePath).parent.path;
  }

  static Future<void> copyDirectory(
    Directory source,
    Directory destination,
  ) async {
    if (!await destination.exists()) {
      await destination.create(recursive: true);
    }

    await for (var entity in source.list(recursive: false)) {
      if (entity is Directory) {
        final newDir = Directory(
          p.join(destination.path, p.basename(entity.path)),
        );
        await copyDirectory(entity, newDir);
      } else if (entity is File) {
        final newFile = File(p.join(destination.path, p.basename(entity.path)));
        await newFile.parent.create(recursive: true);
        await entity.copy(newFile.path);
      }
    }
  }

  static Future<void> deleteFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<void> copyAndRenameFile(
    String sourcePath,
    String targetPath,
  ) async {
    final sourceFile = File(sourcePath);
    final targetFile = File(targetPath);

    if (!await sourceFile.exists()) {
      throw FileNotFoundException(sourcePath);
    }

    await targetFile.parent.create(recursive: true);

    await sourceFile.copy(targetFile.path);
  }
}
