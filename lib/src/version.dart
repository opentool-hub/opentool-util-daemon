// Keep this value aligned with pubspec.yaml. Release builds may override it
// with --define=OPENTOOL_DAEMON_VERSION=<version>.
const String packageVersion = '0.5.2';

const String daemonVersion = String.fromEnvironment(
  'OPENTOOL_DAEMON_VERSION',
  defaultValue: packageVersion,
);
