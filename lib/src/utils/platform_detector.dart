import 'dart:ffi';
import 'dart:io';

import '../service/exception.dart';
import '../service/model.dart';

class PlatformDetector {
  final Map<String, String> environment;
  final String operatingSystem;
  final String abiName;
  final List<String> linuxLibraryDirectories;
  final Future<ProcessResult> Function(String executable, List<String> args)
  _processRunner;

  PlatformDetector({
    Map<String, String>? environment,
    String? operatingSystem,
    String? abiName,
    this.linuxLibraryDirectories = const ['/lib', '/usr/lib'],
    Future<ProcessResult> Function(String executable, List<String> args)?
    processRunner,
  }) : environment = environment ?? Platform.environment,
       operatingSystem = operatingSystem ?? Platform.operatingSystem,
       abiName = abiName ?? Abi.current().toString().toLowerCase(),
       _processRunner = processRunner ?? Process.run;

  Future<ServerPlatform> detect() async {
    final os = operatingSystem;
    if (os != 'macos' && os != 'windows' && os != 'linux') {
      throw ArtifactOperationException(
        code: 'PLATFORM_NOT_SUPPORTED',
        message: 'Unsupported operating system: $os',
        retryable: false,
      );
    }

    final String arch;
    if (abiName.contains('arm64')) {
      arch = 'arm64';
    } else if (abiName.contains('x64')) {
      arch = 'x64';
    } else {
      throw ArtifactOperationException(
        code: 'PLATFORM_NOT_SUPPORTED',
        message: 'Unsupported CPU architecture: $abiName',
        retryable: false,
      );
    }

    return ServerPlatform(
      os: os,
      arch: arch,
      abi: os == 'linux' ? await _detectLinuxAbi() : 'native',
    );
  }

  Future<String> _detectLinuxAbi() async {
    final configured = environment['OPENTOOL_LINUX_ABI']?.trim().toLowerCase();
    if (configured == 'glibc' || configured == 'musl') return configured!;
    try {
      final result = await _processRunner('ldd', const ['--version']);
      final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
      if (output.contains('musl')) return 'musl';
      if (output.contains('glibc') ||
          output.contains('gnu libc') ||
          output.contains('gnu c library')) {
        return 'glibc';
      }
    } catch (_) {}

    for (final directory in linuxLibraryDirectories) {
      try {
        if (await Directory(
          directory,
        ).list().any((entity) => entity.path.contains('ld-musl-'))) {
          return 'musl';
        }
      } catch (_) {}
    }
    throw const ArtifactOperationException(
      code: 'PLATFORM_NOT_SUPPORTED',
      message:
          'Unable to determine Linux ABI; set OPENTOOL_LINUX_ABI to glibc or musl',
      retryable: false,
    );
  }
}
