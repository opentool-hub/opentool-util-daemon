import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:opentool_daemon/src/utils/zip_util.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('archivePath converts Windows filesystem paths to ZIP paths', () {
    final windows = p.Context(style: p.Style.windows);

    final archivePath = ZipUtil.archivePath(
      r'C:\src\tool',
      r'C:\src\tool\bin\demo.exe',
      context: windows,
    );

    expect(archivePath, 'bin/demo.exe');
  });

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

  test(
    'zipDirectory and extraction preserve nested executable permissions',
    () async {
      final sourceDir = await Directory.systemTemp.createTemp('zip-mode-src');
      final targetDir = await Directory.systemTemp.createTemp(
        'zip-mode-target',
      );
      String? extracted;
      try {
        await File(
          p.join(sourceDir.path, 'Opentoolfile.json'),
        ).writeAsString('{}');
        final helper = File(
          p.join(sourceDir.path, 'node_modules', 'node-pty', 'spawn-helper'),
        );
        await helper.parent.create(recursive: true);
        await helper.writeAsString('helper');
        await Process.run('chmod', ['0755', helper.path]);

        final zipPath = p.join(targetDir.path, 'server.ots');
        await ZipUtil.zipDirectory(sourceDir.path, zipPath);

        final bytes = await File(zipPath).readAsBytes();
        final decoder = ZipDecoder();
        final archive = decoder.decodeBytes(bytes);
        try {
          expect(
            decoder.directory.fileHeaders.map(
              (header) => header.versionMadeBy >> 8,
            ),
            everyElement(3),
          );
          expect(
            archive
                .findFile('node_modules/node-pty/spawn-helper')!
                .unixPermissions,
            0x1ed,
          );
        } finally {
          await archive.clear();
        }

        extracted = await ZipUtil.unzipToTemp(zipPath);
        final extractedHelper = File(
          p.join(extracted, 'node_modules', 'node-pty', 'spawn-helper'),
        );
        expect((await extractedHelper.stat()).mode & 0x1ff, 0x1ed);
      } finally {
        if (extracted != null) {
          await Directory(extracted).delete(recursive: true);
        }
        await sourceDir.delete(recursive: true);
        await targetDir.delete(recursive: true);
      }
    },
    skip: Platform.isWindows,
  );

  test('extraction strips special permission bits', () async {
    final temp = await Directory.systemTemp.createTemp('zip-safe-mode');
    String? extracted;
    try {
      final executable = ArchiveFile.string('bin/tool', 'tool')
        ..mode = 0x8000 | 0x9ed;
      final archive = Archive()
        ..addFile(ArchiveFile.string('Opentoolfile.json', '{}'))
        ..addFile(executable);
      final archivePath = p.join(temp.path, 'safe-mode.ots');
      await File(archivePath).writeAsBytes(_encodeUnixArchive(archive));

      extracted = await ZipUtil.unzipToTemp(archivePath);

      expect(
        (await File(p.join(extracted, 'bin', 'tool')).stat()).mode & 0xfff,
        0x1ed,
      );
    } finally {
      if (extracted != null) {
        await Directory(extracted).delete(recursive: true);
      }
      await temp.delete(recursive: true);
    }
  }, skip: Platform.isWindows);

  test(
    'extraction ignores permissions from non-Unix ZIP entries',
    () async {
      final temp = await Directory.systemTemp.createTemp('zip-fat-mode');
      String? extracted;
      try {
        final executable = ArchiveFile.string('bin/tool', 'tool')
          ..mode = 0x8000 | 0x1ed;
        final archive = Archive()
          ..addFile(ArchiveFile.string('Opentoolfile.json', '{}'))
          ..addFile(executable);
        final archivePath = p.join(temp.path, 'fat-mode.ots');
        await File(archivePath).writeAsBytes(ZipEncoder().encode(archive));

        extracted = await ZipUtil.unzipToTemp(archivePath);

        expect(
          (await File(p.join(extracted, 'bin', 'tool')).stat()).mode & 0x49,
          0,
        );
      } finally {
        if (extracted != null) {
          await Directory(extracted).delete(recursive: true);
        }
        await temp.delete(recursive: true);
      }
    },
    skip: Platform.isWindows,
  );

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

  test('inspect and extraction normalize Windows ZIP separators', () async {
    final temp = await Directory.systemTemp.createTemp('windows-zip');
    String? extracted;
    try {
      final archive = Archive()
        ..addFile(ArchiveFile.string('Opentoolfile.json', '{}'))
        ..addFile(ArchiveFile.string(r'bin\demo.exe', 'ready'));
      final archivePath = '${temp.path}/windows.ots';
      await File(archivePath).writeAsBytes(ZipEncoder().encode(archive));

      final inspection = await ZipUtil.inspect(archivePath);
      expect(inspection.files, contains('bin/demo.exe'));

      extracted = await ZipUtil.unzipToTemp(archivePath);
      expect(
        await File(p.join(extracted, 'bin', 'demo.exe')).readAsString(),
        'ready',
      );
    } finally {
      if (extracted != null) {
        await Directory(extracted).delete(recursive: true);
      }
      await temp.delete(recursive: true);
    }
  });

  test('inspect rejects Windows traversal and canonical duplicates', () async {
    final temp = await Directory.systemTemp.createTemp('unsafe-windows-zip');
    try {
      final traversal = Archive()
        ..addFile(ArchiveFile.string('Opentoolfile.json', '{}'))
        ..addFile(ArchiveFile.string(r'..\escape', 'unsafe'));
      final traversalPath = '${temp.path}/traversal.ots';
      await File(traversalPath).writeAsBytes(ZipEncoder().encode(traversal));
      await expectLater(
        ZipUtil.inspect(traversalPath),
        throwsA(isA<FormatException>()),
      );

      final duplicate = Archive()
        ..addFile(ArchiveFile.string('Opentoolfile.json', '{}'))
        ..addFile(ArchiveFile.string('bin/demo.exe', 'one'))
        ..addFile(ArchiveFile.string(r'bin\demo.exe', 'two'));
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

  test(
    'inspect and extraction preserve safe relative symbolic links',
    () async {
      final temp = await Directory.systemTemp.createTemp('symlink-zip');
      String? extracted;
      try {
        final archive = Archive()
          ..addFile(ArchiveFile.string('Opentoolfile.json', '{}'))
          ..addFile(ArchiveFile.string('framework/Versions/A/tool', 'ready'))
          ..addFile(_symlink('framework/Current', 'Versions/A'));
        final archivePath = '${temp.path}/safe.ots';
        await File(archivePath).writeAsBytes(_encodeUnixArchive(archive));

        final inspection = await ZipUtil.inspect(archivePath);
        expect(inspection.files, contains('framework/Current'));

        extracted = await ZipUtil.unzipToTemp(archivePath);
        expect(
          await Link(p.join(extracted, 'framework', 'Current')).target(),
          'Versions/A',
        );
        expect(
          await File(
            p.join(extracted, 'framework', 'Current', 'tool'),
          ).readAsString(),
          'ready',
        );
      } finally {
        if (extracted != null) {
          await Directory(extracted).delete(recursive: true);
        }
        await temp.delete(recursive: true);
      }
    },
  );

  test('inspect rejects symbolic links that escape the archive', () async {
    final temp = await Directory.systemTemp.createTemp('unsafe-symlink-zip');
    try {
      final archive = Archive()
        ..addFile(ArchiveFile.string('Opentoolfile.json', '{}'))
        ..addFile(_symlink('framework/Current', '../../outside'));
      final archivePath = '${temp.path}/unsafe.ots';
      await File(archivePath).writeAsBytes(_encodeUnixArchive(archive));

      await expectLater(
        ZipUtil.inspect(archivePath),
        throwsA(isA<FormatException>()),
      );
    } finally {
      await temp.delete(recursive: true);
    }
  });
}

ArchiveFile _symlink(String name, String target) {
  // Zip symlinks store their relative target as entry content and advertise
  // the POSIX symlink file type through the external mode bits.
  return ArchiveFile.string(name, target)
    ..mode = 0xa1ff
    ..symbolicLink = target;
}

List<int> _encodeUnixArchive(Archive archive) {
  final bytes = ZipEncoder().encode(archive);
  // archive's encoder currently marks central-directory records as MS-DOS,
  // while ZIP symlinks are identified only for UNIX-created records.
  for (var index = 0; index <= bytes.length - 6; index++) {
    if (bytes[index] == 0x50 &&
        bytes[index + 1] == 0x4b &&
        bytes[index + 2] == 0x01 &&
        bytes[index + 3] == 0x02) {
      bytes[index + 5] = 3;
    }
  }
  return bytes;
}
