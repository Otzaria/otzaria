// בדיקת שטח אמיתית לחיפוש המקורב עם מילון מורפולוגי (lexical.db), מול מנוע
// ה-Rust הממשי דרך flutter_rust_bridge — לא mock.
//
// הרצה (macOS):   flutter test integration_test/magic_search_test.dart -d macos
//        (Linux): flutter test integration_test/magic_search_test.dart -d linux
//
// מאמת את הדרישה המרכזית: החיפוש המקורב הוא מסלול נפרד. חיפוש "מדויק" לא
// דולף להטיות, חיפוש "מקורב" ללא מילון לא מגיע אליהן (מרחק עריכה גדול מדי),
// ורק כשנטען מילון — המקורב מוצא את ההטיה. בנוסף: fallback נקי כשאין קובץ.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUpAll(() async {
    await RustLib.init();
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('magic_it_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  // בונה lexical.db זעיר באותה סכמה של ה-DB האמיתי: למה "הלכ" עם צורות
  // השטח "הלכתי"/"הולכ" (מקופלות, כפי שה-DB האמיתי מאחסן).
  String buildLexicalDb() {
    final path = p.join(tmp.path, 'lexical.db');
    final db = sqlite3.open(path);
    db.execute('''
      CREATE TABLE base (id INTEGER PRIMARY KEY AUTOINCREMENT, value TEXT NOT NULL UNIQUE);
      CREATE TABLE surface (id INTEGER PRIMARY KEY AUTOINCREMENT, value TEXT NOT NULL UNIQUE, base_id INTEGER NOT NULL REFERENCES base(id), notes TEXT);
      CREATE TABLE variant (id INTEGER PRIMARY KEY AUTOINCREMENT, value TEXT NOT NULL UNIQUE);
      CREATE TABLE surface_variant (surface_id INTEGER NOT NULL REFERENCES surface(id), variant_id INTEGER NOT NULL REFERENCES variant(id), PRIMARY KEY (surface_id, variant_id));
      INSERT INTO base (id, value) VALUES (1, 'הלכ');
      INSERT INTO surface (id, value, base_id) VALUES (1, 'הלכתי', 1), (2, 'הולכ', 1);
    ''');
    db.close();
    return path;
  }

  // בונה אינדקס Tantivy אמיתי: רק ההטיה "הלכתי" מאונדקסת (הלמה "הלך" רחוקה
  // 3 עריכות), ומסמך נוסף שאינו במרחק fuzzy של "הלך".
  Future<SearchEngine> buildIndex() async {
    final indexDir = p.join(tmp.path, 'index');
    await Directory(indexDir).create(recursive: true);
    final engine = SearchEngine(path: indexDir);
    await engine.addDocument(
      id: BigInt.one,
      title: 'a',
      reference: 'a',
      topics: '/root',
      text: 'הלכתי',
      segment: BigInt.zero,
      isPdf: false,
      filePath: '/books/a.txt',
    );
    await engine.addDocument(
      id: BigInt.two,
      title: 'b',
      reference: 'b',
      topics: '/root',
      text: 'מזרח',
      segment: BigInt.zero,
      isPdf: false,
      filePath: '/books/b.txt',
    );
    await engine.commit();
    return engine;
  }

  Future<List<SearchResult>> exact(SearchEngine e, String q) => e.searchExact(
        query: q,
        facets: const ['/root'],
        limit: 10,
        offset: 0,
        order: ResultsOrder.relevance,
        matchNikud: false,
        matchTaamim: false,
      );

  Future<List<SearchResult>> fuzzy(SearchEngine e, String q) => e.searchFuzzy(
        query: q,
        facets: const ['/root'],
        limit: 10,
        offset: 0,
        maxDistance: 2,
        order: ResultsOrder.relevance,
        matchNikud: false,
        matchTaamim: false,
      );

  testWidgets('מקורב מוצא הטיה דרך המילון; מדויק לא דולף', (tester) async {
    final engine = await buildIndex();

    // מדויק: "הלך" אסור שיחזיר את ההטיה "הלכתי".
    expect(await exact(engine, 'הלך'), isEmpty,
        reason: 'חיפוש מדויק לא אמור לדלוף להטיות');

    // מקורב ללא מילון: "הלך"→"הלכתי" הוא 3 עריכות — מעבר ל-maxDistance=2.
    expect(engine.hasMagicDictionary(), isFalse);
    expect(await fuzzy(engine, 'הלך'), isEmpty,
        reason: 'מקורב ללא מילון לא מגיע להטיה במרחק 2');

    // טעינת המילון אל המנוע החי.
    expect(engine.setMagicDictionaryPath(path: buildLexicalDb()), isTrue);
    expect(engine.hasMagicDictionary(), isTrue);

    // מקורב עם מילון: כעת ההרחבה הלקסיקלית מזריקה את "הלכתי" → התאמה.
    final results = await fuzzy(engine, 'הלך');
    expect(results, isNotEmpty, reason: 'מקורב עם מילון חייב למצוא את ההטיה');
    expect(results.any((r) => r.text.contains('הלכתי')), isTrue);
  });

  testWidgets('setMagicDictionaryPath מחזיר false לקובץ חסר ולא טוען מילון',
      (tester) async {
    final engine = await buildIndex();
    final missing = p.join(tmp.path, 'nope.db');
    expect(engine.setMagicDictionaryPath(path: missing), isFalse);
    expect(engine.hasMagicDictionary(), isFalse);

    // והמסלול המקורב עדיין עובד (fallback ל-fuzzy רגיל) — "הלכתי" עם שיבוש
    // קל (מרחק 1) עדיין נמצא.
    final near = await fuzzy(engine, 'הלכתל'); // ת→ל, מרחק 1 מ-"הלכתי"
    expect(near.any((r) => r.text.contains('הלכתי')), isTrue);
  });
}
