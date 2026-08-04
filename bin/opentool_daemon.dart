import 'package:opentool_daemon/opentool_daemon_server.dart';

Future<void> main(List<String> args) async {
  final configPath = configPathFromArgs(args);
  config = initConfig(configFilePath: configPath, strict: configPath != null);
  if (args.contains('--auto-restore')) {
    config.autoRestore = true;
  } else if (args.contains('--no-auto-restore')) {
    config.autoRestore = false;
  }

  DaemonServer daemonServer = DaemonServer();
  await daemonServer.start();
}
