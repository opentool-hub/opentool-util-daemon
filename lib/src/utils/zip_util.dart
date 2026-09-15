import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:posix/posix.dart' as posix;

import '../constants.dart';
import 'directory_util.dart';

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
      throw FileNotFoundException(sourceDirPath);
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
        final entry = ArchiveFile(relativePath, data.length, data);
        if (_supportsPosixPermissions) {
          final stat = await entity.stat();
          // ZIP stores the POSIX file type together with its permission bits.
          // Preserve only ordinary permissions; never package special bits.
          entry.mode = 0x8000 | (stat.mode & 0x1ff);
        }
        archive.addFile(entry);
      }
    }

    final zipData = encoder.encodeBytes(archive);
    if (_supportsPosixPermissions) {
      await _markCentralDirectoryAsUnix(zipData);
    }
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
      throw FileNotFoundException(zipFilePath);
    }
    final tmpDir = await Directory.systemTemp.createTemp('opentool_unpack_');
    final extractDir = tmpDir.path;
    await Directory(extractDir).create(recursive: true);

    final decoded = await _decodeAndValidate(zipFilePath);
    try {
      final symbolicLinks = <ArchiveFile>[];
      final directoryPermissions = <MapEntry<String, int>>[];
      for (final entry in decoded.archive.files) {
        final cleanName = _normalizeEntryName(entry.name);
        final components = p.posix.split(cleanName);
        final filePath = p.joinAll([extractDir, ...components]);
        if (entry.isSymbolicLink) {
          symbolicLinks.add(entry);
          continue;
        }
        if (entry.isDirectory) {
          await Directory(filePath).create(recursive: true);
          if (_shouldRestorePermissions(decoded, cleanName)) {
            directoryPermissions.add(
              MapEntry(filePath, entry.unixPermissions & 0x1ff),
            );
          }
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
        if (_shouldRestorePermissions(decoded, cleanName)) {
          await _chmod(filePath, entry.unixPermissions & 0x1ff);
        }
      }
      // Links are created after regular entries so framework link targets are
      // already present. `_decodeAndValidate` guarantees every target remains
      // inside the extraction root.
      for (final entry in symbolicLinks) {
        final cleanName = _normalizeEntryName(entry.name);
        final filePath = p.joinAll([extractDir, ...p.posix.split(cleanName)]);
        await Link(filePath).create(entry.symbolicLink!, recursive: true);
      }
      // Apply directory modes only after all descendants and links have been
      // created; a read-only directory must not block its own extraction.
      directoryPermissions.sort(
        (left, right) => right.key.length.compareTo(left.key.length),
      );
      for (final permission in directoryPermissions) {
        await _chmod(permission.key, permission.value);
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
      throw FileNotFoundException(zipFilePath);
    }
    final input = InputFileStream(zipFilePath);
    try {
      final decoder = ZipDecoder();
      final archive = decoder.decodeStream(input, verify: true);
      final unixEntries = <String>{
        for (final header in decoder.directory.fileHeaders)
          if (header.versionMadeBy >> 8 == 3)
            _normalizeEntryName(header.filename),
      };
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
        final portableName = originalName.replaceAll(r'\', '/');
        final cleanName = p.posix.normalize(portableName);
        if (p.posix.isAbsolute(portableName) ||
            p.windows.isAbsolute(originalName) ||
            RegExp(r'^[a-zA-Z]:').hasMatch(originalName) ||
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
        if (cleanName == OPENTOOL_FILE_JSON_NAME) {
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
      return _DecodedArchive(
        archive: archive,
        input: input,
        files: files,
        unixEntries: unixEntries,
      );
    } catch (_) {
      await input.close();
      rethrow;
    }
  }

  /// ZIP uses POSIX separators, but existing Windows-built `.ots` artifacts
  /// contain backslashes. Canonicalize both forms before duplicate, traversal,
  /// entrypoint, and extraction checks so the security policy stays uniform.
  static String _normalizeEntryName(String name) =>
      p.posix.normalize(name.replaceAll(r'\', '/'));

  static bool get _supportsPosixPermissions =>
      Platform.isMacOS || Platform.isLinux || Platform.isAndroid;

  static final bool _supportsPosixPackage = () {
    if (!_supportsPosixPermissions) return false;
    try {
      return posix.isPosixSupported;
    } catch (_) {
      return false;
    }
  }();

  static bool _shouldRestorePermissions(
    _DecodedArchive decoded,
    String cleanName,
  ) => _supportsPosixPermissions && decoded.unixEntries.contains(cleanName);

  static Future<void> _chmod(String filePath, int permissions) async {
    final octalPermissions = permissions.toRadixString(8);
    if (_supportsPosixPackage) {
      posix.chmod(filePath, octalPermissions);
      return;
    }

    final result = await Process.run('chmod', [octalPermissions, filePath]);
    if (result.exitCode != 0) {
      throw FileSystemException(
        'chmod failed with exit code ${result.exitCode}: ${result.stderr}',
        filePath,
      );
    }
  }

  /// `archive` 4.x writes POSIX modes into external attributes but currently
  /// identifies every central-directory record as MS-DOS. Patch the records
  /// by walking the parsed central directory, rather than scanning arbitrary
  /// compressed bytes for header-like signatures.
  static Future<void> _markCentralDirectoryAsUnix(Uint8List zipData) async {
    final decoder = ZipDecoder();
    final decoded = decoder.decodeBytes(zipData);
    try {
      var offset = decoder.directory.centralDirectoryOffset;
      for (final _ in decoder.directory.fileHeaders) {
        if (offset < 0 || offset + 46 > zipData.length) {
          throw const FormatException('ZIP central directory is truncated');
        }
        if (_readUint32(zipData, offset) != 0x02014b50) {
          throw const FormatException('ZIP central directory is invalid');
        }
        final filenameLength = _readUint16(zipData, offset + 28);
        final extraLength = _readUint16(zipData, offset + 30);
        final commentLength = _readUint16(zipData, offset + 32);
        final recordLength = 46 + filenameLength + extraLength + commentLength;
        if (offset + recordLength > zipData.length) {
          throw const FormatException('ZIP central directory is truncated');
        }
        // versionMadeBy is little-endian: byte 5 is the creator OS.
        zipData[offset + 5] = 3;
        offset += recordLength;
      }
    } finally {
      await decoded.clear();
    }
  }

  static int _readUint16(Uint8List data, int offset) =>
      data[offset] | (data[offset + 1] << 8);

  static int _readUint32(Uint8List data, int offset) =>
      _readUint16(data, offset) | (_readUint16(data, offset + 2) << 16);
}

class _DecodedArchive {
  final Archive archive;
  final InputFileStream input;
  final Set<String> files;
  final Set<String> unixEntries;

  const _DecodedArchive({
    required this.archive,
    required this.input,
    required this.files,
    required this.unixEntries,
  });

  Future<void> close() async {
    for (final entry in archive.files) {
      await entry.close();
    }
    await input.close();
  }
}
