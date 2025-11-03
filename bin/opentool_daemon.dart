import 'package:opentool_daemon/opentool_daemon_server.dart';

Future<void> main() async {
  DaemonServer daemonServer = DaemonServer(version: "2.0.0");
  await daemonServer.start();
}
