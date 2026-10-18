import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/view/book_preview_panel.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

import '../../helpers/memory_settings_cache.dart';

class _SettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _SettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NotesBloc extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _NotesBloc() : super(const PersonalNotesState.initial()) {
    on<PersonalNotesEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  const query = 'בשעת השינה';
  final half = List.filled(30000, 'מילה').join(' ');
  final line = '<b>פתיחה</b> $half $query $half';
  final book = TextBook(title: 'ספר בדיקה');

  Widget app(int target) => MultiBlocProvider(
    providers: [
      BlocProvider<SettingsBloc>(create: (_) => _SettingsBloc()),
      BlocProvider<PersonalNotesBloc>(create: (_) => _NotesBloc()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: BookPreviewPanel(
          book: book,
          initialTextIndex: target,
          searchText: query,
        ),
      ),
    ),
  );

  Future<void> loadPreview(WidgetTester tester, List<String> content) async {
    await tester.pumpWidget(app(0));
    await tester.pump();

    final previewBloc = BlocProvider.of<TextBookBloc>(
      tester.element(
        find
            .descendant(
              of: find.byWidgetPredicate(
                (w) => w is BlocProvider<TextBookBloc>,
              ),
              matching: find.byWidgetPredicate((_) => true),
            )
            .last,
      ),
    );
    // הטעינה האמיתית נכשלת בלי ספרייה; ממתינים לה לפני הזרקת מצב טעון.
    for (var i = 0; i < 100; i++) {
      final state = previewBloc.state;
      if (state is! TextBookInitial && state is! TextBookLoading) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    // ignore: invalid_use_of_visible_for_testing_member
    previewBloc.emit(
      TextBookLoaded(
        book: book,
        showLeftPane: false,
        content: content,
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
        selectedIndex: null,
        pinLeftPane: false,
        searchText: query,
      ),
    );
    await tester.pump();
  }

  List<String> shownLines(WidgetTester tester) =>
      tester.widget<CombinedView>(find.byType(CombinedView)).data;

  testWidgets(
    'תצוגה מקדימה של שורת ענק מציגה חלון סביב ההתאמה (issue #1941)',
    (tester) async {
      expect(line.length, greaterThan(290000));
      await loadPreview(tester, [line, line, 'שורה קצרה']);

      var shown = shownLines(tester);
      expect(shown[0].length, lessThan(20000));
      expect(computeHighlightRanges(shown[0], query), isNotEmpty);
      expect(shown[2], 'שורה קצרה');

      // מעבר לתוצאה בשורת ענק אחרת באותו ספר.
      await tester.pumpWidget(app(1));
      await tester.pump();
      shown = shownLines(tester);
      expect(shown[1].length, lessThan(20000));
      expect(computeHighlightRanges(shown[1], query), isNotEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    },
  );
}
