import 'package:opentool_daemon/opentool_daemon_server.dart';

Future<void> main() async {
  DaemonServer daemonServer = DaemonServer(version: "0.1.0");
  await daemonServer.start();
}
