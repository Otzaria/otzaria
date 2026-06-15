import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/pdf_headings.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/pdf_book/view/pdf_commentators_tab_screen.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/reading_screen.dart';
import 'package:provider/provider.dart';
import '../helpers/memory_settings_cache.dart';

/// רגרסיה: כרטסיית מפרשים עצמאית בתצוגה מפוצלת (`CombinedTab`) הוצגה ריקה,
/// כי `_buildSingleTabContent` (נתיב ה-side-by-side) טיפל רק ב-Pdf/Text/Search
/// ולא ב-`CommentatorsTab`/`PdfCommentatorsTab` כפי ש-`_buildTabView` עושה.
class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, __) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _FakePersonalNotesBloc()
      : super(const PersonalNotesState(
          isLoading: false,
          bookId: '',
          locatedNotes: [],
          missingNotes: [],
          errorMessage: null,
          filteredLocatedNotes: [],
          filteredMissingNotes: [],
        )) {
    on<PersonalNotesEvent>((_, __) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _FakeTabsBloc(super.initial) {
    on<TabsEvent>((_, __) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PdfCommentatorsTab _commentaryTab(String title) {
  final sourceTab = PdfBookTab(
    book: PdfBook(title: title, path: '/tmp/$title.pdf'),
    pageNumber: 1,
  );
  sourceTab.pdfHeadings = PdfHeadings(
    bookTitle: title,
    headingsMap: {'פרק א': 1},
  );
  sourceTab.currentTitle.value = 'פרק א';
  sourceTab.currentTextLineNumber = 1;
  sourceTab.currentTextLineNumberEnd = 9;
  return PdfCommentatorsTab(sourceTab: sourceTab);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  testWidgets(
    'תצוגה מפוצלת מציגה כרטסיות מפרשים בשני הצדדים (לא ריק)',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final combined = CombinedTab(
        rightTab: _commentaryTab('ימין'),
        leftTab: _commentaryTab('שמאל'),
      );
      addTearDown(combined.dispose);

      final tabsBloc = _FakeTabsBloc(
        TabsState(tabs: [combined], currentTabIndex: 0),
      );
      addTearDown(tabsBloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<SettingsBloc>.value(value: _FakeSettingsBloc()),
              BlocProvider<PersonalNotesBloc>.value(
                value: _FakePersonalNotesBloc(),
              ),
              BlocProvider<TabsBloc>.value(value: tabsBloc),
              Provider<FocusRepository>.value(value: FocusRepository()),
            ],
            child: const ReadingScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(PdfCommentatorsTabScreen), findsNWidgets(2),
          reason: 'שני צדי התצוגה המפוצלת חייבים לרנדר כרטסיית מפרשים, '
              'לא SizedBox.shrink');
    },
  );
}
