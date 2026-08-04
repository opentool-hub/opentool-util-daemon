import 'dart:io';
import 'utils/directory_util.dart';

final Map<String, String> JSON_HEADERS = {
  HttpHeaders.contentTypeHeader: 'application/json',
  HttpHeaders.cacheControlHeader: 'no-cache',
  HttpHeaders.connectionHeader: 'keep-alive',
};
final Map<String, String> STREAM_HEADERS = {
  HttpHeaders.contentTypeHeader: 'text/event-stream',
  HttpHeaders.cacheControlHeader: 'no-cache',
  HttpHeaders.connectionHeader: 'keep-alive',
  'Cache-Control': 'no-store',
};

const String DEFAULT_REGISTRY = "https://www.opentool-hub.com";
const String OPENTOOL_FOLDER = ".opentool";
String OPENTOOL_PATH =
    "${DirectoryUtil.getBaseDir()}${Platform.pathSeparator}${OPENTOOL_FOLDER}";

const String SERVER_FOLDER = 'servers';
const String TOOL_FOLDER = 'tools';
const String LOCAL_REGISTRY = 'local';
const String LOCAL_NAMESPACE = 'local';
@Deprecated('Use LOCAL_REGISTRY')
const String NULL_REGISTRY = LOCAL_REGISTRY;
@Deprecated('Use LOCAL_NAMESPACE')
const String NULL_REPO = LOCAL_NAMESPACE;
const String NULL_TAG = 'latest';

const String OPENTOOL_FILE_NAME = 'Opentoolfile';
const String OPENTOOL_FILE_JSON_NAME = 'Opentoolfile.json';
const String OPENTOOL_DAEMON_NAME = "OpenTool Daemon";
const String SYSTEM_CONFIG_FILE_NAME = "config.json";
const String API_KEYS_FILE_NAME = 'api_keys.json';
const String SUDO_TOKEN_FILE_NAME = 'opentool-daemon.sudo';
const String TOOL_API_KEY_HEADER = 'x-opentool-api-key';

const int DAEMON_DEFAULT_PORT = 19627;
const int TOOL_DEFAULT_PORT = 9010;
const String DAEMON_DEFAULT_PREFIX = "/opentool-daemon";
const String SERVER_PREFIX = "/servers";
const String TOOL_PREFIX = "/tools";
