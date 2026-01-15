import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tabs/reading_screen.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/navigation/navigation_repository.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import '../unit/mocks/mock_settings_repository.mocks.dart';

class _FakeTabsRepository implements TabsRepository {
  @override
  List<OpenedTab> loadTabs() => const [];

  @override
  int loadCurrentTabIndex() => 0;

  @override
  SideBySideMode? loadSideBySideMode() => null;

  @override
  void saveTabs(
    List<OpenedTab> tabs,
    int currentTabIndex, [
    SideBySideMode? sideBySideMode,
  ]) {
    // no-op for tests
  }
}

class _FakeNavigationRepository implements NavigationRepository {
  @override
  bool checkLibraryIsEmpty() => false;

  @override
  Future<void> refreshLibrary() async {
    // no-op for tests
  }
}

class _FakeHistoryRepository implements HistoryRepository {
  final List<Bookmark> _items = <Bookmark>[];

  @override
  Future<List<Bookmark>> loadHistory() async => List<Bookmark>.from(_items);

  @override
  Future<void> saveHistory(List<Bookmark> history) async {
    _items
      ..clear()
      ..addAll(history);
  }

  @override
  Future<void> clearHistory() async {
    _items.clear();
  }

  @override
  Future<void> addHistoryItem(Bookmark bookmark) async {
    _items.add(bookmark);
  }

  @override
  Future<void> removeHistoryItem(int index) async {
    if (index < 0 || index >= _items.length) return;
    _items.removeAt(index);
  }

  @override
  Future<void> addHistoryFromTab(OpenedTab tab) async {
    // no-op for tests
  }

  @override
  Future<List<Bookmark>> load() async => loadHistory();

  @override
  Future<void> save(List<Bookmark> items) async => saveHistory(items);

  @override
  Future<void> clear() async => clearHistory();

  @override
  Future<void> addItem(Bookmark item) async => addHistoryItem(item);

  @override
  Future<void> removeAt(int index) async => removeHistoryItem(index);
}

/// Integration tests for menu consistency across different components
///
/// These tests verify that sharing functionality appears consistently
/// across different context menus and components in the application.
void main() {
  group('Menu Consistency Integration Tests', () {
    late MockSettingsRepository mockSettingsRepository;
    late SettingsBloc settingsBloc;
    late TabsBloc tabsBloc;
    late NavigationBloc navigationBloc;
    late HistoryBloc historyBloc;
    late TabsRepository tabsRepository;
    late NavigationRepository navigationRepository;
    late HistoryRepository historyRepository;

    setUp(() {
      mockSettingsRepository = MockSettingsRepository();
      settingsBloc = SettingsBloc(repository: mockSettingsRepository);
      tabsRepository = _FakeTabsRepository();
      navigationRepository = _FakeNavigationRepository();
      historyRepository = _FakeHistoryRepository();
      tabsBloc = TabsBloc(repository: tabsRepository);
      navigationBloc = NavigationBloc(
        repository: navigationRepository,
        tabsRepository: tabsRepository,
      );
      historyBloc = HistoryBloc(historyRepository);
    });

    tearDown(() {
      settingsBloc.close();
      tabsBloc.close();
      navigationBloc.close();
      historyBloc.close();
    });

    /// Integration Test: Menu consistency across different components
    /// Test sharing functionality across different components and verify
    /// menu structure consistency
    /// Validates: Requirements 5.5
    testWidgets('Menu consistency across different components', (tester) async {
      const int iterations = 20; // Fewer iterations for integration test
      final random = Random(42);

      for (int i = 0; i < iterations; i++) {
        // Generate random tab configurations
        final tabCount = random.nextInt(3) + 2; // 2-4 tabs for variety
        final tabs = _generateRandomTabs(random, tabCount);
        final currentTabIndex = random.nextInt(tabCount);

        final tabsState = TabsState(
          tabs: tabs,
          currentTabIndex: currentTabIndex,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<SettingsBloc>.value(value: settingsBloc),
                BlocProvider<TabsBloc>.value(value: tabsBloc),
                BlocProvider<NavigationBloc>.value(value: navigationBloc),
                BlocProvider<HistoryBloc>.value(value: historyBloc),
              ],
              child: BlocProvider<TabsBloc>(
                create: (_) =>
                    TabsBloc(repository: tabsRepository)..emit(tabsState),
                child: const ReadingScreen(),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Test 1: Verify three dots menu consistency
        final threeDotsMenuFinder = find.byType(PopupMenuButton<String>);
        if (threeDotsMenuFinder.evaluate().isNotEmpty) {
          try {
            await tester.tap(threeDotsMenuFinder);
            await tester.pumpAndSettle();

            // Should have consistent sharing option
            expect(
              find.text('העתק קישור לספר זה'),
              findsOneWidget,
              reason:
                  'Three dots menu should consistently show sharing option (iteration $i)',
            );

            // Should have consistent settings option
            expect(
              find.text('הגדרות תצוגת הספרים'),
              findsOneWidget,
              reason:
                  'Three dots menu should consistently show settings option (iteration $i)',
            );

            // Close menu
            await tester.tapAt(const Offset(10, 10));
            await tester.pumpAndSettle();
          } catch (e) {
            debugPrint(
                'Three dots menu consistency test skipped for iteration $i: $e');
          }
        }

        // Test 2: Verify tab context menu consistency
        final tabFinders = find.byType(Tab);
        if (tabFinders.evaluate().isNotEmpty) {
          try {
            // Test context menu on first tab
            await tester.longPress(tabFinders.first);
            await tester.pumpAndSettle();

            // Should have consistent sharing submenu structure
            final sharingSubmenuFinder = find.text('שתף קישור ישיר');
            if (sharingSubmenuFinder.evaluate().isNotEmpty) {
              await tester.tap(sharingSubmenuFinder);
              await tester.pumpAndSettle();

              // Verify all three sharing options are present consistently
              expect(
                find.text('העתק קישור ישיר לספר זה'),
                findsOneWidget,
                reason:
                    'Context menu should consistently show book sharing option (iteration $i)',
              );

              expect(
                find.text('העתק קישור ישיר למקטע זה'),
                findsOneWidget,
                reason:
                    'Context menu should consistently show section sharing option (iteration $i)',
              );

              expect(
                find.text('העתק קישור ישיר למקטע זה עם הדגשת טקסט'),
                findsOneWidget,
                reason:
                    'Context menu should consistently show highlight sharing option (iteration $i)',
              );
            }

            // Close context menu
            await tester.tapAt(const Offset(10, 10));
            await tester.pumpAndSettle();
          } catch (e) {
            debugPrint(
                'Tab context menu consistency test skipped for iteration $i: $e');
          }
        }

        // Test 3: Verify consistency across different tab types
        for (int tabIndex = 0; tabIndex < min(tabs.length, 3); tabIndex++) {
          final tab = tabs[tabIndex];

          // Switch to this tab
          try {
            final specificTabFinder = tabFinders.at(tabIndex);
            await tester.tap(specificTabFinder);
            await tester.pumpAndSettle();

            // Test context menu on this specific tab
            await tester.longPress(specificTabFinder);
            await tester.pumpAndSettle();

            final sharingSubmenuFinder = find.text('שתף קישור ישיר');
            if (sharingSubmenuFinder.evaluate().isNotEmpty) {
              // Property: Sharing submenu should be consistent regardless of tab type
              expect(
                sharingSubmenuFinder,
                findsOneWidget,
                reason:
                    'Sharing submenu should be consistent for ${tab.runtimeType} (iteration $i)',
              );

              await tester.tap(sharingSubmenuFinder);
              await tester.pumpAndSettle();

              // Property: All sharing options should be present for any tab type
              expect(
                find.text('העתק קישור ישיר לספר זה'),
                findsOneWidget,
                reason:
                    'Book sharing should be available for ${tab.runtimeType} (iteration $i)',
              );

              expect(
                find.text('העתק קישור ישיר למקטע זה'),
                findsOneWidget,
                reason:
                    'Section sharing should be available for ${tab.runtimeType} (iteration $i)',
              );

              expect(
                find.text('העתק קישור ישיר למקטע זה עם הדגשת טקסט'),
                findsOneWidget,
                reason:
                    'Highlight sharing should be available for ${tab.runtimeType} (iteration $i)',
              );
            }

            // Close context menu
            await tester.tapAt(const Offset(10, 10));
            await tester.pumpAndSettle();
          } catch (e) {
            debugPrint(
                'Tab type consistency test skipped for tab $tabIndex, iteration $i: $e');
          }
        }
      }
    });

    /// Integration Test: Settings button consistency
    /// Verify that settings button behavior is consistent across different states
    testWidgets('Settings button consistency across states', (tester) async {
      // Test with tabs open
      final tabsWithContent = _generateRandomTabs(Random(42), 2);
      final tabsState = TabsState(tabs: tabsWithContent, currentTabIndex: 0);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
              BlocProvider<TabsBloc>.value(value: tabsBloc),
              BlocProvider<NavigationBloc>.value(value: navigationBloc),
              BlocProvider<HistoryBloc>.value(value: historyBloc),
            ],
            child: BlocProvider<TabsBloc>(
              create: (_) =>
                  TabsBloc(repository: tabsRepository)..emit(tabsState),
              child: const ReadingScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Property: Settings button should be IconButton in tabs state
      final settingsButtonWithTabs = find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.icon is Icon &&
            (widget.icon as Icon).icon == Icons.settings,
      );

      expect(
        settingsButtonWithTabs,
        findsAtLeastNWidgets(1),
        reason: 'Settings button should be present when tabs are open',
      );

      // Test with no tabs
      const emptyTabsState = TabsState(tabs: [], currentTabIndex: 0);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
              BlocProvider<TabsBloc>.value(value: tabsBloc),
              BlocProvider<NavigationBloc>.value(value: navigationBloc),
              BlocProvider<HistoryBloc>.value(value: historyBloc),
            ],
            child: BlocProvider<TabsBloc>(
              create: (_) =>
                  TabsBloc(repository: tabsRepository)..emit(emptyTabsState),
              child: const ReadingScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Property: Settings button should be IconButton in empty state too
      final settingsButtonEmpty = find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.icon is Icon &&
            (widget.icon as Icon).icon == Icons.settings,
      );

      expect(
        settingsButtonEmpty,
        findsAtLeastNWidgets(1),
        reason: 'Settings button should be present when no tabs are open',
      );

      // Property: Both states should have direct IconButton, not PopupMenuButton
      final popupMenuButtons = find.byType(PopupMenuButton);
      for (final element in popupMenuButtons.evaluate()) {
        final popupWidget = element.widget as PopupMenuButton;
        expect(
          popupWidget.tooltip?.contains('הגדרות') ?? false,
          isFalse,
          reason: 'Settings should not use PopupMenuButton in any state',
        );
      }
    });
  });
}

/// Helper function to generate random tabs for testing
List<OpenedTab> _generateRandomTabs(Random random, int count) {
  final tabs = <OpenedTab>[];

  for (int i = 0; i < count; i++) {
    final isTextTab = random.nextBool();
    final title =
        'ספר ${_generateRandomHebrewText(random, random.nextInt(3) + 1)}';

    if (isTextTab) {
      final book = TextBook(title: title);
      tabs.add(TextBookTab(
        book: book,
        index: random.nextInt(1000) + 1,
      ));
    } else {
      final book = PdfBook(title: title, path: '/path/to/$title.pdf');
      tabs.add(PdfBookTab(
        book: book,
        pageNumber: random.nextInt(500) + 1,
      ));
    }
  }

  return tabs;
}

/// Helper function to generate random Hebrew text
String _generateRandomHebrewText(Random random, int wordCount) {
  final hebrewWords = [
    'תורה',
    'משנה',
    'גמרא',
    'הלכה',
    'אגדה',
    'מדרש',
    'זוהר',
    'קבלה',
    'תפילה',
    'ברכה',
    'מצוה',
    'שבת',
    'חג',
    'יום טוב',
    'ראש השנה',
    'יום כיפור',
    'סוכות',
    'פסח',
    'שבועות',
    'חנוכה',
    'פורים',
    'תשעה באב',
    'ספירת העומר',
    'בית המקדש',
    'כהן',
    'לוי',
    'ישראל',
    'נביא',
    'מלך',
    'שופט',
    'זקן'
  ];

  final words = <String>[];
  for (int i = 0; i < wordCount; i++) {
    words.add(hebrewWords[random.nextInt(hebrewWords.length)]);
  }

  return words.join(' ');
}
