import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
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

/// HistoryBloc מינימלי שלא דורש Hive
class _FakeHistoryBloc extends Bloc<HistoryEvent, HistoryState> {
  _FakeHistoryBloc() : super(HistoryInitial());

  @override
  void add(HistoryEvent event) {
    // מתעלמים מ-events בבדיקות
  }
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
      historyBloc: _FakeHistoryBloc(),
      navigationBloc: navigationBloc ?? _FakeNavigationBloc(),
    );

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  group('BookOpenCoordinator — mark params', () {
    // Feature: deep-link-mark, Property 6: markText becomes searchText
    // For any non-empty markText, coordinator creates tab with searchText=markText
    // Validates: Requirements 4.2, 5.1
    test('Property 6: markText becomes searchText', () async {
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

      for (final markText in testTexts) {
        final tabsBloc = _CapturingTabsBloc();
        final coordinator = _makeCoordinator(tabsBloc: tabsBloc);

        await coordinator.openBook(
          _makeBook('ספר בדיקה'),
          0,
          '',
          markText: markText,
        );

        expect(
          tabsBloc.capturedEvents,
          isNotEmpty,
          reason: 'markText=$markText: expected OpenOrFocusTab event',
        );

        final event = tabsBloc.capturedEvents.first;
        expect(
          event,
          isA<OpenOrFocusTab>(),
          reason: 'markText=$markText: expected OpenOrFocusTab',
        );

        final tab = (event as OpenOrFocusTab).tab;
        expect(
          tab,
          isA<TextBookTab>(),
          reason: 'markText=$markText: expected TextBookTab',
        );

        expect(
          (tab as TextBookTab).highlightText,
          markText,
          reason: 'markText=$markText: highlightText should equal markText',
        );
      }
    });

    test('ללא mark — searchQuery עובר כ-searchText (regression)', () async {
      final tabsBloc = _CapturingTabsBloc();
      final coordinator = _makeCoordinator(tabsBloc: tabsBloc);

      await coordinator.openBook(
        _makeBook('ספר בדיקה'),
        0,
        'חיפוש רגיל',
      );

      final tab =
          ((tabsBloc.capturedEvents.first as OpenOrFocusTab).tab as TextBookTab);
      expect(tab.searchText, 'חיפוש רגיל');
    });

    test('markText מנצח על searchQuery', () async {
      final tabsBloc = _CapturingTabsBloc();
      final coordinator = _makeCoordinator(tabsBloc: tabsBloc);

      await coordinator.openBook(
        _makeBook('ספר בדיקה'),
        0,
        'searchQuery',
        markText: 'markText',
      );

      final tab =
          ((tabsBloc.capturedEvents.first as OpenOrFocusTab).tab as TextBookTab);
      // markText הופך ל-highlightText, permanentHighlightLine מוגדר
      expect(tab.highlightText, 'markText');
      expect(tab.permanentHighlightLine, 0);
    });
  });
}
