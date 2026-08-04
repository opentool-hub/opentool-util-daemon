import 'dart:async';
import 'dart:io';
import 'package:opentool_daemon/src/controller/server_controller.dart';
import 'package:opentool_daemon/src/middleware.dart';
import 'package:opentool_daemon/src/service/server_service.dart';
import 'package:opentool_daemon/src/service/manage_service.dart';
import 'package:opentool_daemon/src/storage/hive_storage.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'config.dart';
import 'constants.dart';
import 'controller/manage_controller.dart';
import 'controller/tool_controller.dart';
import 'router.dart';
import 'service/tool_service.dart';
import 'service/hub_install_service.dart';
import 'storage/cache_storage.dart';

class DaemonServer {
  late HttpServer server;

  Future<void> start() async {
    String version = config.version;
    String host = config.server?.host ?? InternetAddress.loopbackIPv4.host;
    int port = config.server?.port ?? DAEMON_DEFAULT_PORT;
    String prefix = config.server?.prefix ?? DAEMON_DEFAULT_PREFIX;
    String serverPrefix = SERVER_PREFIX;
    String toolPrefix = TOOL_PREFIX;

    HiveServerStorage hiveServerStorage = HiveServerStorage();
    await hiveServerStorage.init();
    HiveToolStorage hiveToolStorage = HiveToolStorage();
    await hiveToolStorage.init();
    HiveInternalServerStorage hiveInternalServerStorage =
        HiveInternalServerStorage();
    await hiveInternalServerStorage.init();

    final cacheServerStorage = CacheServerStorage(hiveServerStorage);
    final cacheToolStorage = CacheToolStorage(hiveToolStorage);
    late ServerService serverService;
    final ToolService toolService = ToolService(
      hiveToolStorage,
      cacheToolStorage: cacheToolStorage,
      serverGetter: (serverId) => serverService.get(serverId),
      serverLister: () => serverService.list(),
    );
    serverService = ServerService(
      hiveServerStorage,
      hiveInternalServerStorage,
      cacheServerStorage: cacheServerStorage,
      toolStorage: cacheToolStorage,
      onServersChanged: toolService.repairServerAssociations,
    );
    await serverService.reconcileInstallations();
    await toolService.repairServerAssociations(await serverService.list());
    ManageService manageService = ManageService(version);
    final allowInsecureHub =
        Platform.environment['OPENTOOL_ALLOW_INSECURE_HUB'] == 'true';
    final hubInstallService = HubInstallService(
      serverService: serverService,
      daemonVersion: version,
      allowInsecureHub: allowInsecureHub,
    );

    ManageController manageController = ManageController(manageService);
    ServerController serverController = ServerController(
      serverService,
      hubInstallService: hubInstallService,
    );
    ToolController toolController = ToolController(
      toolService,
      serverService,
      manageService,
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
