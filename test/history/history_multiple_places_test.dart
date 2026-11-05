import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/utils/bookmark_from_tab.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/navigation_repository.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/services/backup/backup_merge.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/workspaces/workspace.dart';

import '../helpers/memory_settings_cache.dart';

class _MemoryHistoryRepository extends HistoryRepository {
  _MemoryHistoryRepository([List<Bookmark> items = const []])
    : stored = List<Bookmark>.from(items);

  List<Bookmark> stored;
  int lastMutationMicroseconds = 0;

  @override
  Future<List<Bookmark>> load() async => stored;

  @override
  Future<List<Bookmark>> mutate(
    List<Bookmark> Function(List<Bookmark> current) apply,
  ) async {
    final stopwatch = Stopwatch()..start();
    stored = List<Bookmark>.from(apply(List<Bookmark>.from(stored)));
    stopwatch.stop();
    lastMutationMicroseconds = stopwatch.elapsedMicroseconds;
    return List<Bookmark>.from(stored);
  }
}

class _CountingSearchBookmark extends Bookmark {
  _CountingSearchBookmark(String query, List<String> facets)
    : super(
        ref: query,
        book: TextBook(title: query),
        index: 0,
        isSearch: true,
        searchScopeFacets: facets,
      );

  int historyKeyReads = 0;

  @override
  String get historyKey {
    historyKeyReads++;
    return super.historyKey;
  }
}

class _FakeNavigationRepository implements NavigationRepository {
  @override
  Future<bool> checkLibraryIsEmpty() async => false;
  @override
  Future<void> refreshLibrary() async {}
}

final _book = TextBook(id: 7, title: 'משנה ברורה');

Bookmark _entry(int index, {String? slot}) => Bookmark(
  ref: 'משנה ברורה $index',
  book: _book,
  index: index,
  historySlot: slot,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  group('Bookmark.historyKey', () {
    test('רשומה בלי slot שומרת את המפתח הישן', () {
      expect(_entry(1).historyKey, 'book:id:7');
    });

    test('slot שונה = רשומה נפרדת לאותו ספר', () {
      expect(
        _entry(1, slot: 'a').historyKey,
        isNot(_entry(1, slot: 'b').historyKey),
      );
      expect(_entry(1, slot: 'a').historyKey, _entry(9, slot: 'a').historyKey);
    });

    test('ה-slot שורד JSON', () {
      final restored = Bookmark.fromJson(_entry(3, slot: 'a').toJson());
      expect(restored.historySlot, 'a');
      expect(_entry(3).toJson().containsKey('historySlot'), isFalse);
    });
  });

  group('HistoryBloc', () {
    Future<HistoryBloc> loadedBloc() async {
      final bloc = HistoryBloc(_MemoryHistoryRepository());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state is HistoryLoaded);
      return bloc;
    }

    Future<void> add(HistoryBloc bloc, Bookmark entry) async {
      bloc.add(BulkAddHistory([entry]));
      await bloc.stream.firstWhere(
        (state) => identical(state.history.firstOrNull, entry),
      );
    }

    test('אותה שאילתה בתחומים ובסינונים שונים נשמרת בנפרד', () async {
      final bloc = await loadedBloc();
      Bookmark search(List<String>? scope, {List<String>? filter}) => Bookmark(
        ref: 'ממון מזיק',
        book: TextBook(title: 'ממון מזיק'),
        index: 0,
        isSearch: true,
        searchScopeFacets: scope,
        searchFilterFacets: filter,
      );
      final all = search(null);
      final scoped = search(['/רשבא', '/ריטבא']);
      final filtered = search(['/רשבא', '/ריטבא'], filter: ['/רשבא']);
      final empty = search(['/רשבא', '/ריטבא'], filter: []);
      for (final entry in [all, scoped, filtered, empty]) {
        await add(bloc, entry);
      }
      expect(bloc.state.history, [empty, filtered, scoped, all]);

      final reordered = search(['/ריטבא', '/רשבא', '/רשבא']);
      await add(bloc, reordered);
      expect(bloc.state.history, [reordered, empty, filtered, all]);
    });

    test('סינוני מחבר ותקופה בכל הספרייה נשמרים כחיפושים נפרדים', () async {
      final bloc = await loadedBloc();
      final entries = <Bookmark>[];
      for (final dimension in <String?>[
        null,
        '/author/מחבר א',
        '/author/מחבר ב',
        '/era/ראשונים',
        '/base',
      ]) {
        final entry = Bookmark(
          ref: 'ממון מזיק',
          book: TextBook(title: 'ממון מזיק'),
          index: 0,
          isSearch: true,
          searchFilterFacets: dimension == null ? null : ['/', dimension],
        );
        entries.add(entry);
        await add(bloc, entry);
      }
      expect(bloc.state.history, entries.reversed.toList());
    });

    for (final operation in ['הוספת מקום', 'מחיקת מקום', 'חיפוש חדש']) {
      test(
        'היסטוריה גדולה: $operation מדלג על מפתחות חיפוש לא קשורים',
        () async {
          final facets = List.generate(
            5000,
            (i) => '/personal/folder/uid:${5000 - i}',
          );
          final searches = List.generate(
            200,
            (i) => _CountingSearchBookmark('שאילתה $i', facets),
          );
          final reading = _entry(42);
          final removing = operation == 'מחיקת מקום';
          // במחיקה נזרעת גם רשומת היעד, כדי למדוד תמיד 200 חיפושים אחרים.
          final repository = _MemoryHistoryRepository([
            if (removing) reading,
            ...searches,
          ]);
          final bloc = HistoryBloc(repository);
          addTearDown(bloc.close);
          await bloc.stream.firstWhere((state) => state is HistoryLoaded);

          if (removing) {
            bloc.add(RemoveHistory(0));
            await bloc.stream.firstWhere(
              (state) => state.history.length == 200,
            );
            expect(bloc.state.history, searches);
          } else {
            final incoming = operation == 'חיפוש חדש'
                ? Bookmark(
                    ref: 'שאילתה חדשה',
                    book: TextBook(title: 'שאילתה חדשה'),
                    index: 0,
                    isSearch: true,
                    searchScopeFacets: facets,
                  )
                : reading;
            await add(bloc, incoming);
            expect(bloc.state.history, [incoming, ...searches.take(199)]);
          }

          final keyReads = searches.fold<int>(
            0,
            (sum, entry) => sum + entry.historyKeyReads,
          );
          debugPrint(
            'history prefilter: $operation; 200 searches x 5000 facets; '
            '${repository.lastMutationMicroseconds} us; $keyReads existing keys',
          );
          expect(keyReads, 0);
        },
      );
    }

    test('שני מקומות באותו ספר נשמרים שניהם', () async {
      final bloc = await loadedBloc();
      final first = _entry(10);
      final second = _entry(500, slot: 'b');

      await add(bloc, first);
      await add(bloc, second);

      expect(bloc.state.history, [second, first]);
    });

    test(
      'לכידת PDF מפוצל ושמירת מקום שהתעדכן אינן דורסות את המקום השני',
      () async {
        final bloc = await loadedBloc();
        final firstController = _ReadyPdfController(10);
        final secondController = _ReadyPdfController(50);
        final book = PdfBook(title: 'ספר', path: '/a.pdf');
        final first = PdfBookTab(book: book, pageNumber: 10)
          ..historySlot = 'a'
          ..pdfViewerController = firstController;
        final second = PdfBookTab(book: book, pageNumber: 50)
          ..historySlot = 'b'
          ..pdfViewerController = secondController;
        final combined = CombinedTab(rightTab: first, leftTab: second);
        addTearDown(combined.dispose);
        bloc.add(AddHistory(combined));
        await bloc.stream.firstWhere((s) => s.history.length == 2);
        expect(
          {
            for (final entry in bloc.state.history)
              entry.historySlot: entry.index,
          },
          {'a': 10, 'b': 50},
        );
        secondController.page = 60;
        bloc.add(CaptureStateForHistory(second));
        await pumpEventQueue();
        bloc.add(FlushHistory());
        await bloc.stream.firstWhere((s) => s.history.first.index == 60);
        expect(
          {
            for (final entry in bloc.state.history)
              entry.historySlot: entry.index,
          },
          {'a': 10, 'b': 60},
        );
      },
    );

    test('אותו slot מעדכן את רשומתו ולא מוסיף', () async {
      final bloc = await loadedBloc();
      final other = _entry(10);
      await add(bloc, other);
      await add(bloc, _entry(500, slot: 'b'));
      final moved = _entry(520, slot: 'b');

      await add(bloc, moved);

      expect(bloc.state.history, [moved, other]);
    });
  });

  group('טאבים', () {
    test('ה-slot נשמר ב-JSON ובהעתקה של טאב טקסט ו-PDF', () {
      final text = TextBookTab(book: _book, index: 3)..historySlot = 'a';
      final pdf = PdfBookTab(
        book: PdfBook(title: 'ברכות', path: '/b.pdf'),
        pageNumber: 2,
      )..historySlot = 'p';
      addTearDown(text.dispose);
      addTearDown(pdf.dispose);

      final restoredText = TextBookTab.fromJson(text.toJson());
      final restoredPdf = PdfBookTab.fromJson(pdf.toJson());
      final copiedText = OpenedTab.from(text);
      final copiedPdf = OpenedTab.from(pdf);
      addTearDown(restoredText.dispose);
      addTearDown(restoredPdf.dispose);
      addTearDown(copiedText.dispose);
      addTearDown(copiedPdf.dispose);

      expect(restoredText.historySlot, 'a');
      expect(restoredPdf.historySlot, 'p');
      expect(copiedText.historySlot, 'a');
      expect(copiedPdf.historySlot, 'p');
    });

    test('פתיחה מרשומת היסטוריה לוקחת את ה-slot שלה', () {
      final tab = tabFromBookmark(_entry(500, slot: 'b'));
      addTearDown(tab.dispose);
      expect(tab.historySlot, 'b');
    });

    test('newHistorySlot אינו חוזר על עצמו גם ברצף מהיר', () {
      final slots = List.generate(50, (_) => OpenedTab.newHistorySlot());
      expect(slots.toSet(), hasLength(50));
    });
  });

  group('TabsBloc ו-BookOpenCoordinator', () {
    late Directory tempDir;
    late TabsBloc tabsBloc;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('history_places_test');
      Hive.init(tempDir.path);
      await Hive.openBox<dynamic>('tabs');
      tabsBloc = TabsBloc(repository: TabsRepository());
    });

    tearDown(() async {
      await tabsBloc.close();
      await Hive.deleteFromDisk();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    Future<BookOpenCoordinator> coordinator(List<Bookmark> history) async {
      final historyBloc = HistoryBloc(_MemoryHistoryRepository(history));
      final navigationBloc = NavigationBloc(
        repository: _FakeNavigationRepository(),
        tabsRepository: TabsRepository(),
      );
      addTearDown(historyBloc.close);
      addTearDown(navigationBloc.close);
      await historyBloc.stream.firstWhere(
        (state) => state.history.length == history.length,
      );
      return BookOpenCoordinator(
        tabsBloc: tabsBloc,
        historyBloc: historyBloc,
        navigationBloc: navigationBloc,
      );
    }

    test('פתיחת ספר ממשיכה את רשומתו האחרונה כשאינה פתוחה', () async {
      final opener = await coordinator([_entry(500, slot: 'b'), _entry(10)]);

      final tab = opener.buildTab(_book, 0, '');
      addTearDown(tab.dispose);

      expect(tab.historySlot, 'b');
      expect((tab as TextBookTab).index, 500);
    });

    test('ספר שכבר פתוח בטאב אחר מקבל רשומה חדשה', () async {
      final open = TextBookTab(book: _book, index: 500)..historySlot = 'b';
      tabsBloc.add(AddTab(open));
      await pumpEventQueue();
      final opener = await coordinator([_entry(500, slot: 'b')]);

      // תוצאת חיפוש בספר הפתוח: טאב חדש, שאינו דורס את מקום הטאב הפתוח.
      tabsBloc.add(AddTab(opener.buildTab(_book, 40, '', explicitIndex: true)));
      await pumpEventQueue();

      final added = tabsBloc.state.tabs.firstWhere((t) => t != open);
      expect(added.historySlot, isNotNull);
      expect(added.historySlot, isNot('b'));
      expect(open.historySlot, 'b');
    });

    test('טאב ללא slot ליד טאב ללא slot של אותו ספר מקבל slot', () async {
      final open = TextBookTab(book: _book, index: 10);
      final second = TextBookTab(book: _book, index: 900);
      tabsBloc.add(AddTab(open));
      tabsBloc.add(AddTab(second));
      await pumpEventQueue();

      expect(open.historySlot, isNull);
      expect(second.historySlot, isNotNull);
    });

    test('פתיחה בחלונית צד אינה דורסת טאב פתוח אחר של אותו ספר', () async {
      final open = TextBookTab(book: _book, index: 10)..historySlot = 'a';
      tabsBloc.add(AddTab(open));
      await pumpEventQueue();
      tabsBloc.add(
        AddTab(TextBookTab(book: TextBook(id: 8, title: 'אחר'), index: 0)),
      );
      await pumpEventQueue();
      final incoming = TextBookTab(book: _book, index: 50)..historySlot = 'a';
      tabsBloc.add(OpenTabInSidePane(incoming));
      await pumpEventQueue();
      expect(tabsBloc.state.tabs.last, isA<CombinedTab>());
      expect(incoming.historySlot, isNot(open.historySlot));
    });

    for (final specific in [false, true]) {
      test(
        'סגירה, פתיחה מההיסטוריה ושחזור ${specific ? 'מפורש' : 'אחרון'} מפרידים מקומות',
        () async {
          final closed = TextBookTab(book: _book, index: 10)..historySlot = 'a';
          tabsBloc.add(AddTab(closed));
          await pumpEventQueue();
          tabsBloc.add(RemoveTab(closed));
          await pumpEventQueue();
          final reopened = TextBookTab(book: _book, index: 50)
            ..historySlot = 'a';
          tabsBloc.add(AddTab(reopened));
          await pumpEventQueue();
          if (specific) {
            tabsBloc.add(RestoreClosedTab(tabsBloc.recentlyClosedTabs.single));
          } else {
            tabsBloc.add(const RestoreLastClosedTab());
          }
          await pumpEventQueue();
          expect(tabsBloc.state.tabs, hasLength(2));
          expect(
            tabsBloc.state.tabs.map((t) => t.historySlot).toSet(),
            hasLength(2),
          );
          expect(reopened.historySlot, 'a');
        },
      );
    }

    test(
      'פתיחה חוזרת של תבנית מוצמדת ישנה אינה צוברת רשומות היסטוריה',
      () async {
        final book = PdfBook(title: 'ספר', path: '/a.pdf');
        final originals = [
          PdfBookTab(book: book, pageNumber: 10),
          PdfBookTab(book: book, pageNumber: 50),
        ];
        final raw = Workspace(
          name: 'תבנית',
          isPinned: true,
          tabs: originals,
        ).toJson();
        for (final tab in originals) {
          tab.dispose();
        }
        final history = HistoryBloc(_MemoryHistoryRepository());
        addTearDown(history.close);
        await history.stream.firstWhere((s) => s is HistoryLoaded);
        int? firstCount;
        for (var i = 0; i < 2; i++) {
          final restored = Workspace.fromJson(raw);
          expect(restored.isPinned, isTrue);
          tabsBloc.add(ReplaceAllTabs(restored.tabs, 0));
          await pumpEventQueue();
          for (final tab in tabsBloc.state.tabs.cast<PdfBookTab>()) {
            tab.pdfViewerController = _ReadyPdfController(tab.pageNumber);
          }
          final updated = history.stream.first;
          history.add(AddHistoryForTabs(tabsBloc.state.tabs));
          await updated;
          firstCount ??= history.state.history.length;
          expect(history.state.history, hasLength(firstCount));
        }
        expect(firstCount, 1);
        expect(tabsBloc.state.tabs.map((t) => t.historySlot), [null, null]);
      },
    );

    test('טאב של ספר אחר אינו מקבל slot חדש', () async {
      tabsBloc.add(AddTab(TextBookTab(book: _book, index: 10)));
      final other = TextBookTab(
        book: TextBook(id: 8, title: 'ספר אחר'),
        index: 0,
      );
      tabsBloc.add(AddTab(other));
      await pumpEventQueue();

      expect(other.historySlot, isNull);
    });

    test('שכפול טאב יוצר מקום נפרד בהיסטוריה', () async {
      final original = TextBookTab(book: _book, index: 500)..historySlot = 'b';
      tabsBloc.add(AddTab(original));
      await pumpEventQueue();

      tabsBloc.add(CloneTab(original));
      await pumpEventQueue();

      final copy = tabsBloc.state.tabs.firstWhere((t) => t != original);
      expect(copy.historySlot, isNotNull);
      expect(copy.historySlot, isNot('b'));
      expect(original.historySlot, 'b');
    });
  });

  test('מיזוג גיבוי משמר את שני המקומות של אותו ספר', () {
    Map<String, dynamic> raw(int index, {String? slot}) =>
        _entry(index, slot: slot).toJson();
    final merged = BackupMerge.merge(
      {
        'history': [raw(10)],
      },
      {
        'history': [raw(500, slot: 'b')],
      },
      olderTimestamp: DateTime(2025, 1, 1),
      newerTimestamp: DateTime(2025, 6, 1),
      now: DateTime(2025, 7, 1),
    );
    expect(merged['history'] as List, hasLength(2));
  });
}

class _ReadyPdfController extends PdfViewerController {
  _ReadyPdfController(this.page);
  int page;
  @override
  bool get isReady => true;
  @override
  int? get pageNumber => page;
}
