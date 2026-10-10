import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite_auto_extension.dart';
import 'package:otzaria/search/in_book_search_settings.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/view/in_book_advanced_search_dialog.dart';
import 'package:otzaria/search/utils/smart_lexical_in_book_search.dart';
import 'package:otzaria/tabs/models/reading_tab_search_state.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/search_engine_test_init.dart';

Future<void> main() async {
  final ready = await tryInitSearchEngine();
  const settings = InBookSearchSettings(
    searchMode: SearchMode.fuzzy,
    matchPolicy: SearchMatchPolicy.smart,
  );

  test('מדיניות חכמה נשמרת ומשוחזרת; JSON ישן נשאר רגיל', () {
    expect(
      SearchMatchPolicy.fromJson(SearchMatchPolicy.smart.toJson()),
      SearchMatchPolicy.smart,
    );
    expect(
      SearchMatchPolicy.fromJson({'proximityScope': 'wordDistance'}),
      SearchMatchPolicy.standard,
    );
    expect(
      SearchMatchPolicy.fromJson({'querySemantics': 'future'}),
      SearchMatchPolicy.standard,
    );
  });

  test('עריכת ההגדרות בדיאלוג מחזירה את משמעות המצב שנבחר', () {
    final tab = createInBookSearchDialogTab(
      query: '"ברא אלהים" ארץ',
      searchMode: SearchMode.fuzzy,
      distance: 0,
      matchPolicy: SearchMatchPolicy.smart,
      searchOptions: const {},
      alternativeWords: const {},
      spacingValues: const {},
    );
    addTearDown(tab.dispose);
    expect(
      tab.searchBloc.state.configuration.matchPolicy.querySemantics,
      SearchQuerySemantics.regular,
    );
  }, skip: !ready);

  test('הסורק שומר כללי ציטוטי המנוע ואקרונים מנוקדים', () {
    expect(smartSearchQuotedPhrases('רַמְבַּ"ם "ברא אלהים" ״ארץ״'), [
      'ברא אלהים',
      'ארץ',
    ]);
    expect(smartSearchQuotedPhrases('„ברא אלהים” “ארץ”'), ['ברא אלהים', 'ארץ']);
    expect(smartSearchQuotedPhrases('"  " רמב"ם "לא נסגר'), isEmpty);
  });

  test('טאב קריאה משמר את המדיניות החכמה בשמירה ושחזור', () {
    const original = ReadingTabSearchState(
      searchText: '"ברא אלהים" ארץ',
      searchMode: SearchMode.fuzzy,
      matchPolicy: SearchMatchPolicy.smart,
    );
    final restored = ReadingTabSearchState.fromJson(original.toJson());
    expect(restored.matchPolicy, SearchMatchPolicy.smart);
    expect(restored.searchText, original.searchText);
    expect(restored.searchMode, SearchMode.fuzzy);
  });

  test('מדיניות ציטוט אינה משנה הדגשות קיימות או הדגשה בין שורות', () {
    for (final query in ['ברא אלהים', '"ברא אלהים"']) {
      for (final sample in [
        (line: 'ברא אלהים הארץ', next: ''),
        (line: 'שם ברא', next: 'אלהים הארץ'),
      ]) {
        final regular = utils.highLight(
          sample.line,
          query,
          isFuzzy: true,
          nextLine: sample.next,
        );
        final smart = utils.highLight(
          sample.line,
          query,
          isFuzzy: true,
          nextLine: sample.next,
          matchPolicy: SearchMatchPolicy.smart,
        );
        expect(regular, contains('color: red'));
        expect(smart, regular);
      }
    }
  }, skip: !ready);

  group('כוונת חיפוש חכם נשמרת בחיפוש בספר', () {
    late Directory temporary;
    late SearchEngine engine;
    late SearchRepository repository;
    const lines = [
      'בראשית ברא אלהים את השמים ואת הארץ',
      'ויברא אלהים את התנינם הגדלים',
      'אלהים ברא שמים',
      'הארץ היתה ברא אלהים',
      'ברא הארץ אלהים',
      'דברי הרמב"ם',
      'דברי רמב"ם',
      'יקוק',
      'יהוה',
    ];

    setUpAll(() async {
      final sqliteEntry = sqliteHostEntryAddress();
      if (sqliteEntry != BigInt.zero) {
        registerSqliteAutoExtension(sqliteEntry.toInt());
      }
      temporary = await Directory.systemTemp.createTemp('smart-in-book-');
      final databasePath = '${temporary.path}/lexical.db';
      final dictionary = sqlite3.open(databasePath);
      dictionary.execute('''
        CREATE TABLE base (id INTEGER PRIMARY KEY, value TEXT NOT NULL UNIQUE);
        CREATE TABLE surface (id INTEGER PRIMARY KEY, value TEXT NOT NULL UNIQUE, base_id INTEGER NOT NULL, notes TEXT);
        CREATE TABLE variant (id INTEGER PRIMARY KEY, value TEXT NOT NULL UNIQUE);
        CREATE TABLE surface_variant (surface_id INTEGER NOT NULL, variant_id INTEGER NOT NULL, PRIMARY KEY (surface_id, variant_id));
        INSERT INTO base VALUES (1, 'ברא'), (2, 'ארץ'), (3, 'רמב"ם');
        INSERT INTO surface VALUES (1, 'ויברא', 1, NULL), (2, 'הארץ', 2, NULL), (3, 'הרמב"ם', 3, NULL);
      ''');
      dictionary.close();
      await Directory('${temporary.path}/index').create();
      engine = await SearchEngine.newInstance(path: '${temporary.path}/index');
      expect(engine.setMagicDictionaryPath(path: databasePath), isTrue);
      for (var i = 0; i < lines.length; i++) {
        await engine.addDocument(
          id: BigInt.from(i + 1),
          title: 'בראשית',
          reference: 'שורה $i',
          topics: '/smart/book',
          text: lines[i],
          segment: BigInt.from(i),
          isPdf: false,
          filePath: 'id:1',
        );
      }
      await engine.commit();
      repository = SearchRepository(
        engineProvider: () async => RustSearchEngineOperations(engine),
      );
    });

    tearDownAll(() async {
      engine.dispose();
      if (Platform.isWindows) return;
      // תהליכוני המיזוג של המנוע עשויים עוד לכתוב לתיקייה; ניקוי תיקייה
      // זמנית אינו סיבה להפיל את הקובץ.
      try {
        await temporary.delete(recursive: true);
      } on FileSystemException {
        // ignore
      }
    });

    for (final entry in <String, List<int>>{
      'ברא אלהים': [0, 1, 2, 3, 4],
      '"ברא אלהים"': [0, 3],
      '“ברא אלהים”': [0, 3],
      '"ברא אלהים" ארץ': [0, 3],
      'ארץ "ברא אלהים"': [0, 3],
      '"ברא אלהים" "השמים"': [0],
      '"ברא" אלהים': [0, 2, 3, 4],
      'רמב"ם': [5, 6],
      '"יקוק"': [7],
    }.entries) {
      test(entry.key, () async {
        final global = await repository.searchSemantic(
          SemanticSearchRequest(
            query: entry.key,
            facets: const ['/smart/book'],
            limit: 100,
            lexicalMode: SemanticLexicalMode.fuzzy,
            retrievalMode: SemanticRetrievalMode.lexicalOnly,
          ),
        );
        final inBook = await searchBookWithEngine(
          repository,
          query: entry.key,
          bookPath: '/smart/book',
          limit: 100,
          settings: settings,
        );
        expect(inBook.map((result) => result.segment.toInt()), entry.value);
        expect(
          inBook.map((result) => result.id).toSet(),
          global.results.map((result) => result.id).toSet(),
        );
        expect(
          inBook.every((result) => result.text.contains('<font color=red>')),
          isTrue,
        );
      });
    }

    test('הקטלוג ממוין לפי id גם כשמספרי השורות בסדר אחר', () async {
      await engine.addDocumentsBatch(
        docs: [
          for (final entry in {901: 3, 899: 7, 900: 1}.entries)
            DocumentInput(
              id: BigInt.from(entry.key),
              title: 'סדר',
              reference: 'שורה',
              topics: '/order',
              text: 'ברא אלהים הארץ',
              segment: BigInt.from(entry.value),
              isPdf: false,
              filePath: 'order',
            ),
        ],
      );
      await engine.commit();
      final results = await searchBookWithEngine(
        repository,
        query: '"ברא אלהים" "הארץ"',
        bookPath: '/order',
        limit: 2,
        settings: settings,
      );
      expect(results.map((r) => r.id.toInt()), [899, 900]);
      expect(results.map((r) => r.segment.toInt()), [7, 1]);
    });

    test('אותו id בספר אחר אינו ממלא תנאי ציטוט של הספר הראשון', () async {
      await engine.addDocumentsBatch(
        docs: [
          for (final path in ['a', 'b'])
            DocumentInput(
              id: BigInt.from(999),
              title: 'תאומים',
              reference: path,
              topics: '/twins',
              text: path == 'a' ? 'ויברא אלהים הארץ' : 'ברא אלהים הארץ',
              segment: BigInt.zero,
              isPdf: false,
              filePath: path,
            ),
        ],
      );
      await engine.commit();
      final results = await searchBookWithEngine(
        repository,
        query: '"ברא אלהים" ארץ',
        bookPath: '/twins',
        limit: 1,
        settings: settings,
      );
      expect(results.map((r) => r.filePath), ['b']);
    });

    test('תנאי ציטוט חכם אינו מסתפק בביטוי שחוצה שורות', () async {
      await engine.addTextBook(
        title: 'חוצה',
        topics: '/cross',
        filePath: 'cross',
        catalogueOrder: 20,
        generationOrder: 20,
        textStorage: TextStorage.inIndex,
        text: 'אלהים סוף ברא\nאלהים סוף\nברא אלהים סוף ברא\nאלהים סוף',
      );
      await engine.commit();
      final results = await searchBookWithEngine(
        repository,
        query: '"ברא אלהים" סוף',
        bookPath: '/cross',
        limit: 100,
        settings: settings,
      );
      expect(results.map((r) => r.segment.toInt()), [2]);
      final quoted = await searchBookWithEngine(
        repository,
        query: '"ברא אלהים"',
        bookPath: '/cross',
        limit: 100,
        settings: settings,
      );
      expect(quoted.map((r) => r.segment.toInt()), [0, 2]);
      expect(quoted.first.continuesToNextLine, isTrue);
      final exact = await repository.searchTexts(
        const SearchEngineRequest(
          query: 'ברא אלהים',
          facets: ['/cross'],
          limit: 100,
        ),
      );
      expect(
        exact.any((r) => r.segment.toInt() == 0 && r.continuesToNextLine),
        isTrue,
      );
    });

    test('מעל 5000 התאמות: אין חיתוך לפי דירוג או לפני הציטוטים', () async {
      await engine.addDocumentsBatch(
        docs: [
          for (var i = 0; i < 5105; i++)
            DocumentInput(
              id: BigInt.from(10000 + i),
              title: 'גדול',
              reference: 'שורה $i',
              topics: '/large',
              text: i < 50 ? 'ויברא אלהים הארץ' : 'ברא אלהים הארץ',
              segment: BigInt.from(5105 - i),
              isPdf: false,
              filePath: 'large',
            ),
        ],
      );
      await engine.commit();
      final results = await searchBookWithEngine(
        repository,
        query: '"ברא אלהים" "הארץ"',
        bookPath: '/large',
        limit: kInBookEngineFetchLimit,
        settings: settings,
      );
      expect(results, hasLength(5000));
      expect(results.first.id.toInt(), 10050);
      expect(results.last.id.toInt(), 15049);
      expect(
        results.map((r) => r.id.toInt()),
        orderedEquals(List.generate(5000, (i) => 10050 + i)),
      );
    });

    test('מצב מקורב רגיל ממשיך להרחיב גם מילות ציטוט', () async {
      final results = await searchBookWithEngine(
        repository,
        query: '"ברא אלהים"',
        bookPath: '/smart/book',
        limit: 100,
        settings: const InBookSearchSettings(searchMode: SearchMode.fuzzy),
      );
      expect(results.map((result) => result.segment.toInt()), contains(1));
    });

    test('גבול התוצאות מועבר למנוע, לרבות גבול החלונית', () async {
      for (final limit in [1, 2, kInBookEngineFetchLimit]) {
        final results = await searchBookWithEngine(
          repository,
          query: 'ברא אלהים',
          bookPath: '/smart/book',
          limit: limit,
          settings: settings,
        );
        expect(results.length, limit < 5 ? limit : 5);
      }
    });
  }, skip: ready ? false : searchEngineSkipReason);
}
