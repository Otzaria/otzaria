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
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
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
  @override
  Future<List<Bookmark>> load() async => [];

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
}) =>
    BookOpenCoordinator(
      tabsBloc: tabsBloc,
      historyBloc: HistoryBloc(_FakeHistoryRepository()),
      navigationBloc: navigationBloc ?? _FakeNavigationBloc(),
    );

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
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
          reason: 'pinpointHighlight=$pinpointText: expected OpenOrFocusTab event',
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
          reason: 'pinpointHighlight=$pinpointText: pinpointHighlight should match',
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
          ((tabsBloc.capturedEvents.first as OpenOrFocusTab).tab as TextBookTab);
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
          ((tabsBloc.capturedEvents.first as OpenOrFocusTab).tab as TextBookTab);
      expect(tab.pinpointHighlight, 'pinpointText');
    });
  });
}
