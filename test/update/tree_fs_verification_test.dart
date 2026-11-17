import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/update/differential/tree_fs.dart';
import 'package:path/path.dart' as p;

Future<String> _hashExpectedSizeFile(String path) async {
  if (p.basename(path) == 'wrong-size.bin') {
    throw StateError('wrong-size.bin was read for hashing');
  }
  return (await sha256.bind(File(path).openRead()).first).toString();
}

void main() {
  test('אימות עץ מגבב רק קבצים בגודל הצפוי ושומר על סדר השגיאות', () async {
    final root = await Directory.systemTemp.createTemp('otzaria-tree-verify');
    addTearDown(() => root.delete(recursive: true));
    final expectedContent = [1, 2, 3];
    final expected = TreeFile(
      size: expectedContent.length,
      sha256: sha256.convert(expectedContent).toString(),
    );
    await File(p.join(root.path, 'wrong-size.bin')).writeAsBytes([1, 2]);
    await File(p.join(root.path, 'wrong-digest.bin')).writeAsBytes([3, 2, 1]);
    await File(p.join(root.path, 'correct.bin')).writeAsBytes(expectedContent);

    expect(
      await verifyTree(
        fs: const LocalTreeFileSystem(),
        root: root.path,
        newTree: TreeManifest(
          files: {
            'wrong-size.bin': expected,
            'wrong-digest.bin': expected,
            'correct.bin': expected,
          },
          links: const {},
        ),
        allowUnmanaged: false,
        hashFile: _hashExpectedSizeFile,
      ),
      [
        'wrong-size.bin: the content does not match',
        'wrong-digest.bin: the content does not match',
      ],
    );
  });
}
