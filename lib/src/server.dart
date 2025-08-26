import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'controller/controller.dart';
import 'router.dart';
import 'service/manage_service.dart';
import 'service/runner_service.dart';
import 'storage/hive_storage.dart';

const int DAEMON_DEFAULT_PORT = 19627;
const String DAEMON_DEFAULT_PREFIX = "/opentool-daemon";

class DaemonServer {

  late HttpServer server;
  String version;

  DaemonServer({required this.version});

  Future<void> start() async {
    String ip = InternetAddress.loopbackIPv4.host;
    int port = DAEMON_DEFAULT_PORT;
    String prefix = DAEMON_DEFAULT_PREFIX;

    final hiveStorage = HiveStorage();
    await hiveStorage.init();

    final manager = ManageService(storage: hiveStorage);
    final runner = RunnerService(manager: manager);
    await runner.startCheckPeriodic(Duration(minutes: 1));

    Controller controller = Controller(manageService: manager, runnerService: runner, version: version);

    daemonRoutes(controller);

    final Router mainRouter = Router();
    mainRouter.mount(prefix, daemonRouter);
    Pipeline pipeline = Pipeline();
    Handler handler = pipeline.addHandler(mainRouter);

    server = await serve(handler, ip, port);
    print("Start Daemon Server: http://${server.address.host}:${server.port}$prefix");
  }

  Future<void> stop() async {
    await server.close(force: true);
  }
}