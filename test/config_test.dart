import 'dart:convert';
import 'dart:io';

import 'package:opentool_daemon/src/config.dart';
import 'package:opentool_daemon/src/version.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('daemon config', () {
    test('explicit config supports partial overrides', () async {
      final temp = await Directory.systemTemp.createTemp('daemon_config_');
      final path = p.join(temp.path, 'daemon.json');
      await File(path).writeAsString(
        jsonEncode({
          'server': {'port': 20000},
        }),
      );
      try {
        final loaded = initConfig(configFilePath: path, strict: true);

        expect(loaded.version, daemonVersion);
        expect(loaded.server?.host, '127.0.0.1');
        expect(loaded.server?.port, 20000);
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test('explicit missing config fails instead of silently falling back', () {
      expect(
        () => initConfig(
          configFilePath: '/definitely/missing/opentool-daemon.json',
          strict: true,
        ),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('parses both supported config argument forms', () {
      expect(
        configPathFromArgs(['--config', '/tmp/daemon.json']),
        '/tmp/daemon.json',
      );
      expect(
        configPathFromArgs(['--config=/tmp/daemon.json']),
        '/tmp/daemon.json',
      );
      expect(configPathFromArgs(['--auto-restore']), isNull);
      expect(
        () => configPathFromArgs(['--config']),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
