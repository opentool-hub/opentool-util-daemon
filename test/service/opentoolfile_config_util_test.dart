import 'dart:io';
import 'package:opentool_daemon/src/service/config.dart';
import 'package:test/test.dart';

void main() {
  group('OpentoolfileConfigUtil', () {
    test('reads file contents before parsing', () async {
      final tmp = await Directory.systemTemp.createTemp('opentoolfile_test');
      final file = File('${tmp.path}/Opentoolfile');
      await file.writeAsString('''
WORKDIR build
ENTRYPOINT ["run"]
CMD ["--flag"]
''');

      final config = await OpentoolfileConfigUtil.fromFile('demo', file.path);

      expect(config.run.workdir, equals('build'));
      expect(config.run.entrypoint, equals('run'));
      expect(config.run.cmds, equals(['--flag']));

      await tmp.delete(recursive: true);
    });
  });
}
