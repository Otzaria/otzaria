// כלי מחקר ידני: בונה קטלוג מתוך דאמפ העץ שנשמר ב-live_dump_tree_test,
// בלי לגעת בתוכנה. מאפשר לבדוק כללי שמות וקטגוריות בשניות במקום בדקות.
//
// RESPONSA_DUMP=<tree.tsv> RESPONSA_OUT=<catalog.db> \
//   flutter test test/external_catalog/live_build_from_dump_test.dart
@Tags(['live'])
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_catalog_builder.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_tree_reader.dart';
import 'package:otzaria/external_catalog/responsa/responsa_category_map.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('build from dump', () {
    final source = Platform.environment['RESPONSA_DUMP'];
    final target = Platform.environment['RESPONSA_OUT'];
    if (source == null || target == null) {
      print('set RESPONSA_DUMP and RESPONSA_OUT');
      return;
    }

    final nodes = <ResponsaTreeNode>[];
    final lines = File(source).readAsLinesSync();
    for (final line in lines.skip(1)) {
      final parts = line.split('\t');
      if (parts.length < 4) continue;
      nodes.add(
        ResponsaTreeNode(
          level: int.parse(parts[0]),
          param: int.parse(parts[1]),
          childCount: int.parse(parts[2]),
          name: parts.sublist(3).join('\t'),
          path: '',
        ),
      );
    }
    print('nodes: ${nodes.length}');

    final books = ResponsaCatalogBuilder.classify(nodes);
    print('books: ${books.length}');

    final refs = ResponsaCatalogBuilder.buildOpenRefs(books);
    print('distinct open_refs: ${refs.toSet().length}');
    print('distinct titles: ${books.map((b) => b.title).toSet().length}');

    // קטגוריות: כמה שויכו לאוצריא וכמה לא
    final unmapped = <String, int>{};
    for (final book in books) {
      final path = book.categoryNodes.join(ResponsaCategoryMap.pathSeparator);
      if (ResponsaCategoryMap.otzariaPathFor(path) == null) {
        unmapped[path] = (unmapped[path] ?? 0) + 1;
      }
    }
    print('unmapped categories: ${unmapped.length}');
    unmapped.forEach((path, n) => print('   $n  $path'));

    final random = Random(3);
    for (var i = 0; i < 15; i++) {
      final k = random.nextInt(books.length);
      print(
        '  ${books[k].title}\n      ref: ${refs[k]}'
        '\n      alt: ${ResponsaCatalogBuilder.alternativeRefs(books[k], refs[k])}'
        '\n      cat: ${books[k].categoryNodes.join(' > ')} -> '
        '${ResponsaCategoryMap.otzariaPathFor(books[k].categoryNodes.join(ResponsaCategoryMap.pathSeparator))}',
      );
    }

    final result = ResponsaCatalogBuilder.build(
      nodes: nodes,
      fingerprint: const ResponsaFingerprint(
        installPath: r'C:\Program Files (x86)\ResponsaCD25H',
        version: 25,
      ),
      targetPath: target,
    );
    print('built ${result.books} books in ${result.elapsed}');
    print('id matching: ${result.idMatching}');

    final db = sqlite3.open(target, mode: OpenMode.readOnly);
    for (final needle in [
      'קצת מהלכות אישות',
      'תורת יקותיאל אישות',
      'בכורי יוסף החדשות',
      'חתימת הספר',
      'דין קריעה ברואה',
      'מהרש"א',
      'שולחן ערוך חושן משפט',
    ]) {
      final rows = db.select(
        'SELECT title, open_ref, category_path FROM books'
        ' WHERE title LIKE ? LIMIT 2',
        ['%$needle%'],
      );
      for (final row in rows) {
        print(
          '  ${row['title']}\n      ref ${row['open_ref']}'
          '\n      cat ${row['category_path']}',
        );
      }
      if (rows.isEmpty) print('  (no hit) $needle');
    }
    db.close();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
