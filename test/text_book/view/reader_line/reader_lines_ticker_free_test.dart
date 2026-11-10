import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_settings_bloc.dart';

// כל טיקר נרשם ל-notifier המשותף של TickerMode, שהסרה ממנו היא O(n). טיקר
// לכל שורה הופך פירוק של אלפי שורות בפריים אחד לריבועי (issues #3381, #3383).

final _content = List.generate(400, (i) => 'שורה $i ${'מילה ' * 6}');

TextBookLoaded _state() => TextBookLoaded(
  book: TextBook(title: 'ספר בדיקה'),
  showLeftPane: false,
  content: _content,
  fontSize: 18,
  showSplitView: false,
  showPageShapeView: false,
  activeCommentators: const [],
  commentatorGroups: const [],
  availableCommentators: const [],
  links: const [],
  visibleLinks: const [],
  linksByLine: const {},
  tableOfContents: const [],
  removeNikud: false,
  visibleIndices: const [0],
  selectedIndex: 2,
  pinLeftPane: false,
  searchText: '',
);

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _TestPersonalNotesBloc(super.initialState) {
    on<PersonalNotesEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, Widget viewer) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final textBookBloc = _TestTextBookBloc(_state());
  final notesBloc = _TestPersonalNotesBloc(const PersonalNotesState.initial());
  final settingsBloc = StubSettingsBloc(SettingsState.initial());
  addTearDown(textBookBloc.close);
  addTearDown(notesBloc.close);
  addTearDown(settingsBloc.close);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('he', 'IL')],
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: textBookBloc),
          BlocProvider<PersonalNotesBloc>.value(value: notesBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
        ],
        child: Scaffold(body: viewer),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// State-ים עם טיקר שכל אחד מהם עוטף שורות בודדות ולא את הרשימה כולה.
int _perLineTickerStates(WidgetTester tester) {
  final lines = find.byType(SmartTextWidget).evaluate().toList();
  final coverage = <State, int>{};
  for (final line in lines) {
    line.visitAncestorElements((ancestor) {
      if (ancestor is StatefulElement && ancestor.state is TickerProvider) {
        coverage.update(ancestor.state, (n) => n + 1, ifAbsent: () => 1);
      }
      return true;
    });
  }
  return coverage.values.where((n) => n < lines.length / 2).length;
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('שורות התצוגה המשולבת אינן מחזיקות טיקר', (tester) async {
    final tab = TextBookTab(book: TextBook(title: 'ספר בדיקה'), index: 0);
    addTearDown(tab.dispose);
    await _pump(
      tester,
      CombinedView(
        data: _content,
        openBookCallback: (_) {},
        openLeftPaneTab: (_, {searchText}) {},
        textSize: 18,
        showCommentaryAsExpansionTiles: false,
        tab: tab,
      ),
    );

    expect(find.byType(SmartTextWidget).evaluate().length, greaterThan(20));
    expect(_perLineTickerStates(tester), 0);
  });

  testWidgets('שורות SimpleTextViewer אינן מחזיקות טיקר', (tester) async {
    await _pump(
      tester,
      SimpleTextViewer(
        content: _content,
        fontSize: 18,
        openBookCallback: (_) {},
        isMainText: true,
      ),
    );

    expect(find.byType(SmartTextWidget).evaluate().length, greaterThan(20));
    expect(_perLineTickerStates(tester), 0);
  });
}
