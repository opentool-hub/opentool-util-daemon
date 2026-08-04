import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
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

  test('inspect rejects paths that escape the extraction directory', () async {
    final temp = await Directory.systemTemp.createTemp('unsafe-zip');
    final archive = Archive()
      ..addFile(
        ArchiveFile.string('Opentoolfile.json', jsonEncode({'name': 'demo'})),
      )
      ..addFile(ArchiveFile.string('../escape', 'unsafe'));
    final path = '${temp.path}/unsafe.ots';
    await File(path).writeAsBytes(ZipEncoder().encode(archive));

    await expectLater(ZipUtil.inspect(path), throwsA(isA<FormatException>()));
    expect(await File('${temp.parent.path}/escape').exists(), isFalse);
    await temp.delete(recursive: true);
  });

  test('inspect rejects missing and duplicate root manifests', () async {
    final temp = await Directory.systemTemp.createTemp('manifest-zip');
    try {
      final missing = Archive()
        ..addFile(ArchiveFile.string('tool', 'executable'));
      final missingPath = '${temp.path}/missing.ots';
      await File(missingPath).writeAsBytes(ZipEncoder().encode(missing));
      await expectLater(
        ZipUtil.inspect(missingPath),
        throwsA(isA<FormatException>()),
      );

      final duplicate = Archive()
        ..addFile(ArchiveFile.string('Opentoolfile.json', '{}'))
        ..addFile(ArchiveFile.string('dir/../Opentoolfile.json', '{}'));
      final duplicatePath = '${temp.path}/duplicate.ots';
      await File(duplicatePath).writeAsBytes(ZipEncoder().encode(duplicate));
      await expectLater(
        ZipUtil.inspect(duplicatePath),
        throwsA(isA<FormatException>()),
      );
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
