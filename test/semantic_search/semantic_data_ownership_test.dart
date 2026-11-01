import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/semantic_search/repository/semantic_data_ownership.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('semantic_links_'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<Link> directoryLink(String name, String target) async {
    final link = Link(p.join(root.path, name));
    if (Platform.isWindows) {
      final result = await Process.run('cmd', [
        '/c',
        'mklink',
        '/J',
        link.path,
        target,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout} ${result.stderr}');
    } else {
      await link.create(target);
    }
    expect(await FileSystemEntity.isLink(link.path), isTrue);
    return link;
  }

  for (final marker in [kSemanticOwnerMarker, 'CURRENT', 'PREVIOUS']) {
    test('קישור שורש עם $marker נמחק בלי למחוק את היעד', () async {
      final target = Directory(p.join(root.path, 'target'))..createSync();
      final payload = File(p.join(target.path, 'model.onnx'))
        ..writeAsStringSync('model');
      final ownership = File(p.join(target.path, marker))..createSync();
      final link = await directoryLink('legacy', target.path);

      expect(await deleteSemanticOwnedDirectory(link.path), isTrue);

      expect(await link.exists(), isFalse);
      expect(await ownership.exists(), isTrue);
      expect(await payload.readAsString(), 'model');
    });
  }

  test('קישור שורש לתיקייה זרה נשאר עם היעד שלו', () async {
    final target = Directory(p.join(root.path, 'target'))..createSync();
    final payload = File(p.join(target.path, 'model.onnx'))
      ..writeAsStringSync('model');
    final link = await directoryLink('foreign', target.path);

    expect(await deleteSemanticOwnedDirectory(link.path), isFalse);

    expect(await link.exists(), isTrue);
    expect(await payload.readAsString(), 'model');
  });

  test('מחיקת תיקייה שלנו אינה נכנסת לקישור שבתוכה', () async {
    final target = Directory(p.join(root.path, 'target'))..createSync();
    final payload = File(p.join(target.path, 'model.onnx'))
      ..writeAsStringSync('model');
    final ours = p.join(root.path, 'owned');
    await markSemanticDirectory(ours);
    await directoryLink(p.join('owned', 'nested'), target.path);

    expect(await deleteSemanticOwnedDirectory(ours), isTrue);

    expect(await Directory(ours).exists(), isFalse);
    expect(await payload.readAsString(), 'model');
  });
}
