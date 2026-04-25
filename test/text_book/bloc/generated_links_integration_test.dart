import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/generated_links/models/generated_inline_link.dart';
import 'package:otzaria/generated_links/models/generated_link_target.dart';
import 'package:otzaria/generated_links/models/generated_links_cache.dart';
import 'package:otzaria/generated_links/models/generated_links_processing_status.dart';
import 'package:otzaria/generated_links/models/processed_range.dart';
import 'package:otzaria/generated_links/repository/generated_links_cache_store.dart';
import 'package:otzaria/generated_links/services/generated_links_scheduler.dart';
import 'package:otzaria/generated_links/services/generated_links_work_gate.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:otzaria/utils/text/text_with_inline_links.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';

// ─── helpers ─────────────────────────────────────────────────────────────────

late Directory _tmpDir;

GeneratedInlineLink _makeLink({
  int bookId = 42,
  int lineIndex = 5,
  int start = 0,
  int end = 6,
}) =>
    GeneratedInlineLink(
      sourceBookId: bookId,
      sourceLineIndex: lineIndex,
      start: start,
      end: end,
      matchedText: 'ברכות ב.',
      target: const GeneratedLinkTarget(
        bookTitle: 'ברכות',
        fileType: 'txt',
        targetIndex: 1,
        displayRef: 'ברכות דף ב עמוד א',
        targetBookId: 7,
      ),
      ruleId: 'gemara.reference.v1',
      confidence: 0.9,
      createdAt: DateTime(2025, 1, 1),
    );

GeneratedLinksCache _makeCompleteCache({
  int bookId = 42,
  List<GeneratedInlineLink>? links,
  String fingerprint = '42:40',
}) =>
    GeneratedLinksCache(
      schemaVersion: GeneratedLinksCache.currentSchemaVersion,
      rulesVersion: 'v1',
      sourceBookId: bookId,
      sourceFingerprint: fingerprint,
      status: GeneratedLinksProcessingStatus.complete,
      processedRanges: const [ProcessedRange(0, 39)],
      links: links ?? [_makeLink(bookId: bookId)],
      updatedAt: DateTime(2025, 1, 1),
    );

class _FakeTextBookRepository extends TextBookRepository {
  _FakeTextBookRepository() : super(fileSystem: FileSystemData.instance);

  @override
  Future<String> getBookContent(TextBook book) async =>
      List.generate(40, (i) => 'שורה $i').join('\n');

  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async => const [];

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async =>
      const [];

  @override
  Future<List<String>> getAvailableCommentators(TextBook book) async =>
      const [];
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final v = _values[key];
    if (v is T) return v;
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> removeAll() async => _values.clear();

  @override
  Future<void> setBool(String key, bool? value) async => _values[key] = value;

  @override
  Future<void> setDouble(String key, double? value) async =>
      _values[key] = value;

  @override
  Future<void> setInt(String key, int? value) async => _values[key] = value;

  @override
  Future<void> setObject<T>(String key, T? value) async =>
      _values[key] = value;

  @override
  Future<void> setString(String key, String? value) async =>
      _values[key] = value;
}

TextBookBloc _createBloc({
  GeneratedLinksCacheStore? cacheStore,
  GeneratedLinksScheduler? scheduler,
  int bookId = 42,
}) {
  return TextBookBloc(
    repository: _FakeTextBookRepository(),
    initialState: TextBookInitial.named(
      TextBook(title: 'ברכות', id: bookId),
      10,
      false,
      const [],
      searchMode: SearchMode.exact,
    ),
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
    generatedLinksCacheStore: cacheStore,
    generatedLinksScheduler: scheduler,
  );
}

// ─── tests ───────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _tmpDir = await Directory.systemTemp.createTemp('gen_links_bloc_test_');
    await Settings.init(cacheProvider: _MemoryCacheProvider());
  });

  tearDownAll(() async {
    await _tmpDir.delete(recursive: true);
  });

  group('שלב 5 — TextBookBloc + generated links', () {
    test('ספר נטען מיד גם בלי cache — generatedLinksByLine ריק כברירת מחדל',
        () async {
      final bloc = _createBloc();

      bloc.add(const LoadContent(
        fontSize: 20,
        showSplitView: false,
        removeNikud: false,
        loadCommentators: false,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final state = bloc.state;
      expect(state, isA<TextBookLoaded>());
      final loaded = state as TextBookLoaded;
      expect(loaded.generatedLinksByLine, isEmpty);
      expect(loaded.links, isEmpty,
          reason: 'generated links לא נכנסות ל-state.links');

      await bloc.close();
    });

    test('cache קיים מוצג מיד — links מופיעים מיד לאחר LoadContent', () async {
      final store = GeneratedLinksCacheStore(basePath: _tmpDir.path);
      // שמירת cache מראש עם fingerprint '42:40' (40 שורות = תוכן ה-fake repo)
      await store.save(_makeCompleteCache(bookId: 42, fingerprint: '42:40'));

      final bloc = _createBloc(cacheStore: store);
      bloc.add(const LoadContent(
        fontSize: 20,
        showSplitView: false,
        removeNikud: false,
        loadCommentators: false,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final state = bloc.state;
      expect(state, isA<TextBookLoaded>());
      final loaded = state as TextBookLoaded;
      expect(loaded.generatedLinksByLine, isNotEmpty,
          reason: 'cache קיים חייב להיטען מיד');
      expect(loaded.generatedLinksByLine[5], isNotNull,
          reason: 'שורה 5 חייבת להכיל קישור');

      await bloc.close();
    });

    test('קישורים חדשים מופיעים לאחר batch — UpdateGeneratedLinks מעדכן state',
        () async {
      final bloc = _createBloc();
      bloc.add(const LoadContent(
        fontSize: 20,
        showSplitView: false,
        removeNikud: false,
        loadCommentators: false,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(bloc.state, isA<TextBookLoaded>());

      final link = _makeLink(lineIndex: 3);
      bloc.add(UpdateGeneratedLinks(
        sourceBookId: 42,
        generatedLinksByLine: {
          3: [link],
        },
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final loaded = bloc.state as TextBookLoaded;
      expect(loaded.generatedLinksByLine[3], contains(link));
      expect(loaded.links, isEmpty,
          reason: 'generated links לא מועתקות ל-state.links');

      await bloc.close();
    });

    test('UpdateGeneratedLinks לא משפיע על ספר אחר', () async {
      final bloc = _createBloc(bookId: 42);
      bloc.add(const LoadContent(
        fontSize: 20,
        showSplitView: false,
        removeNikud: false,
        loadCommentators: false,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final link = _makeLink(bookId: 99, lineIndex: 2);
      bloc.add(UpdateGeneratedLinks(
        sourceBookId: 99, // ספר שונה!
        generatedLinksByLine: {2: [link]},
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final loaded = bloc.state as TextBookLoaded;
      expect(loaded.generatedLinksByLine, isEmpty,
          reason: 'עדכון מספר זר לא אמור לשנות את ה-state');

      await bloc.close();
    });
  });

  group('שלב 5 — addGeneratedInlineLinksToText', () {
    test('מייצר URL תקין otzaria://generated-link עם bookId, index0 ו-book', () {
      final link = _makeLink(lineIndex: 0, start: 0, end: 6);
      final result = addGeneratedInlineLinksToText('ברכות ב. טקסט', [link]);

      expect(result, contains('otzaria://generated-link'));
      expect(result, contains('book=%D7%91%D7%A8%D7%9B%D7%95%D7%AA')); // ברכות encoded
      expect(result, contains('bookId=7')); // targetBookId יציב
      expect(result, contains('index0=1'));
      expect(result, contains('class="generated-inline-link"'));
    });

    test('טקסט ריק מוחזר כפי שהוא', () {
      final result = addGeneratedInlineLinksToText('', [_makeLink()]);
      expect(result, isEmpty);
    });

    test('רשימה ריקה מוחזרת כמו הטקסט המקורי', () {
      const text = 'טקסט ללא קישורים';
      final result = addGeneratedInlineLinksToText(text, const []);
      expect(result, text);
    });

    test('שני קישורים באותה שורה בסדר נכון', () {
      final link1 = _makeLink(lineIndex: 0, start: 0, end: 4);
      final link2 = _makeLink(lineIndex: 0, start: 10, end: 14);
      final result = addGeneratedInlineLinksToText(
          'הוהו בסס ממ בסס', [link2, link1]); // מסודרים הפוך
      final pos1 = result.indexOf('otzaria://');
      final pos2 = result.lastIndexOf('otzaria://');
      expect(pos1, lessThan(pos2), reason: 'שני קישורים חייבים להיות בסדר נכון');
    });
  });

  group('שלב 5 — ניקוי stale links אחרי full content', () {
    test(
        'ApplyFullBookContent עם fingerprint חדש מנקה links ישנים מ-state לפני batch',
        () async {
      // הכנת cache תקין ל-fingerprint '42:40' (preview)
      final store = GeneratedLinksCacheStore(basePath: _tmpDir.path);
      await store
          .save(_makeCompleteCache(bookId: 42, fingerprint: '42:40'));

      final bloc = _createBloc(cacheStore: store, bookId: 42);
      bloc.add(const LoadContent(
        fontSize: 20,
        showSplitView: false,
        removeNikud: false,
        loadCommentators: false,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // ודא שה-preview links נטענו
      final afterPreview = bloc.state as TextBookLoaded;
      expect(afterPreview.generatedLinksByLine, isNotEmpty,
          reason: 'preview links חייבים להיטען מ-cache');

      // החלפת תוכן עם fingerprint שונה (100 שורות במקום 40)
      final fullContent = List.generate(100, (i) => 'שורה $i');
      bloc.add(ApplyFullBookContent(bookTitle: 'ברכות', content: fullContent));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final afterFull = bloc.state as TextBookLoaded;
      expect(afterFull.generatedLinksByLine, isEmpty,
          reason:
              'links ישנים מה-preview חייבים להיות מנוקים לפני batch חדש');

      await bloc.close();
    });
  });

  group('שלב 5 — scheduler integration', () {
    test('batch result מ-scheduler גורם לעדכון state', () async {
      final store = GeneratedLinksCacheStore(basePath: _tmpDir.path);
      final link = _makeLink(bookId: 55, lineIndex: 7);

      final scheduler = GeneratedLinksScheduler(
        cacheStore: store,
        workGate: GeneratedLinksWorkGate(),
        rulesVersion: 'v1',
        processBatch: ({
          required sourceBookId,
          required sourceBookTitle,
          required lines,
          required startLine,
          required endLine,
          required previousRefs,
        }) async =>
            [link],
      );

      final bloc = _createBloc(cacheStore: store, scheduler: scheduler, bookId: 55);
      bloc.add(const LoadContent(
        fontSize: 20,
        showSplitView: false,
        removeNikud: false,
        loadCommentators: false,
      ));

      // המתן לטעינה + batch
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final loaded = bloc.state as TextBookLoaded;
      expect(loaded.generatedLinksByLine[7], isNotNull,
          reason: 'batch result חייב להופיע ב-state');
      expect(loaded.generatedLinksByLine[7]!.first, equals(link));

      await bloc.close();
    });
  });
}
