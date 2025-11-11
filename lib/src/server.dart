import 'dart:io';
import 'package:opentool_daemon/src/controller/server_controller.dart';
import 'package:opentool_daemon/src/middleware.dart';
import 'package:opentool_daemon/src/service/server_service.dart';
import 'package:opentool_daemon/src/service/manage_service.dart';
import 'package:opentool_daemon/src/storage/hive_storage.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'constants.dart';
import 'controller/manage_controller.dart';
import 'controller/tool_controller.dart';
import 'router.dart';
import 'service/tool_service.dart';

class DaemonServer {
  late HttpServer server;
  String version;

  DaemonServer({required this.version});

  Future<void> start() async {
    String ip = InternetAddress.loopbackIPv4.host;
    int port = DAEMON_DEFAULT_PORT;
    String prefix = DAEMON_DEFAULT_PREFIX;
    String serverPrefix = SERVER_PREFIX;
    String toolPrefix = TOOL_PREFIX;

    HiveServerStorage hiveServerStorage = HiveServerStorage();
    await hiveServerStorage.init();
    HiveToolStorage hiveToolStorage = HiveToolStorage();
    await hiveToolStorage.init();
    HiveInternalServerStorage hiveInternalServerStorage = HiveInternalServerStorage();
    await hiveInternalServerStorage.init();

    ManageService manageService = ManageService(version);
    ServerService serverService = ServerService(hiveServerStorage, hiveInternalServerStorage);
    ToolService toolService  = ToolService(hiveToolStorage);

    ManageController manageController = ManageController(manageService);
    ServerController serverController = ServerController(serverService, manageService);
    ToolController toolController = ToolController(toolService, serverService);

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
        .addHandler(mainRouter);

    server = await serve(handler, ip, port);
    print("Start OpenTool Daemon: http://${server.address.host}:${server.port}$prefix");
  }

  Future<void> stop() async {
    await server.close(force: true);
  }
}