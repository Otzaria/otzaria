import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/external_catalog/responsa/native/responsa_catalog_builder.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_catalog_writer.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_tree_reader.dart';
import 'package:otzaria/external_catalog/responsa/responsa_catalog_schema.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_structure.dart';
import 'package:path/path.dart' as p;

/// בנייה שנכשלה חייבת להשאיר את הקטלוג הקיים: אי אפשר להוריד אותו מהרשת,
/// ובנייה מלאה מההתקנה אורכת דקות ארוכות.
void main() {
  late Directory dir;
  late String target;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('responsa_writer');
    target = p.join(dir.path, 'responsa_catalog.db');
  });
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows מחזיק קובץ פתוח רגע אחרי הסגירה; תיקייה זמנית שנשארה
      // אינה כשל של הבדיקה.
    }
  });

  const fingerprint = ResponsaFingerprint(
    version: 25,
    installPath: r'C:\Program Files (x86)\ResponsaCD25',
    file00Size: 2140586529,
  );

  /// עץ מינימלי: מדף, ותחתיו חיבורים (סוג 4) שלכל אחד סימן אחד.
  /// ספר = צומת שתוכנו מקטעים ואינו מקטע בעצמו, ולכן הסימן חובה.
  List<ResponsaTreeNode> tree(List<String> titles) => [
    ResponsaTreeNode(
      name: 'שו"ת',
      param: 1 << 16,
      level: 0,
      path: 'שו"ת',
      childCount: titles.length,
    ),
    for (final (i, title) in titles.indexed) ...[
      ResponsaTreeNode(
        name: title,
        param: (ResponsaStructure.workKind << 16) | (i + 1),
        level: 1,
        path: 'שו"ת${ResponsaTreeReader.pathSeparator}$title',
        childCount: 1,
      ),
      ResponsaTreeNode(
        name: 'סימן א',
        param: (5 << 16) | (i + 1),
        level: 2,
        path:
            'שו"ת${ResponsaTreeReader.pathSeparator}$title'
            '${ResponsaTreeReader.pathSeparator}סימן א',
        childCount: 0,
      ),
    ],
  ];

  List<String> titlesIn(String path) {
    final db = sqlite3.sqlite3.open(path, mode: sqlite3.OpenMode.readOnly);
    try {
      return [
        for (final row in db.select('SELECT title FROM books ORDER BY title'))
          row['title'].toString(),
      ];
    } finally {
      db.close();
    }
  }

  test('בנייה ראשונה כותבת קטלוג קריא', () {
    final result = ResponsaCatalogWriter.build(
      nodes: tree(['אבני נזר', 'חתם סופר']),
      fingerprint: fingerprint,
      targetPath: target,
    );

    expect(result.books, 2);
    expect(titlesIn(target), ['אבני נזר', 'חתם סופר']);
    expect(File('$target.building').existsSync(), isFalse);
  });

  test('בנייה שנייה מחליפה את הקודמת', () {
    ResponsaCatalogWriter.build(
      nodes: tree(['אבני נזר']),
      fingerprint: fingerprint,
      targetPath: target,
    );
    ResponsaCatalogWriter.build(
      nodes: tree(['אבני נזר', 'ערוך לנר']),
      fingerprint: fingerprint,
      targetPath: target,
    );

    expect(titlesIn(target), ['אבני נזר', 'ערוך לנר']);
    expect(File('$target.previous').existsSync(), isFalse);
  });

  /// עץ בלי אף צומת מסוג "חיבור" — למשל כשהקריאה מהתהליך נכשלה
  /// והוחזרה רשימה ריקה. הקטלוג הקיים **אינו** נמחק.
  test('בנייה בלי ספרים נכשלת, והקטלוג הקיים נשאר', () {
    ResponsaCatalogWriter.build(
      nodes: tree(['אבני נזר']),
      fingerprint: fingerprint,
      targetPath: target,
    );

    expect(
      () => ResponsaCatalogWriter.build(
        nodes: const [],
        fingerprint: fingerprint,
        targetPath: target,
      ),
      throwsA(isA<ResponsaCatalogBuildException>()),
    );

    expect(titlesIn(target), ['אבני נזר']);
    expect(File('$target.building').existsSync(), isFalse);
  });

  test('הקטלוג נושא את גרסת הסכמה ואת נתיב ההתקנה', () {
    ResponsaCatalogWriter.build(
      nodes: tree(['אבני נזר']),
      fingerprint: fingerprint,
      targetPath: target,
    );

    final db = sqlite3.sqlite3.open(target, mode: sqlite3.OpenMode.readOnly);
    try {
      final meta = {
        for (final row in db.select('SELECT key, value FROM db_meta'))
          row['key'].toString(): row['value'].toString(),
      };
      expect(meta['catalog_schema_version'], '$responsaCatalogSchemaVersion');
      expect(meta['install_path'], fingerprint.installPath);
    } finally {
      db.close();
    }
  });
}
