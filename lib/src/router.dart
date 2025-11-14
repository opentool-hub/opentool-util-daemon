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
  manageRouter.get('/opentool-hub/user', manageController.getUserInfo);
  manageRouter.post('/opentool-hub/logout', manageController.logout);
}

/// /opentool-daemon/servers
void serverRoutes(ServerController serverController) {
  serverRouter.get('/list', serverController.listServers);
  serverRouter.post('/build', serverController.buildServer);
  serverRouter.delete('/<serverId>', serverController.deleteServer);
  serverRouter.post('/<serverId>/tag', serverController.tagServer);
  serverRouter.post('/<serverId>/push', serverController.pushServer);
  serverRouter.get('/<serverId>/export', serverController.exportServer);
  serverRouter.post('/import', serverController.importServer);
  serverRouter.post('/<serverId>/alias', serverController.setAlias);
}

/// /opentool-daemon/tools
void toolRoutes(ToolController toolController) {
  toolRouter.get('/list', toolController.listTools);
  toolRouter.post('/create', toolController.runServer);
  toolRouter.post('/<toolId>/start', toolController.startTool);
  toolRouter.post('/<toolId>/stop', toolController.stopTool);
  toolRouter.delete('/<toolId>', toolController.deleteTool);
  toolRouter.post('/<toolId>/call', toolController.callTool);
  toolRouter.post('/<toolId>/streamCall', toolController.streamCallTool);
  toolRouter.get('/<toolId>/load', toolController.loadTool);
  toolRouter.post('/<toolId>/alias', toolController.setAlias);
}
