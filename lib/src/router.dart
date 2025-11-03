import 'package:shelf_router/shelf_router.dart';
import 'controller/manage_controller.dart';
import 'controller/server_controller.dart';
import 'controller/tool_controller.dart';

Router manageRouter = Router();
Router serverRouter = Router();
Router toolRouter = Router();

/// /opentool-daemon
void manageRoutes(ManageController manageController) {
  manageRouter.get('/version', manageController.getVersion);
  manageRouter.post('/opentool-hub/login', manageController.login);
  manageRouter.get('/opentool-hub/user', manageController.logout);
  manageRouter.post('/opentool-hub/logout', manageController.logout);
}

/// /opentool-daemon/servers
void serverRoutes(ServerController serverController) {
  serverRouter.get('/servers/list', serverController.listServers);
  serverRouter.post('/servers/build', serverController.buildServer);
  serverRouter.delete('/servers/{server_id}', serverController.deleteServer);
  serverRouter.post('/servers/{server_id}/tag', serverController.tagServer);
  serverRouter.post('/servers/{server_id}/push', serverController.pushServer);
  serverRouter.get('/servers/{serverId}/export', serverController.exportServer);
  serverRouter.post('/servers/import', serverController.importServer);
}

/// /opentool-daemon/tools
void toolRoutes(ToolController toolController) {
  toolRouter.post('/{serverId}/start', toolController.startServer);
  toolRouter.get('/list', toolController.listTools);
  toolRouter.post('/{toolId}/stop', toolController.stopTool);
  toolRouter.delete('/{toolId}', toolController.deleteTool);
  toolRouter.post('/{toolId}/call', toolController.callTool);
  toolRouter.post('/{toolId}/streamCall', toolController.streamCallTool);
  toolRouter.get('/{toolId}/load', toolController.loadTool);
}