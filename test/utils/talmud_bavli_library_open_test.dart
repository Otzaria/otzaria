import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/resolving_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/utils/navigation/talmud_bavli_open_format.dart';

import '../helpers/memory_settings_cache.dart';

class _RecordingTabsBloc extends Fake implements TabsBloc {
  final added = <TabsEvent>[];

  @override
  TabsState get state => TabsState.initial();

  @override
  Stream<TabsState> get stream => const Stream.empty();

  @override
  void add(TabsEvent event) => added.add(event);
}

class _RecordingHistoryBloc extends Fake implements HistoryBloc {
  final added = <HistoryEvent>[];

  @override
  HistoryState get state => HistoryLoaded(const []);

  @override
  Stream<HistoryState> get stream => const Stream.empty();

  @override
  void add(HistoryEvent event) => added.add(event);
}

class _RecordingNavigationBloc extends Fake implements NavigationBloc {
  final added = <NavigationEvent>[];

  @override
  Stream<NavigationState> get stream => const Stream.empty();

  @override
  void add(NavigationEvent event) => added.add(event);
}

Category _category(String title, {Category? parent}) {
  final category = Category(
    title: title,
    description: '',
    shortDescription: '',
    order: 0,
    subCategories: [],
    books: [],
    parent: parent,
  );
  parent?.subCategories.add(category);
  return category;
}

/// ספרייה עם מסכת ברכות: מהדורת טקסט תחת סדר זרעים, ואופציונלית PDF נלווה.
({Library library, TextBook text}) _buildLibrary({bool withPdf = true}) {
  final bavliRoot = _category('תלמוד בבלי');
  final seder = _category('סדר זרעים', parent: bavliRoot);
  final text = TextBook(title: 'ברכות', category: seder, categoryId: 10);
  seder.books.add(text);
  if (withPdf) {
    bavliRoot.books.add(
      PdfBook(
        title: 'ברכות',
        path: r'C:\books\תלמוד בבלי\ברכות.pdf',
        category: bavliRoot,
      ),
    );
  }
  return (library: Library(categories: [bavliRoot]), text: text);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingTabsBloc tabsBloc;
  late _RecordingHistoryBloc historyBloc;
  late _RecordingNavigationBloc navigationBloc;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    tabsBloc = _RecordingTabsBloc();
    historyBloc = _RecordingHistoryBloc();
    navigationBloc = _RecordingNavigationBloc();
  });

  Future<bool> run(WidgetTester tester, Book book, int index) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>.value(value: tabsBloc),
          BlocProvider<HistoryBloc>.value(value: historyBloc),
          BlocProvider<NavigationBloc>.value(value: navigationBloc),
        ],
        child: Builder(
          builder: (ctx) {
            capturedContext = ctx;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return openLibraryBookPerTalmudBavliFormat(capturedContext, book, index);
  }

  group('openLibraryBookPerTalmudBavliFormat', () {
    testWidgets('הגדרת PDF: מסכת טקסט בלי מיקום נפתחת כ-PDF בדף 1', (
      tester,
    ) async {
      await Settings.setValue(
        SettingsRepository.keyTalmudBavliOpenFormat,
        'pdf',
      );
      final built = _buildLibrary();
      DataRepository.instance.library = Future.value(built.library);

      final handled = await run(tester, built.text, 0);

      expect(handled, isTrue);
      final event = tabsBloc.added.single as OpenOrFocusTab;
      final tab = event.tab as PdfBookTab;
      expect(tab.book.title, 'ברכות');
      expect(tab.pageNumber, 1);
      expect(
        navigationBloc.added.single,
        isA<NavigateToScreen>().having(
          (e) => e.screen,
          'screen',
          Screen.reading,
        ),
      );
    });

    testWidgets('הגדרת PDF עם מיקום מפורש: נפתח טאב-טעינה עם מיפוי עמוד', (
      tester,
    ) async {
      await Settings.setValue(
        SettingsRepository.keyTalmudBavliOpenFormat,
        'pdf',
      );
      final built = _buildLibrary();
      DataRepository.instance.library = Future.value(built.library);

      final handled = await run(tester, built.text, 7);

      expect(handled, isTrue);
      final event = tabsBloc.added.single as OpenOrFocusTab;
      final tab = event.tab as ResolvingTab;
      expect(
        tab.fallbackTab,
        isA<TextBookTab>().having((t) => t.book.title, 'title', 'ברכות'),
      );
    });

    testWidgets('הגדרת טקסט (ברירת מחדל): הפתיחה לא מטופלת — נשארת רגילה', (
      tester,
    ) async {
      final built = _buildLibrary();
      DataRepository.instance.library = Future.value(built.library);

      final handled = await run(tester, built.text, 0);

      expect(handled, isFalse);
      expect(tabsBloc.added, isEmpty);
      expect(navigationBloc.added, isEmpty);
    });

    testWidgets('הגדרת PDF אך אין מהדורת PDF בספרייה: fallback לפתיחה רגילה', (
      tester,
    ) async {
      await Settings.setValue(
        SettingsRepository.keyTalmudBavliOpenFormat,
        'pdf',
      );
      final built = _buildLibrary(withPdf: false);
      DataRepository.instance.library = Future.value(built.library);

      final handled = await run(tester, built.text, 0);

      expect(handled, isFalse);
      expect(tabsBloc.added, isEmpty);
    });

    testWidgets('ספר שאינו טקסט (PDF) לא מנותב — נפתח כרגיל', (tester) async {
      await Settings.setValue(
        SettingsRepository.keyTalmudBavliOpenFormat,
        'pdf',
      );
      final built = _buildLibrary();
      DataRepository.instance.library = Future.value(built.library);
      final pdf = PdfBook(
        title: 'ברכות',
        path: r'C:\books\תלמוד בבלי\ברכות.pdf',
      );

      final handled = await run(tester, pdf, 1);

      expect(handled, isFalse);
      expect(tabsBloc.added, isEmpty);
    });
  });
}
