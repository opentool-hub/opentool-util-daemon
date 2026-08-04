import 'dart:io';

import 'package:opentool_daemon/src/version.dart';
import 'package:test/test.dart';

void main() {
  test('compiled fallback version matches pubspec', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    final match = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull);
    expect(packageVersion, match!.group(1));
    expect(daemonVersion, packageVersion);
  });
}
