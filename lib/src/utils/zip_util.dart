import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';

class ZipUtil {
  static Future<void> zipDirectory(
    String sourceDirPath,
    String zipFilePath,
  ) async {
    final sourceDir = Directory(sourceDirPath);
    if (!await sourceDir.exists()) {
      throw Exception('Source directory does not exist: $sourceDirPath');
    }

    final encoder = ZipEncoder();
    final archive = Archive();

    await for (var entity in sourceDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        final relativePath = p.relative(entity.path, from: sourceDirPath);
        final data = await entity.readAsBytes();
        archive.addFile(ArchiveFile(relativePath, data.length, data));
      }
    }

    final zipData = encoder.encode(archive);
    final zipFile = File(zipFilePath);
    await zipFile.parent.create(recursive: true);
    await zipFile.writeAsBytes(zipData);
  }

  static Future<String> unzipToTemp(String zipFilePath) async {
    final sourceFile = File(zipFilePath);
    if (!await sourceFile.exists()) {
      throw Exception('Source file not found: $zipFilePath');
    }

    /// 1. Create Temp Directory
    final tmpDir = await Directory.systemTemp.createTemp('opentool_unpack_');
    final extractDir = p.join(
      tmpDir.path,
      p.basenameWithoutExtension(zipFilePath),
    );
    await Directory(extractDir).create(recursive: true);

    /// 2. Unzip
    final bytes = await sourceFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      final filePath = p.join(extractDir, file.name);
      if (file.isFile) {
        final outFile = File(filePath);
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        await Directory(filePath).create(recursive: true);
      }
    }

    return extractDir;
  }
}
