import 'dart:io';

import 'package:opentool_daemon/src/service/exception.dart';
import 'package:opentool_daemon/src/utils/platform_detector.dart';
import 'package:test/test.dart';

void main() {
  test('maps supported OS and architecture to Hub platform values', () async {
    final platform = await PlatformDetector(
      operatingSystem: 'windows',
      abiName: 'windows_x64',
    ).detect();

    expect(platform.os, 'windows');
    expect(platform.arch, 'x64');
    expect(platform.abi, 'native');
  });

  test('detects Linux musl from ldd output', () async {
    final platform = await PlatformDetector(
      operatingSystem: 'linux',
      abiName: 'linux_arm64',
      environment: const {},
      linuxLibraryDirectories: const [],
      processRunner: (_, _) async => ProcessResult(1, 0, 'musl libc', ''),
    ).detect();

    expect(platform.arch, 'arm64');
    expect(platform.abi, 'musl');
  });

  test('honors explicit Linux ABI and rejects unsupported platforms', () async {
    final linux = await PlatformDetector(
      operatingSystem: 'linux',
      abiName: 'linux_x64',
      environment: const {'OPENTOOL_LINUX_ABI': 'glibc'},
    ).detect();
    expect(linux.abi, 'glibc');

    await expectLater(
      PlatformDetector(
        operatingSystem: 'android',
        abiName: 'android_arm64',
      ).detect(),
      throwsA(
        isA<ArtifactOperationException>().having(
          (error) => error.code,
          'code',
          'PLATFORM_NOT_SUPPORTED',
        ),
      ),
    );
  });
}
