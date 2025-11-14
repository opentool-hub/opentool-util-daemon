import 'dart:io';
import 'package:opentool_daemon/src/utils/zip_util.dart';
import 'package:test/test.dart';

void main() {
  test('zipDirectory creates parent directories for the target file', () async {
    final sourceDir = await Directory.systemTemp.createTemp('zip-src');
    final nested = File('${sourceDir.path}/hello.txt');
    await nested.writeAsString('hello');

    final targetDir = await Directory.systemTemp.createTemp('zip-target');
    final zipPath = '${targetDir.path}/nested/path/archive.ots';

    await ZipUtil.zipDirectory(sourceDir.path, zipPath);

    expect(await File(zipPath).exists(), isTrue);

    await sourceDir.delete(recursive: true);
    await Directory(targetDir.path).delete(recursive: true);
  });
}
