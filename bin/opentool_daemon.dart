import 'package:opentool_daemon/opentool_daemon_server.dart';
import 'package:opentool_daemon/src/config.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--auto-restore')) {
    config.autoRestore = true;
  } else if (args.contains('--no-auto-restore')) {
    config.autoRestore = false;
  }

  DaemonServer daemonServer = DaemonServer();
  await daemonServer.start();
}
