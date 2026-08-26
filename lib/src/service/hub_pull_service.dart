import 'dart:async';
import 'dart:io';

import '../constants.dart';
import '../hub/dto.dart';
import '../hub/exception.dart';
import '../hub/hub_client.dart';
import '../utils/logger.dart';
import '../utils/platform_detector.dart';
import 'artifact_downloader.dart';
import 'exception.dart';
import 'pull_cancellation.dart';
import 'model.dart';
import 'server_service.dart';

class HubPullRequest {
  final String registry;
  final String namespace;
  final String name;
  final String version;
  final String client;

  const HubPullRequest({
    required this.registry,
    required this.namespace,
    required this.name,
    required this.version,
    required this.client,
  });

  factory HubPullRequest.validate({
    required String registry,
    required String namespace,
    required String name,
    required String version,
    String? client,
  }) {
    final normalizedNamespace = namespace.trim().toLowerCase();
    final normalizedName = name.trim().toLowerCase();
    final normalizedVersion = version.trim();
    final namePattern = RegExp(r'^[a-z0-9]+(?:[._-][a-z0-9]+)*$');
    final semverPattern = RegExp(
      r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
      r'(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?'
      r'(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
    );
    if (!namePattern.hasMatch(normalizedNamespace) ||
        !namePattern.hasMatch(normalizedName) ||
        !semverPattern.hasMatch(normalizedVersion)) {
      throw const FormatException('Tool reference is invalid');
    }
    final normalizedClient = (client ?? 'unknown').trim().toLowerCase();
    if (!const {
      'desktop',
      'embedded',
      'server',
      'cli',
      'unknown',
    }.contains(normalizedClient)) {
      throw const FormatException('Client type is invalid');
    }
    final canonicalRegistry = HubClient.canonicalizeRegistry(
      registry,
    ).toString();
    return HubPullRequest(
      registry: canonicalRegistry,
      namespace: normalizedNamespace,
      name: normalizedName,
      version: normalizedVersion,
      client: normalizedClient,
    );
  }

  String get ref => '$namespace/$name:$version';
}

class PullEvent {
  final String event;
  final Map<String, dynamic> data;

  const PullEvent(this.event, this.data);
}

typedef HubClientFactory = HubClient Function(String registry);

class HubPullService {
  final ServerService serverService;
  final PlatformDetector platformDetector;
  final ArtifactDownloader downloader;
  final HubClientFactory _hubClientFactory;
  final Map<String, _SourceLockEntry> _sourceLocks = {};

  HubPullService({
    required this.serverService,
    required String daemonVersion,
    PlatformDetector? platformDetector,
    ArtifactDownloader? downloader,
    HubClientFactory? hubClientFactory,
  }) : platformDetector = platformDetector ?? PlatformDetector(),
       downloader = downloader ?? ArtifactDownloader(dataDir: OPENTOOL_PATH),
       _hubClientFactory =
           hubClientFactory ??
           ((registry) => HubClient(registry, daemonVersion: daemonVersion));

  Future<ServerModel> pull(
    HubPullRequest request, {
    required void Function(PullEvent event) onEvent,
    PullCancellationToken? cancellation,
  }) async {
    _ensureNotCancelled(cancellation);
    final platform = await platformDetector.detect();
    return _withSourceLock(request, () async {
      _ensureNotCancelled(cancellation);
      onEvent(PullEvent('start', {'stage': 'resolving', 'ref': request.ref}));
      final server = await _performInstall(
        request,
        platform,
        onEvent,
        cancellation,
      );
      _ensureNotCancelled(cancellation);
      onEvent(
        PullEvent('done', {'stage': 'ready', 'server': _serverJson(server)}),
      );
      return server;
    });
  }

  int get debugSourceLockCount => _sourceLocks.length;

  Future<T> _withSourceLock<T>(
    HubPullRequest request,
    Future<T> Function() action,
  ) async {
    final key =
        '${request.registry}|${request.namespace}|${request.name}|${request.version}';
    final entry = _sourceLocks.putIfAbsent(key, _SourceLockEntry.new);
    entry.references++;
    try {
      return await entry.lock.protect(action);
    } finally {
      entry.references--;
      if (entry.references == 0 && identical(_sourceLocks[key], entry)) {
        _sourceLocks.remove(key);
      }
    }
  }

  Future<ServerModel> _performInstall(
    HubPullRequest request,
    ServerPlatform platform,
    void Function(PullEvent event) onEvent,
    PullCancellationToken? cancellation,
  ) async {
    String? downloadedPath;
    try {
      final resolved = await _hubClientFactory(request.registry).resolve(
        namespace: request.namespace,
        name: request.name,
        version: request.version,
        os: platform.os,
        arch: platform.arch,
        abi: platform.abi,
        client: request.client,
        cancellation: cancellation,
      );
      _ensureNotCancelled(cancellation);
      _validateResolve(request, platform, resolved);
      logger.log(
        LogModule.server,
        'hub.resolve.result',
        detail:
            'ref: ${request.ref}, versionRevision: ${resolved.versionRevision}, versionDigest: ${resolved.versionDigest}, artifactId: ${resolved.artifact.id}, artifactDigest: ${resolved.artifact.digest}',
      );

      final existing = await serverService.findHubSource(
        registry: request.registry,
        namespace: request.namespace,
        name: request.name,
        version: request.version,
      );
      if (existing != null) {
        if (existing.artifactDigest != resolved.artifact.digest ||
            (existing.versionRevision != null &&
                resolved.versionRevision < existing.versionRevision!) ||
            (existing.versionRevision == resolved.versionRevision &&
                existing.versionDigest != null &&
                existing.versionDigest != resolved.versionDigest)) {
          throw const ArtifactOperationException(
            code: 'ARTIFACT_SOURCE_CONFLICT',
            message:
                'The requested published version conflicts with installed immutable metadata',
            retryable: false,
          );
        }
        if (existing.versionRevision == resolved.versionRevision &&
            existing.versionDigest == resolved.versionDigest &&
            existing.artifactId == resolved.artifact.id) {
          return existing;
        }
        return serverService.refreshHubSourceMetadata(
          existing.id,
          _metadata(request, platform, resolved),
        );
      }

      downloadedPath = await downloader.download(
        downloadUrl: resolved.artifact.downloadUrl,
        expectedSize: resolved.artifact.size,
        expectedDigest: resolved.artifact.digest,
        onProgress: (downloaded, total) {
          onEvent(
            PullEvent('data', {
              'stage': 'downloading',
              'downloadedBytes': downloaded,
              'totalBytes': total,
              'percent': total == 0 ? 0 : (downloaded * 100 ~/ total),
            }),
          );
        },
        onVerifying: () => onEvent(
          PullEvent('data', {
            'stage': 'verifying',
            'digest': resolved.artifact.digest,
          }),
        ),
        cancellation: cancellation,
      );
      _ensureNotCancelled(cancellation);
      final registered = await serverService.registerHubArtifact(
        downloadedPath,
        _metadata(request, platform, resolved),
        onImporting: () =>
            onEvent(const PullEvent('data', {'stage': 'registering'})),
      );
      logger.log(
        LogModule.server,
        'hub.pull.result',
        detail:
            'serverId: ${registered.id}, versionRevision: ${registered.versionRevision}, versionDigest: ${registered.versionDigest}, artifactId: ${registered.artifactId}, artifactDigest: ${registered.artifactDigest}',
      );
      return registered;
    } on PullCancelledException {
      throw const ArtifactOperationException(
        code: 'PULL_CANCELLED',
        message: 'Pull was cancelled',
        retryable: false,
      );
    } on HubApiException catch (error) {
      throw _mapHubError(error);
    } finally {
      if (downloadedPath != null) {
        final file = File(downloadedPath);
        if (await file.exists()) await file.delete();
      }
    }
  }

  HubArtifactMetadata _metadata(
    HubPullRequest request,
    ServerPlatform platform,
    ResolveResult resolved,
  ) => HubArtifactMetadata(
    registry: request.registry,
    namespace: request.namespace,
    name: request.name,
    version: request.version,
    versionRevision: resolved.versionRevision,
    versionDigest: resolved.versionDigest,
    artifactId: resolved.artifact.id,
    artifactDigest: resolved.artifact.digest,
    artifactMediaType: resolved.artifact.mediaType,
    artifactSize: resolved.artifact.size,
    platform: platform,
  );

  void _validateResolve(
    HubPullRequest request,
    ServerPlatform platform,
    ResolveResult resolved,
  ) {
    final digestPattern = RegExp(r'^sha256:[a-f0-9]{64}$');
    if (resolved.tool.namespace != request.namespace ||
        resolved.tool.name != request.name ||
        resolved.version != request.version ||
        resolved.versionRevision < 1 ||
        !digestPattern.hasMatch(resolved.versionDigest) ||
        resolved.artifact.os != platform.os ||
        resolved.artifact.arch != platform.arch ||
        resolved.artifact.abi != platform.abi ||
        resolved.artifact.id.trim().isEmpty ||
        resolved.artifact.mediaType != 'application/vnd.opentool.ots' ||
        resolved.artifact.size <= 0 ||
        !digestPattern.hasMatch(resolved.artifact.digest)) {
      throw const ArtifactOperationException(
        code: 'HUB_INVALID_RESPONSE',
        message: 'Hub resolve response does not match the pull request',
        retryable: true,
      );
    }
    if (!resolved.artifact.downloadUrlExpiresAt.isAfter(
      DateTime.now().toUtc(),
    )) {
      throw const ArtifactOperationException(
        code: 'HUB_UNAVAILABLE',
        message: 'Hub returned an expired artifact download URL',
        retryable: true,
      );
    }
  }

  ArtifactOperationException _mapHubError(HubApiException error) {
    final code = switch (error.code) {
      'INSTALL_CANCELLED' => 'PULL_CANCELLED',
      'VERSION_DEPRECATED' => 'TOOL_VERSION_DEPRECATED',
      'TOOL_NOT_FOUND' ||
      'VERSION_NOT_FOUND' ||
      'VERSION_NOT_PUBLISHED' ||
      'VERSION_YANKED' => 'TOOL_VERSION_NOT_FOUND',
      'ARTIFACT_PLATFORM_UNSUPPORTED' => 'PLATFORM_NOT_SUPPORTED',
      _ => error.retryable ? 'HUB_UNAVAILABLE' : error.code,
    };
    return ArtifactOperationException(
      code: code,
      message: error.message,
      retryable: error.retryable,
      requestId: error.requestId,
    );
  }

  void _ensureNotCancelled(PullCancellationToken? cancellation) {
    if (cancellation?.isCancelled ?? false) {
      throw const ArtifactOperationException(
        code: 'PULL_CANCELLED',
        message: 'Pull was cancelled',
        retryable: false,
      );
    }
  }

  Map<String, dynamic> _serverJson(ServerModel server) => {
    'id': server.id,
    'alias': server.alias,
    'registry': server.registry,
    'namespace': server.namespace,
    'version': server.version,
    'name': server.name,
    'schemaVersion': 2,
    'source': {
      'registry': server.registry,
      'namespace': server.namespace,
      'name': server.name,
      'version': server.version,
      if (server.versionDigest != null) 'versionDigest': server.versionDigest,
      if (server.versionRevision != null)
        'versionRevision': server.versionRevision,
      if (server.artifactId != null) 'artifactId': server.artifactId,
      if (server.artifactDigest != null)
        'artifactDigest': server.artifactDigest,
      if (server.artifactMediaType != null)
        'artifactMediaType': server.artifactMediaType,
    },
    if (server.platform != null)
      'platform': {
        'os': server.platform!.os,
        'arch': server.platform!.arch,
        'abi': server.platform!.abi,
      },
    if (server.artifactSize != null) 'size': server.artifactSize,
    if (server.createdAt != null)
      'createdAt': server.createdAt!.toIso8601String(),
  };
}

class _AsyncLock {
  Future<void> _tail = Future<void>.value();

  Future<T> protect<T>(Future<T> Function() action) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous.catchError((_) {});
    try {
      return await action();
    } finally {
      done.complete();
    }
  }
}

class _SourceLockEntry {
  final _AsyncLock lock = _AsyncLock();
  int references = 0;
}
