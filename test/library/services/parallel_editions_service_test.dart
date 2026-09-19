import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/services/parallel_editions_service.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_external_editions_registry.dart';

InstalledPlugin _plugin() {
  final manifest = PluginManifest.fromJson({
    'schemaVersion': 1,
    'id': 'test.editions.plugin',
    'name': 'Test Plugin',
    'version': '1.0.0',
    'entrypoint': 'index.html',
    'minAppVersion': '0.9.97',
    'sdkVersion': '1.x',
    'permissions': const ['database.read', 'library.books.read'],
    'contributes': {
      'databaseSources': [
        {'id': 'mapping_source', 'label': 'מיפוי', 'required': true},
      ],
    },
  });
  return InstalledPlugin(
    pluginId: 'test.editions.plugin',
    name: 'Test Plugin',
    version: '1.0.0',
    installPath: '/plugins/test',
    entrypointPath: '/plugins/test/index.html',
    enabled: true,
    pinned: false,
    manifest: manifest,
    installedAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

// שם הספק בקונפיגורציה חייב להתאים לזהות החיצונית של ספריו — קידומות
// הזיהוי ('hb:') הן קבועות-מארח, ולכן הבדיקה משתמשת בספק hebrewbooks.
PluginExternalEditionsConfig _config() => PluginExternalEditionsConfig(
  plugin: _plugin(),
  id: 'editions-1',
  provider: 'hebrewbooks',
  sourceId: 'mapping_source',
  table: 'mapping',
  externalIdColumn: 'ext_id',
  otzariaIdColumn: 'otzaria_id',
  orderBy: const [(column: 'quality', descending: true)],
);

/// ספר מקומי של הספק (נפתח בקורא) עם מזהה חיצוני של הספק.
PdfBook _localExternalBook(int id) => PdfBook(
  id: id,
  title: 'ספר $id',
  path: '/books/$id.pdf',
  externalLibraryId: 'hb:$id',
);

void main() {
  late List<Map<String, dynamic>> recordedSpecs;
  late List<List<int>> queryResponses;
  late Set<Object>? loaderRequestedIds;
  late List<Book> loaderResponse;

  setUp(() {
    recordedSpecs = [];
    queryResponses = [];
    loaderRequestedIds = null;
    loaderResponse = const [];
    ParallelEditionsService.queryRunner = (plugin, spec) async {
      recordedSpecs.add(spec);
      final ids = queryResponses.removeAt(0);
      return {
        'rows': [
          for (final id in ids) {'value': id},
        ],
      };
    };
    ParallelEditionsService.externalBooksLoader = (provider, ids) async {
      loaderRequestedIds = ids;
      return loaderResponse;
    };
  });

  tearDown(() {
    ParallelEditionsService.queryRunner = (plugin, spec) =>
        throw UnimplementedError();
    ParallelEditionsService.externalBooksLoader = (provider, ids) =>
        throw UnimplementedError();
    ParallelEditionsService.builtInExternalIdsFor = (id) =>
        throw UnimplementedError();
    ParallelEditionsService.builtInOtzariaIdsFor = (id) =>
        throw UnimplementedError();
  });

  test('ספר ספרייה: מיפוי ישיר, סינון לא-מקומיים ושימור סדר', () async {
    queryResponses = [
      [11, 12, 11, 13],
    ];
    loaderResponse = [
      _localExternalBook(13),
      _localExternalBook(11),
      // ספר קטלוג בלבד (נפתח באתר) — לא מהדורה מקבילה בקורא.
      ExternalLibraryBook(
        title: 'קטלוג 12',
        id: 12,
        link: 'https://example.org/12',
        externalLibraryId: 'hb:12',
      ),
    ];

    final current = PdfBook(id: 5, title: 'ספר נוכחי', path: '/books/5.pdf');
    final editions = await ParallelEditionsService.externalEditionsFor(
      current,
      _config(),
    );

    // סדר איכות ההתאמה מהמיפוי נשמר (11 לפני 13), כפילות 11 הוסרה,
    // ו-12 סונן כי אינו מקומי.
    expect([for (final book in editions) book.id], [11, 13]);

    expect(recordedSpecs, hasLength(1));
    final spec = recordedSpecs.single;
    expect(spec['sourceId'], 'mapping_source');
    expect(spec['from'], {'table': 'mapping', 'alias': 'm'});
    expect(spec['where'], {
      'op': 'in',
      'left': 'm.otzaria_id',
      'value': [5],
    });
    expect(spec['orderBy'], [
      {'expr': 'm.quality', 'direction': 'desc'},
    ]);
    // הטוען מקבל את כל המזהים (אחרי דה-דופליקציה); הסינון המקומי אחריו.
    expect(loaderRequestedIds, {11, 12, 13});
  });

  test('ספר של הספק: שני צעדים במיפוי והחרגת הספר הנוכחי', () async {
    queryResponses = [
      [3, 4], // otzaria ids הממופים לספר הנוכחי
      [7, 8, 9], // כל מהדורות הספק של אותם ספרים, כולל הנוכחי (7)
    ];
    loaderResponse = [_localExternalBook(8), _localExternalBook(9)];

    final current = PdfBook(
      id: 7,
      title: 'ספר ספק',
      path: '/books/7.pdf',
      externalLibraryId: 'hb:7',
    );
    final config = PluginExternalEditionsConfig(
      plugin: _plugin(),
      id: 'editions-1',
      provider: 'hebrewbooks',
      sourceId: 'mapping_source',
      table: 'mapping',
      externalIdColumn: 'ext_id',
      otzariaIdColumn: 'otzaria_id',
      orderBy: const [],
    );
    final editions = await ParallelEditionsService.externalEditionsFor(
      current,
      config,
    );

    expect([for (final book in editions) book.id], [8, 9]);
    expect(recordedSpecs, hasLength(2));
    expect(recordedSpecs.first['where'], {
      'op': 'in',
      'left': 'm.ext_id',
      'value': [7],
    });
    expect(recordedSpecs.last['where'], {
      'op': 'in',
      'left': 'm.otzaria_id',
      'value': [3, 4],
    });
  });

  test('ספר ספרייה בלי מזהה — אין שאילתות בכלל', () async {
    final current = TextBook(title: 'בלי מזהה');
    final editions = await ParallelEditionsService.externalEditionsFor(
      current,
      _config(),
    );
    expect(editions, isEmpty);
    expect(recordedSpecs, isEmpty);
  });

  test('ספר ממסד אחר — המזהה שלו אינו מזהה אוצריא, אין שאילתות', () async {
    for (final source in [BookSource.user, BookSource.attached('my-db')]) {
      final current = TextBook(id: 3, title: 'ספר', source: source);
      final editions = await ParallelEditionsService.externalEditionsFor(
        current,
        _config(),
      );
      expect(editions, isEmpty);
    }
    expect(recordedSpecs, isEmpty);
  });

  test('מיפוי ריק — לא פונים לטוען הספרים', () async {
    queryResponses = [[]];
    final current = PdfBook(id: 5, title: 'ספר', path: '/books/5.pdf');
    final editions = await ParallelEditionsService.externalEditionsFor(
      current,
      _config(),
    );
    expect(editions, isEmpty);
    expect(loaderRequestedIds, isNull);
  });

  group('מיפוי היברובוקס המובנה (issue #1273)', () {
    test('ספר ספרייה: מהדורות מקומיות בלי תוסף רשום', () async {
      final requested = <int>[];
      ParallelEditionsService.builtInExternalIdsFor = (id) async {
        requested.add(id);
        return [21, 22];
      };
      loaderResponse = [_localExternalBook(22), _localExternalBook(21)];

      final current = TextBook(id: 5, title: 'חולין');
      final editions = await ParallelEditionsService.builtInEditionsFor(
        current,
      );

      expect([for (final book in editions) book.id], [21, 22]);
      expect(requested, [5]);
      expect(recordedSpecs, isEmpty);
    });

    test('ספר היברובוקס: שני צעדים במיפוי והחרגת הספר הנוכחי', () async {
      ParallelEditionsService.builtInOtzariaIdsFor = (id) async => [3, 4];
      ParallelEditionsService.builtInExternalIdsFor = (id) async =>
          id == 3 ? [7, 8] : [9, 8];
      loaderResponse = [_localExternalBook(8), _localExternalBook(9)];

      final current = PdfBook(
        id: 7,
        title: 'ספר ספק',
        path: '/books/7.pdf',
        externalLibraryId: 'hb:7',
      );
      final editions = await ParallelEditionsService.builtInEditionsFor(
        current,
      );

      expect([for (final book in editions) book.id], [8, 9]);
      expect(loaderRequestedIds, {8, 9});
    });
  });
}
