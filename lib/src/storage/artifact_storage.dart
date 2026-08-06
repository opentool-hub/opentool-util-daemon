import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:unique_id_dart/unique_id_dart.dart';

class ArtifactWriteResult {
  final String tempPath;
  final String digest;
  final int size;

  const ArtifactWriteResult({
    required this.tempPath,
    required this.digest,
    required this.size,
  });
}

class ArtifactStorage {
  final String dataDir;

  ArtifactStorage(this.dataDir);

  String get contentRoot => p.join(dataDir, 'content');
  String get tempRoot => p.join(contentRoot, '.tmp');
  String get trashRoot => p.join(contentRoot, '.trash');

  String pathForDigest(String digest) {
    final hex = _hex(digest);
    return p.join(
      contentRoot,
      'sha256',
      hex.substring(0, 2),
      '${hex.substring(2)}.ots',
    );
  }

  Future<ArtifactWriteResult> copyToPart(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Artifact file does not exist', sourcePath);
    }
    await Directory(tempRoot).create(recursive: true);
    final part = File(p.join(tempRoot, '${uniqueId(shorter: false)}.part'));
    final sink = part.openWrite(mode: FileMode.writeOnly);
    final output = _DigestSink();
    final digestSink = sha256.startChunkedConversion(output);
    var size = 0;
    try {
      await for (final chunk in source.openRead()) {
        size += chunk.length;
        digestSink.add(chunk);
        sink.add(chunk);
      }
      digestSink.close();
      await sink.flush();
      await sink.close();
      final raf = await part.open(mode: FileMode.append);
      await raf.flush();
      await raf.close();
      return ArtifactWriteResult(
        tempPath: part.path,
        digest: 'sha256:${output.value!}',
        size: size,
      );
    } catch (_) {
      await sink.close();
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }

  Future<String> commitPart(ArtifactWriteResult write) async {
    final target = File(pathForDigest(write.digest));
    await target.parent.create(recursive: true);
    if (await target.exists()) {
      await verify(target.path, write.digest, write.size);
      await deleteIfExists(write.tempPath);
      return target.path;
    }
    try {
      await File(write.tempPath).rename(target.path);
    } on FileSystemException {
      if (!await target.exists()) rethrow;
      await verify(target.path, write.digest, write.size);
      await deleteIfExists(write.tempPath);
    }
    return target.path;
  }

  Future<void> verify(
    String path,
    String expectedDigest,
    int expectedSize,
  ) async {
    final file = File(path);
    if (!await file.exists() || await file.length() != expectedSize) {
      throw const FormatException(
        'Artifact content size does not match its record',
      );
    }
    final actual = await sha256.bind(file.openRead()).first;
    if ('sha256:$actual' != expectedDigest) {
      throw const FormatException(
        'Artifact content digest does not match its record',
      );
    }
  }

  Future<String> moveToTrash(String digest, String operationId) async {
    final source = File(pathForDigest(digest));
    final target = p.join(trashRoot, operationId);
    await Directory(trashRoot).create(recursive: true);
    if (await source.exists()) await source.rename(target);
    return target;
  }

  Future<void> deleteIfExists(String? path) async {
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Future<void> cleanupParts() async {
    final directory = Directory(tempRoot);
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.part'))
        await entity.delete();
    }
  }

  String _hex(String digest) {
    if (!RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(digest)) {
      throw ArgumentError.value(digest, 'digest', 'Invalid sha256 digest');
    }
    return digest.substring(7);
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
