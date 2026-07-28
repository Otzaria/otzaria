import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/navigation_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/resolving_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/utils/navigation/open_book.dart';
import '../helpers/memory_settings_cache.dart';

// ─── Fakes ───────────────────────────────────────────────────────────────────

class _FakeNavigationRepository implements NavigationRepository {
  @override
  bool checkLibraryIsEmpty() => false;
  @override
  Future<void> refreshLibrary() async {}
}

class _FakeTabsRepository implements TabsRepository {
  @override
  List<OpenedTab> loadTabs() => [];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// TabsBloc שמאפשר לבדוק אילו events נשלחו
class _CapturingTabsBloc extends TabsBloc {
  final List<TabsEvent> capturedEvents = [];

  _CapturingTabsBloc() : super(repository: _FakeTabsRepository());

  @override
  void add(TabsEvent event) {
    capturedEvents.add(event);
    // לא קוראים ל-super כדי לא לטפל ב-event (נמנע מ-side effects)
  }
}

/// HistoryRepository מינימלי שלא דורש Hive
class _FakeHistoryRepository extends HistoryRepository {
  final List<Bookmark> _items;

  _FakeHistoryRepository([this._items = const []]);

  @override
  Future<List<Bookmark>> load() async => _items;

  @override
  Future<void> save(List<Bookmark> items) async {}
}

class _FakeNavigationBloc extends NavigationBloc {
  final List<NavigationEvent> capturedEvents = [];

  _FakeNavigationBloc()
    : super(
        repository: _FakeNavigationRepository(),
        tabsRepository: _FakeTabsRepository(),
      );

  @override
  void add(NavigationEvent event) {
    capturedEvents.add(event);
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

TextBook _makeBook(String title) => TextBook(title: title);

BookOpenCoordinator _makeCoordinator({
  required _CapturingTabsBloc tabsBloc,
  _FakeNavigationBloc? navigationBloc,
  HistoryBloc? historyBloc,
}) => BookOpenCoordinator(
  tabsBloc: tabsBloc,
  historyBloc: historyBloc ?? HistoryBloc(_FakeHistoryRepository()),
  navigationBloc: navigationBloc ?? _FakeNavigationBloc(),
);

/// יוצר [HistoryBloc] טעון מראש עם רשומות היסטוריה ומחכה לטעינתן.
Future<HistoryBloc> _makeLoadedHistory(List<Bookmark> items) async {
  final bloc = HistoryBloc(_FakeHistoryRepository(items));
  // הקונסטרקטור שולח LoadHistory; ממתינים שה-state יכיל את הרשומות לפני שימוש.
  await bloc.stream.firstWhere((s) => s.history.length == items.length);
  return bloc;
}

PdfBook _makePdfBook(String title) =>
    PdfBook(title: title, path: 'c:/books/$title.pdf');

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  testWidgets('openPreparedTab פותח ResolvingTab בלי לצמצם ל-TextBookTab', (
    tester,
  ) async {
    final tabsBloc = _CapturingTabsBloc();
    final historyBloc = HistoryBloc(_FakeHistoryRepository());
    final navigationBloc = _FakeNavigationBloc();
    addTearDown(tabsBloc.close);
    addTearDown(historyBloc.close);
    addTearDown(navigationBloc.close);

    late BuildContext context;
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>.value(value: tabsBloc),
          BlocProvider<HistoryBloc>.value(value: historyBloc),
          BlocProvider<NavigationBloc>.value(value: navigationBloc),
        ],
        child: Builder(
          builder: (buildContext) {
            context = buildContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final fallback = TextBookTab(book: _makeBook('ברכות'), index: 0);
    final resolvingTab = ResolvingTab(
      fallbackTab: fallback,
      resolve: () async => fallback,
    );
    addTearDown(resolvingTab.dispose);

    openPreparedTab(context, resolvingTab, insertAdjacent: true);

    final event = tabsBloc.capturedEvents.single as OpenOrFocusTab;
    expect(event.tab, same(resolvingTab));
    expect(event.insertAdjacent, isTrue);
  });

  group('BookOpenCoordinator — mark params', () {
    // Feature: deep-link-mark, Property 6: pinpointHighlight becomes highlight
    test('Property 6: pinpointHighlight מועבר לטאב', () async {
      final testTexts = [
        'בראשית',
        'תורה',
        'hello world',
        'test123',
        'א ב ג',
        'special chars !@#',
        'עברית עם רווחים',
        'single',
      ];

      for (final pinpointText in testTexts) {
        final tabsBloc = _CapturingTabsBloc();
        final coordinator = _makeCoordinator(tabsBloc: tabsBloc);

        coordinator.openBook(
          _makeBook('ספר בדיקה'),
          0,
          '',
          pinpointHighlight: pinpointText,
        );

        expect(
          tabsBloc.capturedEvents,
          isNotEmpty,
          reason:
              'pinpointHighlight=$pinpointText: expected OpenOrFocusTab event',
        );

        final event = tabsBloc.capturedEvents.first;
        expect(
          event,
          isA<OpenOrFocusTab>(),
          reason: 'pinpointHighlight=$pinpointText: expected OpenOrFocusTab',
        );

        final tab = (event as OpenOrFocusTab).tab;
        expect(
          tab,
          isA<TextBookTab>(),
          reason: 'pinpointHighlight=$pinpointText: expected TextBookTab',
        );

        expect(
          (tab as TextBookTab).pinpointHighlight,
          pinpointText,
          reason:
              'pinpointHighlight=$pinpointText: pinpointHighlight should match',
        );
      }
    });

    test('ללא mark — searchQuery עובר כ-searchText (regression)', () async {
      final tabsBloc = _CapturingTabsBloc();
      final coordinator = _makeCoordinator(tabsBloc: tabsBloc);

      coordinator.openBook(
        _makeBook('ספר בדיקה'),
        0,
        'חיפוש רגיל',
      );

      final tab =
          ((tabsBloc.capturedEvents.first as OpenOrFocusTab).tab
              as TextBookTab);
      expect(tab.searchText, 'חיפוש רגיל');
    });

    test('pinpointHighlight מועבר לטאב', () async {
      final tabsBloc = _CapturingTabsBloc();
      final coordinator = _makeCoordinator(tabsBloc: tabsBloc);

      coordinator.openBook(
        _makeBook('ספר בדיקה'),
        0,
        'searchQuery',
        pinpointHighlight: 'pinpointText',
      );

      final tab =
          ((tabsBloc.capturedEvents.first as OpenOrFocusTab).tab
              as TextBookTab);
      expect(tab.pinpointHighlight, 'pinpointText');
    });
  });

  group('BookOpenCoordinator — navigateToPositionIfReused', () {
    // ברירת מחדל: false — שמירה על התנהגות קיימת של פתיחת ספר מהספרייה
    test('ברירת מחדל: navigateToPositionIfReused=false', () {
      final tabsBloc = _CapturingTabsBloc();
      final coordinator = _makeCoordinator(tabsBloc: tabsBloc);

      coordinator.openBook(_makeBook('ספר בדיקה'), 5, '');

      final event = tabsBloc.capturedEvents.first as OpenOrFocusTab;
      expect(event.navigateToPositionIfReused, isFalse);
    });

    // הגנה על באג deep-link: פתיחת קישור עומק חייבת להעביר את הדגל
    test('navigateToPositionIfReused=true מועבר ל-OpenOrFocusTab', () {
      final tabsBloc = _CapturingTabsBloc();
      final coordinator = _makeCoordinator(tabsBloc: tabsBloc);

      coordinator.openBook(
        _makeBook('ספר בדיקה'),
        42,
        '',
        navigateToPositionIfReused: true,
      );

      final event = tabsBloc.capturedEvents.first as OpenOrFocusTab;
      expect(
        event.navigateToPositionIfReused,
        isTrue,
        reason: 'deep-link צריך לבקש ניווט לטאב קיים',
      );
    });

    // ה-flag עובד גם כש-markText קיים — לא נכשל בגלל הפרה צדדית
    test('navigateToPositionIfReused=true עם markText מועבר נכון', () {
      final tabsBloc = _CapturingTabsBloc();
      final coordinator = _makeCoordinator(tabsBloc: tabsBloc);

      coordinator.openBook(
        _makeBook('ספר בדיקה'),
        7,
        '',
        markText: 'highlight',
        navigateToPositionIfReused: true,
      );

      final event = tabsBloc.capturedEvents.first as OpenOrFocusTab;
      expect(event.navigateToPositionIfReused, isTrue);
      expect((event.tab as TextBookTab).highlightText, 'highlight');
    });
  });

  group('BookOpenCoordinator — שחזור מיקום מהיסטוריה', () {
    // הבאג: פתיחת PDF מהספרייה מעבירה index=1 (העמוד הראשון, ברירת המחדל),
    // וקודם לכן התנאי `index != 0` דילג על שחזור ההיסטוריה ופתח תמיד בעמוד 1.
    test('PDF מהספרייה (index=1) משחזר את העמוד האחרון מההיסטוריה', () async {
      final book = _makePdfBook('ספר PDF');
      final history = await _makeLoadedHistory([
        Bookmark(ref: 'ספר PDF עמוד 50', book: book, index: 50),
      ]);
      final tabsBloc = _CapturingTabsBloc();
      final coordinator = _makeCoordinator(
        tabsBloc: tabsBloc,
        historyBloc: history,
      );

      // index=1 = הדיפולט שהספרייה מעבירה ל-PDF.
      coordinator.openBook(book, 1, '');

      final tab = (tabsBloc.capturedEvents.first as OpenOrFocusTab).tab;
      expect(tab, isA<PdfBookTab>());
      expect(
        (tab as PdfBookTab).pageNumber,
        50,
        reason: 'PDF מהספרייה צריך להיפתח בעמוד שנשמר בהיסטוריה',
      );

      await history.close();
    });

    test('PDF עם עמוד מפורש (index≠1) מתעלם מההיסטוריה', () async {
      final book = _makePdfBook('ספר PDF');
      final history = await _makeLoadedHistory([
        Bookmark(ref: 'ספר PDF עמוד 50', book: book, index: 50),
      ]);
      final tabsBloc = _CapturingTabsBloc();
      final coordinator = _makeCoordinator(
        tabsBloc: tabsBloc,
        historyBloc: history,
      );

      // קישור עומק/חיפוש לעמוד ספציפי — מיקום מפורש שיש לכבד.
      coordinator.openBook(book, 7, '');

      final tab = (tabsBloc.capturedEvents.first as OpenOrFocusTab).tab;
      expect(
        (tab as PdfBookTab).pageNumber,
        7,
        reason: 'עמוד מפורש צריך לגבור על ההיסטוריה',
      );

      await history.close();
    });

    test('PDF ללא היסטוריה (index=1) נפתח בעמוד 1', () {
      final book = _makePdfBook('ספר PDF');
      final tabsBloc = _CapturingTabsBloc();
      final coordinator = _makeCoordinator(tabsBloc: tabsBloc);

      coordinator.openBook(book, 1, '');

      final tab = (tabsBloc.capturedEvents.first as OpenOrFocusTab).tab;
      expect((tab as PdfBookTab).pageNumber, 1);
    });

    // רגרסיה: שני PDF עם אותה כותרת אך נתיב שונה הם ספרים נפרדים — אסור
    // שפתיחת אחד תקפוץ לעמוד שנשמר עבור השני.
    test('שני PDF עם אותה כותרת ונתיב שונה — אין שחזור צולב', () async {
      final bookA = PdfBook(title: 'אותה כותרת', path: 'c:/a/book.pdf');
      final bookB = PdfBook(title: 'אותה כותרת', path: 'c:/b/book.pdf');
      // בהיסטוריה נשמר רק העמוד של ספר A.
      final history = await _makeLoadedHistory([
        Bookmark(ref: 'אותה כותרת עמוד 50', book: bookA, index: 50),
      ]);
      final tabsBloc = _CapturingTabsBloc();
      final coordinator = _makeCoordinator(
        tabsBloc: tabsBloc,
        historyBloc: history,
      );

      // פתיחת ספר B (index=1, ברירת מחדל) — לא אמור לקבל את עמוד 50 של A.
      coordinator.openBook(bookB, 1, '');

      final tab = (tabsBloc.capturedEvents.first as OpenOrFocusTab).tab;
      expect(
        (tab as PdfBookTab).pageNumber,
        1,
        reason: 'אסור שספר B יקפוץ למיקום שנשמר עבור ספר A בעל אותה כותרת',
      );

      await history.close();
    });

    test('ספר טקסט (index=0) משחזר את האינדקס האחרון מההיסטוריה', () async {
      final book = _makeBook('ספר טקסט');
      final history = await _makeLoadedHistory([
        Bookmark(ref: 'ספר טקסט', book: book, index: 30),
      ]);
      final tabsBloc = _CapturingTabsBloc();
      final coordinator = _makeCoordinator(
        tabsBloc: tabsBloc,
        historyBloc: history,
      );

      coordinator.openBook(book, 0, '');

      final tab = (tabsBloc.capturedEvents.first as OpenOrFocusTab).tab;
      expect(
        (tab as TextBookTab).index,
        30,
        reason: 'התנהגות ספר הטקסט הקיימת לא משתנה',
      );

      await history.close();
    });
  });
}
