import 'package:opentool_daemon/opentool_daemon_server.dart';

Future<void> main() async {
  DaemonServer daemonServer = DaemonServer();
  await daemonServer.start();
}
