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
import 'install_cancellation.dart';
import 'model.dart';
import 'server_service.dart';

class HubInstallRequest {
  final String registry;
  final String namespace;
  final String name;
  final String version;
  final String client;

  const HubInstallRequest({
    required this.registry,
    required this.namespace,
    required this.name,
    required this.version,
    required this.client,
  });

  factory HubInstallRequest.validate({
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
    return HubInstallRequest(
      registry: canonicalRegistry,
      namespace: normalizedNamespace,
      name: normalizedName,
      version: normalizedVersion,
      client: normalizedClient,
    );
  }

  String get ref => '$namespace/$name:$version';
}

class HubInstallEvent {
  final String event;
  final Map<String, dynamic> data;

  const HubInstallEvent(this.event, this.data);
}

typedef HubClientFactory = HubClient Function(String registry);

class HubInstallService {
  final ServerService serverService;
  final PlatformDetector platformDetector;
  final ArtifactDownloader downloader;
  final HubClientFactory _hubClientFactory;
  final Map<String, Future<ServerModel>> _inFlight = {};

  HubInstallService({
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

  Future<ServerModel> install(
    HubInstallRequest request, {
    required void Function(HubInstallEvent event) onEvent,
    InstallCancellationToken? cancellation,
  }) async {
    _ensureNotCancelled(cancellation);
    final platform = await platformDetector.detect();
    final key = [
      request.registry,
      request.namespace,
      request.name,
      request.version,
      platform.os,
      platform.arch,
      platform.abi,
    ].join('|');

    var task = _inFlight[key];
    if (task == null) {
      onEvent(
        HubInstallEvent('start', {'stage': 'resolving', 'ref': request.ref}),
      );
      late Future<ServerModel> created;
      created = _performInstall(request, platform, onEvent, cancellation)
          .whenComplete(() {
            if (identical(_inFlight[key], created)) _inFlight.remove(key);
          });
      _inFlight[key] = created;
      task = created;
    } else {
      onEvent(
        HubInstallEvent('start', {'stage': 'waiting', 'ref': request.ref}),
      );
    }

    final server = await task;
    _ensureNotCancelled(cancellation);
    onEvent(
      HubInstallEvent('done', {
        'stage': 'installed',
        'server': _serverJson(server),
      }),
    );
    return server;
  }

  Future<ServerModel> _performInstall(
    HubInstallRequest request,
    ServerPlatform platform,
    void Function(HubInstallEvent event) onEvent,
    InstallCancellationToken? cancellation,
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
            'ref: ${request.ref}, versionDigest: ${resolved.versionDigest}, artifactId: ${resolved.artifact.id}, artifactDigest: ${resolved.artifact.digest}',
      );

      final existing = await serverService.findHubSource(
        registry: request.registry,
        namespace: request.namespace,
        name: request.name,
        version: request.version,
      );
      if (existing != null) {
        if (existing.artifactDigest == resolved.artifact.digest)
          return existing;
        throw const InstallException(
          code: 'ARTIFACT_VERSION_CONFLICT',
          message:
              'The requested published version is already installed with a different digest',
          retryable: false,
        );
      }

      downloadedPath = await downloader.download(
        downloadUrl: resolved.artifact.downloadUrl,
        expectedSize: resolved.artifact.size,
        expectedDigest: resolved.artifact.digest,
        onProgress: (downloaded, total) {
          onEvent(
            HubInstallEvent('data', {
              'stage': 'downloading',
              'downloadedBytes': downloaded,
              'totalBytes': total,
              'percent': total == 0 ? 0 : (downloaded * 100 ~/ total),
            }),
          );
        },
        onVerifying: () => onEvent(
          HubInstallEvent('data', {
            'stage': 'verifying',
            'digest': resolved.artifact.digest,
          }),
        ),
        cancellation: cancellation,
      );
      _ensureNotCancelled(cancellation);
      final installed = await serverService.installHubArtifact(
        downloadedPath,
        HubArtifactMetadata(
          registry: request.registry,
          namespace: request.namespace,
          name: request.name,
          version: request.version,
          versionDigest: resolved.versionDigest,
          artifactId: resolved.artifact.id,
          artifactDigest: resolved.artifact.digest,
          artifactMediaType: resolved.artifact.mediaType,
          artifactSize: resolved.artifact.size,
          platform: platform,
        ),
        onImporting: () =>
            onEvent(const HubInstallEvent('data', {'stage': 'importing'})),
      );
      logger.log(
        LogModule.server,
        'hub.install.result',
        detail:
            'serverId: ${installed.id}, versionDigest: ${installed.versionDigest}, artifactId: ${installed.artifactId}, artifactDigest: ${installed.artifactDigest}',
      );
      return installed;
    } on InstallCancelledException {
      throw const InstallException(
        code: 'INSTALL_CANCELLED',
        message: 'Installation was cancelled',
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

  void _validateResolve(
    HubInstallRequest request,
    ServerPlatform platform,
    ResolveResult resolved,
  ) {
    final digestPattern = RegExp(r'^sha256:[a-f0-9]{64}$');
    if (resolved.tool.namespace != request.namespace ||
        resolved.tool.name != request.name ||
        resolved.version != request.version ||
        !digestPattern.hasMatch(resolved.versionDigest) ||
        resolved.artifact.os != platform.os ||
        resolved.artifact.arch != platform.arch ||
        resolved.artifact.abi != platform.abi ||
        resolved.artifact.id.trim().isEmpty ||
        resolved.artifact.mediaType != 'application/vnd.opentool.ots' ||
        resolved.artifact.size <= 0 ||
        !digestPattern.hasMatch(resolved.artifact.digest)) {
      throw const InstallException(
        code: 'HUB_INVALID_RESPONSE',
        message: 'Hub resolve response does not match the installation request',
        retryable: true,
      );
    }
    if (!resolved.artifact.downloadUrlExpiresAt.isAfter(
      DateTime.now().toUtc(),
    )) {
      throw const InstallException(
        code: 'HUB_UNAVAILABLE',
        message: 'Hub returned an expired artifact download URL',
        retryable: true,
      );
    }
  }

  InstallException _mapHubError(HubApiException error) {
    final code = switch (error.code) {
      'INSTALL_CANCELLED' => 'INSTALL_CANCELLED',
      'VERSION_DEPRECATED' => 'TOOL_VERSION_DEPRECATED',
      'TOOL_NOT_FOUND' ||
      'VERSION_NOT_FOUND' ||
      'VERSION_NOT_PUBLISHED' ||
      'VERSION_YANKED' => 'TOOL_VERSION_NOT_FOUND',
      'ARTIFACT_PLATFORM_UNSUPPORTED' => 'PLATFORM_NOT_SUPPORTED',
      _ => error.retryable ? 'HUB_UNAVAILABLE' : error.code,
    };
    return InstallException(
      code: code,
      message: error.message,
      retryable: error.retryable,
      requestId: error.requestId,
    );
  }

  void _ensureNotCancelled(InstallCancellationToken? cancellation) {
    if (cancellation?.isCancelled ?? false) {
      throw const InstallException(
        code: 'INSTALL_CANCELLED',
        message: 'Installation was cancelled',
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
    'repo': server.repo,
    'name': server.name,
    'tag': server.tag,
    'source': {
      'registry': server.registry,
      'namespace': server.namespace,
      'name': server.name,
      'version': server.version,
      if (server.versionDigest != null) 'versionDigest': server.versionDigest,
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
    if (server.installedAt != null)
      'installedAt': server.installedAt!.toIso8601String(),
  };
}
