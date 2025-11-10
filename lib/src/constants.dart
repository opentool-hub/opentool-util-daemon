import 'dart:io';
import 'utils/directory_util.dart';

final Map<String, String> JSON_HEADERS = {HttpHeaders.contentTypeHeader: 'application/json', HttpHeaders.cacheControlHeader: 'no-cache', HttpHeaders.connectionHeader: 'keep-alive',};
final Map<String, String> STREAM_HEADERS = {HttpHeaders.contentTypeHeader: 'text/event-stream', HttpHeaders.cacheControlHeader: 'no-cache', HttpHeaders.connectionHeader: 'keep-alive', 'Cache-Control': 'no-store',};

const String DEFAULT_REGISTRY = "https://api.opentool-hub.com";
const String OPENTOOL_FOLDER = ".opentool";
String OPENTOOL_PATH = "${DirectoryUtil.getBaseDir()}${Platform.pathSeparator}${OPENTOOL_FOLDER}";

const String SERVER_FOLDER = 'servers';
const String TOOL_FOLDER = 'tools';
const String NULL_REGISTRY = 'native';
const String NULL_REPO = 'native';
const String NULL_TAG = 'latest';

const String OPENTOOL_FILE_NAME = 'Opentoolfile';
// const String METADATA_FILE_NAME = 'metadata.json';
const String OPENTOOL_FILE_JSON_NAME = 'Opentoolfile.json';
const String OPENTOOL_DAEMON_NAME = "OpenTool Daemon";
const String SYSTEM_CONFIG_FILE_NAME = "config.json";

const int DAEMON_DEFAULT_PORT = 19627;
const String DAEMON_DEFAULT_PREFIX = "/opentool-daemon";
const String SERVER_PREFIX = "/servers";
const String TOOL_PREFIX = "/tools";