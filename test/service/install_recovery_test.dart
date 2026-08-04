import 'dart:io';

import 'package:opentool_daemon/src/constants.dart';
import 'package:opentool_daemon/src/service/server_service.dart';
import 'package:opentool_daemon/src/storage/dao.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_doubles.dart';

void main() {
  test(
    'startup reconciliation removes incomplete state but not external files',
    () async {
      final originalOpenToolPath = OPENTOOL_PATH;
      final temp = await Directory.systemTemp.createTemp('install_recovery_');
      OPENTOOL_PATH = p.join(temp.path, '.opentool');
      final serverDir = Directory(p.join(OPENTOOL_PATH, SERVER_FOLDER));
      final downloadDir = Directory(p.join(OPENTOOL_PATH, 'downloads'));
      await serverDir.create(recursive: true);
      await downloadDir.create(recursive: true);
      final orphan = File(p.join(serverDir.path, 'orphan.ots'));
      final pending = File(p.join(serverDir.path, 'artifact.ots.pending'));
      final part = File(p.join(downloadDir.path, 'artifact.part'));
      final external = File(p.join(temp.path, 'external.ots'));
      for (final file in [orphan, pending, part, external]) {
        await file.writeAsString('data');
      }

      final servers = StubHiveServerStorage()
        ..seed([
          ServerDao(
            id: 'broken-server',
            alias: 'broken',
            registry: 'https://hub.example',
            repo: 'litevar',
            name: 'broken',
            tag: '1.0.0',
            internalId: 'missing-internal',
          ),
        ]);
      final internals = StubHiveInternalServerStorage()
        ..seed([
          InternalServerDao(id: 'orphan', file: orphan.path),
          InternalServerDao(id: 'external', file: external.path),
        ]);
      final service = ServerService(servers, internals);

      try {
        await service.reconcileInstallations();

        expect(await service.list(), isEmpty);
        expect(await internals.list(), isEmpty);
        expect(await orphan.exists(), isFalse);
        expect(await pending.exists(), isFalse);
        expect(await part.exists(), isFalse);
        expect(await external.exists(), isTrue);
      } finally {
        OPENTOOL_PATH = originalOpenToolPath;
        await temp.delete(recursive: true);
      }
    },
  );
}
