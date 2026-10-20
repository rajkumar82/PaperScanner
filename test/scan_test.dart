import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:paperscanner/models/scan.dart';

void main() {
  test(
    'a scan round-trips through scan.json and supports edit/remove',
    () async {
      final root = await Directory.systemTemp.createTemp('scan_test');
      addTearDown(() => root.delete(recursive: true));

      final photo = File('${root.path}/cam.jpg')..writeAsBytesSync([1, 2, 3]);
      final scan = await Scan.create(root);
      await scan.addPage(
        photo,
        1,
        const Rect.fromLTRB(0.1, 0.2, 0.9, 0.8),
        Uint8List.fromList([9]),
      );
      await scan.addPage(
        photo,
        0,
        const Rect.fromLTRB(0, 0, 1, 1),
        Uint8List.fromList([8]),
      );

      var loaded = (await Scan.fromDir(scan.dir))!;
      expect(loaded.pages.length, 2);
      expect(loaded.pages[0].turns, 1);
      expect(loaded.pages[0].crop, const Rect.fromLTRB(0.1, 0.2, 0.9, 0.8));
      expect(loaded.originalOf(loaded.pages[0]).readAsBytesSync(), [1, 2, 3]);

      final oldRendered = scan.renderedOf(scan.pages[0]);
      await scan.updatePage(
        0,
        3,
        const Rect.fromLTRB(0, 0, 0.5, 0.5),
        Uint8List.fromList([7]),
      );
      expect(oldRendered.existsSync(), isFalse);
      expect(scan.renderedOf(scan.pages[0]).readAsBytesSync(), [7]);

      await scan.removePage(1);
      loaded = (await Scan.fromDir(scan.dir))!;
      expect(loaded.pages.length, 1);
      expect(loaded.pages[0].turns, 3);
    },
  );
}
