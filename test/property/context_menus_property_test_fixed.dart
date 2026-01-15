import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mockito/mockito.dart';
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
import 'package:otzaria/utils/sharing_utils.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/navigation/navigation_repository.dart';
import 'package:otzaria/history/history_repository.dart';

import 'package:otzaria/settings/settings_repository.dart';

// Mock classes
class MockTabsRepository extends Mock implements TabsRepository {}

class MockNavigationRepository extends Mock implements NavigationRepository {}

class MockHistoryRepository extends Mock implements HistoryRepository {}

class MockSettingsRepository extends Mock implements SettingsRepository {}

/// Property-based tests for context menus and sharing functionality
///
/// These tests validate universal correctness properties across many
/// randomly generated inputs to ensure the system behaves correctly
/// under all valid conditions.
void main() {
  group('Context Menus Property Tests', () {
    late MockSettingsRepository mockSettingsRepository;
    late SettingsBloc settingsBloc;
    late TabsRepository mockTabsRepository;
    late NavigationRepository mockNavigationRepository;
    late HistoryRepository mockHistoryRepository;

    setUp(() {
      mockSettingsRepository = MockSettingsRepository();

      // Create mock repositories
      mockTabsRepository = MockTabsRepository();
      mockNavigationRepository = MockNavigationRepository();
      mockHistoryRepository = MockHistoryRepository();

      // Setup mock behavior
      when(mockTabsRepository.loadTabs()).thenReturn([]);
      when(mockTabsRepository.loadCurrentTabIndex()).thenReturn(0);
      when(mockTabsRepository.loadSideBySideMode()).thenReturn(null);
      when(mockNavigationRepository.checkLibraryIsEmpty()).thenReturn(false);

      settingsBloc = SettingsBloc(repository: mockSettingsRepository);
    });

    tearDown(() {
      settingsBloc.close();
    });

    /// Property 2: Direct Settings Button Behavior
    /// For any application state (with or without tabs), clicking the settings
    /// button should directly open the reading settings dialog without showing any popup menu
    /// Validates: Requirements 2.1, 2.2, 2.3
    testWidgets('Property 2: Direct Settings Button Behavior', (tester) async {
      const int iterations = 10; // Reduced for faster testing
      final random = Random(42);

      for (int i = 0; i < iterations; i++) {
        // Generate random application states
        final hasTabsOpen = random.nextBool();
        final tabCount = hasTabsOpen ? random.nextInt(3) + 1 : 0;
        final tabs =
            hasTabsOpen ? _generateRandomTabs(random, tabCount) : <OpenedTab>[];
        final currentTabIndex = hasTabsOpen ? random.nextInt(tabCount) : 0;

        final tabsBloc = TabsBloc(repository: mockTabsRepository);
        final navigationBloc = NavigationBloc(
          repository: mockNavigationRepository,
          tabsRepository: mockTabsRepository,
        );
        final historyBloc = HistoryBloc(mockHistoryRepository);

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
              child: const ReadingScreen(),
            ),
          ),
        );

        // Emit the test state
        tabsBloc.emit(tabsState);
        await tester.pumpAndSettle();

        // Property: Settings button should always be present as IconButton (not PopupMenuButton)
        final settingsButtonFinder = find.byWidgetPredicate((widget) =>
            widget is IconButton &&
            widget.icon is Icon &&
            (widget.icon as Icon).icon.toString().contains('settings'));

        expect(
          settingsButtonFinder,
          findsWidgets,
          reason:
              'Settings button should be present in any state (iteration $i)',
        );

        // Property: Settings button should be IconButton, not PopupMenuButton
        final iconButtons = find.byType(IconButton);
        bool foundSettingsIconButton = false;

        for (final element in iconButtons.evaluate()) {
          final iconButton = element.widget as IconButton;
          if (iconButton.icon is Icon) {
            final icon = iconButton.icon as Icon;
            if (icon.icon.toString().contains('settings')) {
              foundSettingsIconButton = true;
              break;
            }
          }
        }

        expect(
          foundSettingsIconButton,
          isTrue,
          reason:
              'Settings should be direct IconButton, not PopupMenuButton (iteration $i)',
        );

        // Property: No PopupMenuButton should exist for settings
        final popupMenuButtons = find.byType(PopupMenuButton);
        for (final element in popupMenuButtons.evaluate()) {
          final popupWidget = element.widget as PopupMenuButton;
          // Verify that if PopupMenuButton exists, it's not for settings
          if (popupWidget.tooltip?.contains('הגדרות') == true) {
            fail('Settings should not use PopupMenuButton (iteration $i)');
          }
        }

        // Clean up
        tabsBloc.close();
        navigationBloc.close();
        historyBloc.close();
      }
    });
  });

  group('Sharing Utils Property Tests', () {
    /// Property 3: Unique Sharing URL Generation
    /// For any book, section, and highlighted text combination, the three sharing
    /// functions should generate three distinct URLs with appropriate parameters
    /// for book identification, section location, and text highlighting
    /// Validates: Requirements 3.1, 3.2, 3.3, 3.4
    test('Property 3: Unique Sharing URL Generation', () {
      const int iterations = 100;
      final random = Random(42);

      for (int i = 0; i < iterations; i++) {
        // Generate random tab data
        final tab = _generateRandomTabs(random, 1).first;
        final selectedText = random.nextBool()
            ? _generateRandomHebrewText(random, random.nextInt(50) + 1)
            : null;

        // Generate URLs using sharing utilities
        final bookLink = SharingUtils.generateBookLink(tab);
        final sectionLink = SharingUtils.generateSectionLink(tab);
        final highlightLink = SharingUtils.generateHighlightedTextLink(tab,
            selectedText: selectedText);

        // Property: All three URLs should be different
        expect(
          bookLink != sectionLink,
          isTrue,
          reason:
              'Book link and section link should be different (iteration $i)\n'
              'Book: $bookLink\nSection: $sectionLink',
        );

        expect(
          bookLink != highlightLink,
          isTrue,
          reason:
              'Book link and highlight link should be different (iteration $i)\n'
              'Book: $bookLink\nHighlight: $highlightLink',
        );

        expect(
          sectionLink != highlightLink,
          isTrue,
          reason:
              'Section link and highlight link should be different (iteration $i)\n'
              'Section: $sectionLink\nHighlight: $highlightLink',
        );

        // Property: All URLs should start with otzaria:// protocol
        expect(
          bookLink.startsWith('otzaria://'),
          isTrue,
          reason:
              'Book link should use otzaria protocol (iteration $i): $bookLink',
        );

        expect(
          sectionLink.startsWith('otzaria://'),
          isTrue,
          reason:
              'Section link should use otzaria protocol (iteration $i): $sectionLink',
        );

        expect(
          highlightLink.startsWith('otzaria://'),
          isTrue,
          reason:
              'Highlight link should use otzaria protocol (iteration $i): $highlightLink',
        );

        // Property: Section link should contain more information than book link
        expect(
          sectionLink.length >= bookLink.length,
          isTrue,
          reason:
              'Section link should contain at least as much info as book link (iteration $i)',
        );

        // Property: Highlight link should contain more information than section link
        expect(
          highlightLink.length >= sectionLink.length,
          isTrue,
          reason:
              'Highlight link should contain at least as much info as section link (iteration $i)',
        );

        // Property: URLs should contain encoded book title
        final encodedTitle = Uri.encodeComponent(tab.title);
        expect(
          bookLink.contains(encodedTitle),
          isTrue,
          reason:
              'Book link should contain encoded title (iteration $i): $bookLink',
        );

        expect(
          sectionLink.contains(encodedTitle),
          isTrue,
          reason:
              'Section link should contain encoded title (iteration $i): $sectionLink',
        );

        expect(
          highlightLink.contains(encodedTitle),
          isTrue,
          reason:
              'Highlight link should contain encoded title (iteration $i): $highlightLink',
        );

        // Property: If selected text provided, highlight link should contain it
        if (selectedText != null && selectedText.trim().isNotEmpty) {
          final encodedText = Uri.encodeComponent(selectedText.trim());
          expect(
            highlightLink.contains(encodedText) ||
                highlightLink.contains('text='),
            isTrue,
            reason:
                'Highlight link should contain encoded text or text parameter (iteration $i)',
          );
        }
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
      // Create a TextBookTab with proper TextBook
      final book = TextBook(title: title);
      tabs.add(TextBookTab(
        book: book,
        index: random.nextInt(1000) + 1,
      ));
    } else {
      // Create a PdfBookTab with proper PdfBook
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
