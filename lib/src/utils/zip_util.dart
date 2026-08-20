import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../constants.dart';

class ZipInspection {
  final Map<String, dynamic> manifest;
  final Set<String> files;

  const ZipInspection({required this.manifest, required this.files});
}

class ZipUtil {
  static const int maxArchiveEntries = 50000;
  static const int maxUncompressedSize = 2 * 1024 * 1024 * 1024;
  static const int maxManifestSize = 1024 * 1024;

  static String archivePath(
    String sourcePath,
    String entityPath, {
    p.Context? context,
  }) {
    final pathContext = context ?? p.context;
    final relativePath = pathContext.relative(entityPath, from: sourcePath);
    return p.posix.joinAll(pathContext.split(relativePath));
  }

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
        final relativePath = archivePath(sourceDirPath, entity.path);
        final data = await entity.readAsBytes();
        archive.addFile(ArchiveFile(relativePath, data.length, data));
      }
    }

    final zipData = encoder.encode(archive);
    final zipFile = File(zipFilePath);
    await zipFile.parent.create(recursive: true);
    await zipFile.writeAsBytes(zipData);
  }

  static Future<ZipInspection> inspect(String zipFilePath) async {
    final decoded = await _decodeAndValidate(zipFilePath);
    try {
      final manifestEntry = decoded.archive.files.singleWhere(
        (entry) => entry.name == OPENTOOL_FILE_JSON_NAME,
      );
      final bytes = manifestEntry.readBytes();
      if (bytes == null) throw const FormatException('Manifest is unreadable');
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Manifest must be a JSON object');
      }
      return ZipInspection(manifest: value, files: decoded.files);
    } finally {
      await decoded.close();
    }
  }

  static Future<String> unzipToTemp(String zipFilePath) async {
    final sourceFile = File(zipFilePath);
    if (!await sourceFile.exists()) {
      throw Exception('Source file not found: $zipFilePath');
    }
    final tmpDir = await Directory.systemTemp.createTemp('opentool_unpack_');
    final extractDir = tmpDir.path;
    await Directory(extractDir).create(recursive: true);

    final decoded = await _decodeAndValidate(zipFilePath);
    try {
      final symbolicLinks = <ArchiveFile>[];
      for (final entry in decoded.archive.files) {
        final cleanName = p.posix.normalize(entry.name);
        final components = p.posix.split(cleanName);
        final filePath = p.joinAll([extractDir, ...components]);
        if (entry.isSymbolicLink) {
          symbolicLinks.add(entry);
          continue;
        }
        if (entry.isDirectory) {
          await Directory(filePath).create(recursive: true);
          continue;
        }
        await File(filePath).parent.create(recursive: true);
        final output = OutputFileStream(filePath);
        try {
          entry.writeContent(output);
          if (output.length != entry.size) {
            throw FormatException(
              'Archive entry has an invalid size: $cleanName',
            );
          }
        } finally {
          await output.close();
        }
      }
      // Links are created after regular entries so framework link targets are
      // already present. `_decodeAndValidate` guarantees every target remains
      // inside the extraction root.
      for (final entry in symbolicLinks) {
        final cleanName = p.posix.normalize(entry.name);
        final filePath = p.joinAll([extractDir, ...p.posix.split(cleanName)]);
        await Link(filePath).create(entry.symbolicLink!, recursive: true);
      }
      return extractDir;
    } catch (_) {
      await Directory(tmpDir.path).delete(recursive: true);
      rethrow;
    } finally {
      await decoded.close();
    }
  }

  static Future<_DecodedArchive> _decodeAndValidate(String zipFilePath) async {
    final sourceFile = File(zipFilePath);
    if (!await sourceFile.exists()) {
      throw Exception('Source file not found: $zipFilePath');
    }
    final input = InputFileStream(zipFilePath);
    try {
      final archive = ZipDecoder().decodeStream(input, verify: true);
      if (archive.files.isEmpty || archive.files.length > maxArchiveEntries) {
        throw const FormatException(
          'Artifact contains an invalid number of entries',
        );
      }
      var totalSize = 0;
      var manifestCount = 0;
      final paths = <String>{};
      final files = <String>{};
      for (final entry in archive.files) {
        final originalName = entry.name;
        final cleanName = p.posix.normalize(originalName);
        if (originalName.contains(r'\') ||
            p.posix.isAbsolute(originalName) ||
            cleanName == '..' ||
            cleanName.startsWith('../') ||
            cleanName == '.') {
          throw FormatException(
            'Artifact contains an unsafe path: $originalName',
          );
        }
        if (!paths.add(cleanName)) {
          throw FormatException(
            'Artifact contains a duplicate path: $cleanName',
          );
        }
        if (entry.isSymbolicLink) {
          final target = entry.symbolicLink;
          if (target == null ||
              target.isEmpty ||
              target.contains(r'\') ||
              p.posix.isAbsolute(target)) {
            throw FormatException(
              'Artifact contains an unsafe symbolic link: $originalName',
            );
          }
          final resolvedTarget = p.posix.normalize(
            p.posix.join(p.posix.dirname(cleanName), target),
          );
          if (resolvedTarget == '.' ||
              resolvedTarget == '..' ||
              resolvedTarget.startsWith('../')) {
            throw FormatException(
              'Artifact symbolic link escapes the archive: $originalName',
            );
          }
        } else if (!entry.isFile && !entry.isDirectory) {
          throw FormatException('Artifact contains a special file: $cleanName');
        }
        if (entry.size < 0 || totalSize > maxUncompressedSize - entry.size) {
          throw const FormatException(
            'Artifact expands beyond the allowed size',
          );
        }
        totalSize += entry.size;
        if (entry.isFile || entry.isSymbolicLink) files.add(cleanName);
        if (originalName == OPENTOOL_FILE_JSON_NAME) {
          manifestCount++;
          if (entry.size > maxManifestSize) {
            throw const FormatException('Opentoolfile.json is too large');
          }
        }
      }
      if (manifestCount != 1) {
        throw const FormatException(
          'Artifact must contain one root Opentoolfile.json',
        );
      }
      return _DecodedArchive(archive: archive, input: input, files: files);
    } catch (_) {
      await input.close();
      rethrow;
    }
  }
}

class _DecodedArchive {
  final Archive archive;
  final InputFileStream input;
  final Set<String> files;

  const _DecodedArchive({
    required this.archive,
    required this.input,
    required this.files,
  });

  Future<void> close() async {
    for (final entry in archive.files) {
      await entry.close();
    }
    await input.close();
  }
}
