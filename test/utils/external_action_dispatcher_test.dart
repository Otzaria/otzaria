import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/core/external_uri_router.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/navigation_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/utils/navigation/external_action_dispatcher.dart';

import '../helpers/memory_settings_cache.dart';

// ─── Fakes (זהה ל-book_open_coordinator_mark_test.dart) ──────────────────────

class _FakeNavigationRepository implements NavigationRepository {
  @override
  Future<bool> checkLibraryIsEmpty() async => false;
  @override
  Future<void> refreshLibrary() async {}
}

class _FakeTabsRepository implements TabsRepository {
  @override
  List<OpenedTab> loadTabs({bool newRuntime = false}) => [];
  @override
  Future<void> flushPendingWrites() async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _CapturingTabsBloc extends TabsBloc {
  final List<TabsEvent> capturedEvents = [];
  _CapturingTabsBloc() : super(repository: _FakeTabsRepository());

  @override
  void add(TabsEvent event) {
    capturedEvents.add(event);
  }
}

class _FakeHistoryRepository extends HistoryRepository {
  _FakeHistoryRepository([this.entries = const []]);
  final List<Bookmark> entries;
  @override
  Future<List<Bookmark>> load() async => entries;
  @override
  Future<List<Bookmark>> mutate(
    List<Bookmark> Function(List<Bookmark> current) apply,
  ) async => apply(entries);
}

class _FakeNavigationBloc extends NavigationBloc {
  _FakeNavigationBloc()
    : super(
        repository: _FakeNavigationRepository(),
        tabsRepository: _FakeTabsRepository(),
      );

  @override
  void add(NavigationEvent event) {}
}

BookOpenCoordinator _makeCoordinator(_CapturingTabsBloc tabsBloc) =>
    BookOpenCoordinator(
      tabsBloc: tabsBloc,
      historyBloc: HistoryBloc(_FakeHistoryRepository()),
      navigationBloc: _FakeNavigationBloc(),
    );

Future<BookOpenCoordinator> _coordinatorWithLastRead(
  _CapturingTabsBloc tabsBloc,
  Bookmark lastRead,
) async {
  final historyBloc = HistoryBloc(_FakeHistoryRepository([lastRead]));
  addTearDown(historyBloc.close);
  await historyBloc.stream.firstWhere((s) => s.history.isNotEmpty);
  return BookOpenCoordinator(
    tabsBloc: tabsBloc,
    historyBloc: historyBloc,
    navigationBloc: _FakeNavigationBloc(),
  );
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  // הגנה על באג הרגרסיה שתוקן: deep-link "חשוף" (otzaria://open/book/<id>)
  // לא אמור להזיז טאב פתוח למיקום שונה. הטסטים האלה בודקים את החיבור בין
  // OpenBookAction.hasExplicitPosition לבין הדגל ב-OpenOrFocusTab — בדיוק
  // הנקודה שאיבדה כיסוי מאז שהדגל הוצא ל-getter.
  group('dispatchOpenBookAction', () {
    test('URI חשוף → navigateToPositionIfReused=false', () {
      final action =
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/book/1'))
              as OpenBookAction;
      final tabsBloc = _CapturingTabsBloc();

      dispatchOpenBookAction(
        action: action,
        book: TextBook(title: 'ספר בדיקה'),
        coordinator: _makeCoordinator(tabsBloc),
      );

      final event = tabsBloc.capturedEvents.first as OpenOrFocusTab;
      expect(
        event.navigateToPositionIfReused,
        isFalse,
        reason: 'URI חשוף לא אמור להזיז טאב פתוח',
      );
    });

    test('URI עם ?index= → navigateToPositionIfReused=true', () {
      final action =
          ExternalUriRouter.parseUri(
                Uri.parse('otzaria://open/book/1?index=42'),
              )
              as OpenBookAction;
      final tabsBloc = _CapturingTabsBloc();

      dispatchOpenBookAction(
        action: action,
        book: TextBook(title: 'ספר בדיקה'),
        coordinator: _makeCoordinator(tabsBloc),
      );

      final event = tabsBloc.capturedEvents.first as OpenOrFocusTab;
      expect(event.navigateToPositionIfReused, isTrue);
      expect((event.tab as TextBookTab).index, 42);
    });

    test('URI עם ?index=0 נפתח בשורה 0 ולא במיקום מההיסטוריה', () async {
      final book = TextBook(title: 'ספר בדיקה', id: 7);
      final tabsBloc = _CapturingTabsBloc();
      final coordinator = await _coordinatorWithLastRead(
        tabsBloc,
        Bookmark(ref: 'ספר בדיקה', book: book, index: 120),
      );
      final action =
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/book/7?index=0'))
              as OpenBookAction;

      dispatchOpenBookAction(
        action: action,
        book: book,
        coordinator: coordinator,
      );

      final event = tabsBloc.capturedEvents.first as OpenOrFocusTab;
      expect((event.tab as TextBookTab).index, 0);
    });

    test('URI עם ?mark → navigateToPositionIfReused=true', () {
      final action =
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/book/1?mark'))
              as OpenBookAction;
      final tabsBloc = _CapturingTabsBloc();

      dispatchOpenBookAction(
        action: action,
        book: TextBook(title: 'ספר בדיקה'),
        coordinator: _makeCoordinator(tabsBloc),
      );

      final event = tabsBloc.capturedEvents.first as OpenOrFocusTab;
      expect(event.navigateToPositionIfReused, isTrue);
    });

    test('URI עם ?m= → navigateToPositionIfReused=true ו-markText מועבר', () {
      final action =
          ExternalUriRouter.parseUri(
                Uri.parse('otzaria://open/book/1?m=%D7%91%D7%99%D7%AA'),
              )
              as OpenBookAction;
      final tabsBloc = _CapturingTabsBloc();

      dispatchOpenBookAction(
        action: action,
        book: TextBook(title: 'ספר בדיקה'),
        coordinator: _makeCoordinator(tabsBloc),
      );

      final event = tabsBloc.capturedEvents.first as OpenOrFocusTab;
      expect(event.navigateToPositionIfReused, isTrue);
      expect((event.tab as TextBookTab).highlightText, 'בית');
    });

    test(
      'URI עם ?q= בלבד → navigateToPositionIfReused=false (q אינו מיקום)',
      () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse('otzaria://open/book/1?q=%D7%AA%D7%95%D7%A8%D7%94'),
                )
                as OpenBookAction;
        final tabsBloc = _CapturingTabsBloc();

        dispatchOpenBookAction(
          action: action,
          book: TextBook(title: 'ספר בדיקה'),
          coordinator: _makeCoordinator(tabsBloc),
        );

        final event = tabsBloc.capturedEvents.first as OpenOrFocusTab;
        expect(
          event.navigateToPositionIfReused,
          isFalse,
          reason: 'חיפוש (q) אינו מיקום מפורש — אסור להזיז טאב פתוח',
        );
        expect((event.tab as TextBookTab).searchText, 'תורה');
      },
    );
  });

  group('dispatchOpenPdfBookAction', () {
    test('URI חשוף → navigateToPositionIfReused=false', () {
      final action =
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/pdf/1'))
              as OpenPdfBookAction;
      final tabsBloc = _CapturingTabsBloc();

      dispatchOpenPdfBookAction(
        action: action,
        book: TextBook(title: 'ספר בדיקה'),
        coordinator: _makeCoordinator(tabsBloc),
      );

      final event = tabsBloc.capturedEvents.first as OpenOrFocusTab;
      expect(
        event.navigateToPositionIfReused,
        isFalse,
        reason: 'PDF חשוף לא אמור להזיז טאב פתוח לעמוד 1',
      );
    });

    test('URI עם ?index= → navigateToPositionIfReused=true', () {
      final action =
          ExternalUriRouter.parseUri(
                Uri.parse('otzaria://open/pdf/1?index=5'),
              )
              as OpenPdfBookAction;
      final tabsBloc = _CapturingTabsBloc();

      dispatchOpenPdfBookAction(
        action: action,
        book: TextBook(title: 'ספר בדיקה'),
        coordinator: _makeCoordinator(tabsBloc),
      );

      final event = tabsBloc.capturedEvents.first as OpenOrFocusTab;
      expect(event.navigateToPositionIfReused, isTrue);
    });

    test('URI עם ?index=1 נפתח בעמוד 1 ולא בעמוד מההיסטוריה', () async {
      final book = PdfBook(title: 'ספר PDF', path: '/x/a.pdf', id: 9);
      final tabsBloc = _CapturingTabsBloc();
      final coordinator = await _coordinatorWithLastRead(
        tabsBloc,
        Bookmark(ref: 'ספר PDF', book: book, index: 77),
      );
      final action =
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/pdf/9?index=1'))
              as OpenPdfBookAction;

      dispatchOpenPdfBookAction(
        action: action,
        book: book,
        coordinator: coordinator,
      );

      final event = tabsBloc.capturedEvents.first as OpenOrFocusTab;
      expect((event.tab as PdfBookTab).pageNumber, 1);
    });
  });
}
