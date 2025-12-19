import 'dart:io';

import 'package:path/path.dart' as p;

class ExecutableUtil {
  /// Resolves [entrypoint] into a runnable command string within [workdir].
  ///
  /// - On POSIX, prefers `./<entrypoint>` if a matching file exists in workdir.
  /// - On Windows, prefers `.\\<entrypoint>.exe` / `.cmd` / `.bat` when present.
  static String resolveEntrypoint(
    String workdir,
    String entrypoint, {
    bool? isWindows,
  }) {
    final bool windows = isWindows ?? Platform.isWindows;
    if (entrypoint.isEmpty) return entrypoint;

    final bool isPathLike =
        p.isAbsolute(entrypoint) ||
        entrypoint.startsWith('./') ||
        entrypoint.startsWith('../') ||
        entrypoint.startsWith('.\\') ||
        entrypoint.startsWith('..\\');
    if (isPathLike) {
      if (!windows) return entrypoint;
      if (entrypoint.startsWith('./')) {
        return '.\\${p.windows.normalize(entrypoint.substring(2))}';
      }
      return p.windows.normalize(entrypoint);
    }

    final candidates = <String>[entrypoint];
    if (windows && p.extension(entrypoint).isEmpty) {
      candidates.addAll([
        '$entrypoint.exe',
        '$entrypoint.cmd',
        '$entrypoint.bat',
      ]);
    }

    for (final candidate in candidates) {
      final candidatePath = p.join(workdir, candidate);
      if (File(candidatePath).existsSync()) {
        if (windows) {
          return '.\\${p.windows.normalize(candidate)}';
        }
        return './$candidate';
      }
    }

    return entrypoint;
  }

  /// Ensures POSIX executables are marked as executable when invoked as `./...`.
  ///
  /// No-ops on Windows.
  static Future<void> ensureExecutable(
    String entrypoint,
    String workdir, {
    bool? isWindows,
    Future<ProcessResult> Function(String executable, List<String> arguments)?
    commandRunner,
  }) async {
    final bool windows = isWindows ?? Platform.isWindows;
    if (windows) return;

    if (entrypoint.isEmpty) return;
    if (!entrypoint.startsWith('./')) return;

    final String executableName = entrypoint.substring(2);
    final String absolutePath = p.join(workdir, executableName);
    final File executable = File(absolutePath);
    if (!await executable.exists()) return;

    final FileStat stat = await executable.stat();
    final bool isExecutable = stat.mode & 0x49 != 0;
    if (isExecutable) return;

    final runner = commandRunner ?? ((cmd, args) => Process.run(cmd, args));
    await runner('chmod', ['+x', absolutePath]);
  }
}
