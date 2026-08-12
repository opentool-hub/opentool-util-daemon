import 'dart:async';
import 'dart:io';
import 'package:opentool_daemon/src/controller/server_controller.dart';
import 'package:opentool_daemon/src/middleware.dart';
import 'package:opentool_daemon/src/service/server_service.dart';
import 'package:opentool_daemon/src/service/manage_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'config.dart';
import 'constants.dart';
import 'controller/manage_controller.dart';
import 'controller/tool_controller.dart';
import 'router.dart';
import 'service/tool_service.dart';
import 'service/hub_pull_service.dart';
import 'service/artifact_registry_service.dart';
import 'service/builtin_reconcile_service.dart';
import 'service/tool_materialization_service.dart';
import 'storage/cache_storage.dart';
import 'storage/artifact_storage.dart';
import 'storage/registry_storage.dart';

class DaemonServer {
  late HttpServer server;

  Future<void> start() async {
    String version = config.version;
    String host = config.server?.host ?? InternetAddress.loopbackIPv4.host;
    int port = config.server?.port ?? DAEMON_DEFAULT_PORT;
    String prefix = config.server?.prefix ?? DAEMON_DEFAULT_PREFIX;
    String serverPrefix = SERVER_PREFIX;
    String toolPrefix = TOOL_PREFIX;

    final storage = RegistryStorageBundle(OPENTOOL_PATH);
    await storage.init();
    final artifactStorage = ArtifactStorage(OPENTOOL_PATH);
    final cacheServerStorage = CacheServerStorage(storage.servers);
    final cacheToolStorage = CacheToolStorage(storage.tools);
    late ServerService serverService;
    late ToolService toolService;
    final registry = ArtifactRegistryService(
      content: artifactStorage,
      artifacts: storage.artifacts,
      servers: cacheServerStorage,
      operations: storage.operations,
      tools: cacheToolStorage,
      onServersChanged: () async {
        await toolService.repairServerAssociations(await serverService.list());
      },
    );
    final materialization = ToolMaterializationService(
      dataDir: OPENTOOL_PATH,
      tools: cacheToolStorage,
      operations: storage.operations,
    );
    await materialization.recover();
    toolService = ToolService(
      cacheToolStorage,
      cacheToolStorage: cacheToolStorage,
      serverGetter: (serverId) => serverService.get(serverId),
      serverLister: () => serverService.list(),
      materializationService: materialization,
    );
    serverService = ServerService(
      storage.servers,
      cacheServerStorage: cacheServerStorage,
      toolStorage: cacheToolStorage,
      onServersChanged: toolService.repairServerAssociations,
      artifactRegistry: registry,
    );
    final builtinService = BuiltinReconcileService(
      registry: registry,
      content: artifactStorage,
      servers: cacheServerStorage,
      bundles: storage.builtinBundles,
    );
    await builtinService.recover();
    await serverService.reconcileInstallations();
    await toolService.repairServerAssociations(await serverService.list());
    ManageService manageService = ManageService(
      version,
      apiKeyStorage: storage.apiKeys,
    );
    final hubPullService = HubPullService(
      serverService: serverService,
      daemonVersion: version,
    );
    final hostAuthenticator =
        await HostManagementAuthenticator.fromEnvironment();

    ManageController manageController = ManageController(manageService);
    ServerController serverController = ServerController(
      serverService,
      hubPullService: hubPullService,
      builtinReconcileService: builtinService,
      hostAuthenticator: hostAuthenticator,
    );
    ToolController toolController = ToolController(
      toolService,
      serverService,
      manageService,
      hostAuthenticator: hostAuthenticator,
    );

    manageRoutes(manageController);
    serverRoutes(serverController);
    toolRoutes(toolController);

    final Router mainRouter = Router();
    mainRouter.mount(prefix, manageRouter);
    manageRouter.mount(serverPrefix, serverRouter);
    manageRouter.mount(toolPrefix, toolRouter);

    Pipeline pipeline = Pipeline();

    Handler handler = pipeline
        .addMiddleware(exceptionHandler())
        .addMiddleware(logRequest())
        .addHandler(mainRouter);

    server = await serve(handler, host, port);
    print(
      "Start OpenTool Daemon: http://${server.address.host}:${server.port}$prefix",
    );

    unawaited(
      toolService
          .refreshStatusesOnStartup(autoRestore: config.autoRestore)
          .catchError((e, st) {
            print("refreshStatusesOnStartup error: $e\n$st");
          }),
    );
  }

  Future<void> stop() async {
    await server.close(force: true);
  }
}
