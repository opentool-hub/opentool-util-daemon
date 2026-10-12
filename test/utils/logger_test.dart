import 'dart:io';

import 'package:opentool_daemon/src/utils/logger.dart';
import 'package:test/test.dart';

void main() {
  test('rotates daemon log and keeps only configured backups', () {
    final dir = Directory.systemTemp.createTempSync('daemon-log-test-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/daemon.log');
    final writer = DaemonLogFileWriter(file, maxBytes: 11, backupCount: 2);

    writer.writeLine('one');
    writer.writeLine('two');
    writer.writeLine('three');
    writer.writeLine('four');
    writer.writeLine('five');

    expect(file.readAsStringSync(), 'five\n');
    expect(File('${file.path}.1').readAsStringSync(), 'three\nfour\n');
    expect(File('${file.path}.2').readAsStringSync(), 'one\ntwo\n');
    expect(File('${file.path}.3').existsSync(), isFalse);
  });

  test('rotates an already oversized log on the next write', () {
    final dir = Directory.systemTemp.createTempSync('daemon-log-test-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/daemon.log')
      ..writeAsStringSync('existing data\n');
    final writer = DaemonLogFileWriter(file, maxBytes: 8, backupCount: 1);

    writer.writeLine('new');

    expect(file.readAsStringSync(), 'new\n');
    expect(File('${file.path}.1').readAsStringSync(), 'existing data\n');
  });
}
