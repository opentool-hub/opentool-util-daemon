import 'package:shelf_router/shelf_router.dart';
import 'controller/controller.dart';

Router daemonRouter = Router();

void daemonRoutes(Controller controller) {
  daemonRouter.get('/version', controller.getVersion);
  daemonRouter.get('/list', controller.list);
  daemonRouter.post('/register', controller.register);
  daemonRouter.post('/rename', controller.rename);
  daemonRouter.post('/call', controller.call);
  daemonRouter.post('/load', controller.load);
  daemonRouter.post('/stop', controller.stop);
  daemonRouter.post('/remove', controller.remove);
}