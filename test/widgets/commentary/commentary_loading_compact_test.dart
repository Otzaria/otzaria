import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_panel.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as text_utils;
import 'package:otzaria/widgets/commentary/commentary_search_results_list.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../test_helpers/stub_settings_bloc.dart';

class _FakePersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _FakePersonalNotesBloc()
    : super(
        const PersonalNotesState(
          isLoading: false,
          bookId: '',
          locatedNotes: [],
          missingNotes: [],
          errorMessage: null,
          filteredLocatedNotes: [],
          filteredMissingNotes: [],
        ),
      ) {
    on<PersonalNotesEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Settings.init(cacheProvider: MemorySettingsCache());
    await text_utils.splitByEra(const []);
  });

  Widget host(Widget child) => MaterialApp(
    home: MultiBlocProvider(
      providers: [
        BlocProvider<SettingsBloc>.value(value: StubSettingsBloc()),
        BlocProvider<PersonalNotesBloc>.value(value: _FakePersonalNotesBloc()),
      ],
      child: Scaffold(body: child),
    ),
  );

  void expectCompact(WidgetTester tester, String message) {
    final loading = find.byType(LoadingIndicator);
    expect(loading, findsOneWidget);
    expect(tester.widget<LoadingIndicator>(loading).message, message);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(message), findsOneWidget);
    // הגודל של ההודעה אינו תלוי בגודל גופן המפרשים.
    final context = tester.element(find.text(message));
    expect(
      tester.widget<Text>(find.text(message)).style?.fontSize,
      Theme.of(context).textTheme.bodySmall?.fontSize,
    );
  }

  testWidgets('LoadingIndicator.compact: ספינר 24 עובי 2 והודעה מתחתיו', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const LoadingIndicator.compact(message: 'טוען...')),
    );

    expect(
      tester.getSize(find.byType(CircularProgressIndicator)),
      const Size(24, 24),
    );
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .strokeWidth,
      2,
    );
    expect(
      tester.getTopLeft(find.text('טוען...')).dy,
      greaterThan(
        tester.getBottomLeft(find.byType(CircularProgressIndicator)).dy,
      ),
    );
  });

  testWidgets('חיפוש במפרשים: "טוען תוצאות..." עם ספינר', (tester) async {
    await tester.pumpWidget(
      host(
        CommentarySearchResultsList(
          query: 'שלום',
          snippets: const [],
          currentIdx: 0,
          onSnippetTap: (_) {},
        ),
      ),
    );

    expectCompact(tester, 'טוען תוצאות...');
  });

  for (final (index, message) in [
    (0, 'טוען מפרשים...'),
    (1, 'טוען קישורים...'),
  ]) {
    testWidgets('חלונית מפרשים של PDF, לשונית $index: "$message" עם ספינר', (
      tester,
    ) async {
      final tab = PdfBookTab(
        book: PdfBook(title: 'מכות', path: '/books/מכות.pdf'),
        pageNumber: 1,
      );
      tab.currentTextLineNumber = 10;
      addTearDown(tab.dispose);

      await tester.pumpWidget(
        host(
          PdfCommentaryPanel(
            tab: tab,
            linksCount: 0,
            linksLoading: true,
            openBookCallback: (_) {},
            fontSize: 16.0,
            initialTabIndex: index,
          ),
        ),
      );
      await tester.pump();

      expectCompact(tester, message);
    });
  }
}
