import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:unique_id_dart/unique_id_dart.dart';

import '../constants.dart';
import '../storage/dao.dart';
import '../storage/storage.dart';
import '../utils/directory_util.dart';
import '../utils/zip_util.dart';
import 'exception.dart';
import 'model.dart';

class ToolMaterializationService {
  final String dataDir;
  final Storage<ToolDao> tools;
  final Storage<ArtifactOperationDao> operations;

  ToolMaterializationService({
    required this.dataDir,
    required this.tools,
    required this.operations,
  });

  Future<void> ensureMaterialized(ToolDao tool, ServerModel server) async {
    if (server.state != 'available') {
      throw ArtifactOperationException(
        code: 'MATERIALIZATION_FAILED',
        message: 'Server ${server.id} is ${server.state}',
        retryable: false,
      );
    }
    final digest = server.artifactDigest;
    final artifactPath = server.artifactFilePath;
    if (digest == null ||
        artifactPath == null ||
        !await File(artifactPath).exists()) {
      throw const ArtifactOperationException(
        code: 'MATERIALIZATION_FAILED',
        message: 'Server artifact is unavailable',
        retryable: false,
      );
    }
    final workspace = Directory(p.join(dataDir, TOOL_FOLDER, tool.id));
    if (tool.materializedArtifactDigest == digest &&
        await File(p.join(workspace.path, OPENTOOL_FILE_JSON_NAME)).exists()) {
      return;
    }

    final operationId = uniqueId(shorter: false);
    final staging = Directory(
      p.join(dataDir, TOOL_FOLDER, '.staging', '${tool.id}-$operationId'),
    );
    final previous = Directory(
      p.join(dataDir, TOOL_FOLDER, '.previous', '${tool.id}-$operationId'),
    );
    final previousDigest = tool.materializedArtifactDigest;
    final now = DateTime.now().toUtc();
    final operation = ArtifactOperationDao(
      id: operationId,
      type: 'materialize',
      stage: 'created',
      tempPath: staging.path,
      digest: digest,
      serverId: server.id,
      payloadJson: jsonEncode({
        'toolId': tool.id,
        'workspace': workspace.path,
        'previous': previous.path,
        'previousDigest': previousDigest,
      }),
      createdAt: now,
      updatedAt: now,
    );
    await operations.add(operation);
    String? extractedPath;
    try {
      extractedPath = await ZipUtil.unzipToTemp(artifactPath);
      await staging.parent.create(recursive: true);
      await DirectoryUtil.copyDirectory(Directory(extractedPath), staging);
      await DirectoryUtil.deleteDirectory(extractedPath);
      extractedPath = null;
      if (!await File(p.join(staging.path, OPENTOOL_FILE_JSON_NAME)).exists()) {
        throw const FormatException('Materialized artifact has no manifest');
      }
      await _stage(operation, 'staged');
      if (await workspace.exists()) {
        await previous.parent.create(recursive: true);
        await workspace.rename(previous.path);
      }
      await _stage(operation, 'previousMoved');
      await staging.rename(workspace.path);
      await _stage(operation, 'workspaceMoved');
      tool.materializedArtifactDigest = digest;
      await tools.update(tool);
      await _stage(operation, 'toolUpdated');
      await _stage(operation, 'committed');
      await DirectoryUtil.deleteDirectory(previous.path);
      await operations.remove(operation.id);
    } catch (error) {
      if (await previous.exists()) {
        if (await workspace.exists())
          await DirectoryUtil.deleteDirectory(workspace.path);
        await previous.rename(workspace.path);
      }
      tool.materializedArtifactDigest = previousDigest;
      await tools.update(tool);
      await DirectoryUtil.deleteDirectory(staging.path);
      await operations.remove(operation.id);
      if (error is ArtifactOperationException) rethrow;
      throw ArtifactOperationException(
        code: 'MATERIALIZATION_FAILED',
        message: 'Unable to materialize Tool content: $error',
        retryable: true,
      );
    } finally {
      if (extractedPath != null) {
        await DirectoryUtil.deleteDirectory(extractedPath);
      }
    }
  }

  Future<void> recover() async {
    for (final operation in (await operations.list()).where(
      (item) => item.type == 'materialize',
    )) {
      final payload = operation.payloadJson == null
          ? null
          : jsonDecode(operation.payloadJson!);
      if (payload is! Map<String, dynamic>) {
        await operations.remove(operation.id);
        continue;
      }
      final workspace = Directory(payload['workspace'] as String);
      final previous = Directory(payload['previous'] as String);
      final previousDigest = payload['previousDigest'] as String?;
      final staging = Directory(operation.tempPath ?? '');
      final tool = await tools.get(payload['toolId'] as String);
      final manifest = File(p.join(workspace.path, OPENTOOL_FILE_JSON_NAME));
      if (tool != null &&
          tool.materializedArtifactDigest == operation.digest &&
          await manifest.exists()) {
        await DirectoryUtil.deleteDirectory(previous.path);
      } else {
        if (await previous.exists()) {
          if (await workspace.exists()) {
            await DirectoryUtil.deleteDirectory(workspace.path);
          }
          await previous.rename(workspace.path);
        } else if (await workspace.exists()) {
          await DirectoryUtil.deleteDirectory(workspace.path);
        }
        if (tool != null) {
          tool.materializedArtifactDigest = previousDigest;
          await tools.update(tool);
        }
      }
      await DirectoryUtil.deleteDirectory(staging.path);
      await operations.remove(operation.id);
    }
  }

  Future<void> _stage(ArtifactOperationDao operation, String stage) async {
    operation.stage = stage;
    operation.updatedAt = DateTime.now().toUtc();
    await operations.update(operation);
  }
}
