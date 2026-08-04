import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_sidebar.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../test_helpers/memory_cache_provider.dart';

/// חלונית ההערות מקבלת את השורות הגלויות מ-TextBookBloc. ה-BlocListener מגיב
/// רק לשינוי הבא של ה-state, ולכן בלי סנכרון בהרכבה הסינון "הצג רק הערות
/// לטקסט הנראה" לא היה מסנן כלום עד הגלילה הראשונה — כלומר הציג את כל הספר.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Widget buildSidebar({
    required _RecordingNotesBloc notesBloc,
    TextBookBloc? textBookBloc,
    List<int>? visibleLineIndices,
    bool isPdf = false,
  }) {
    final sidebar = PersonalNotesSidebar(
      bookId: 'ספר בדיקה',
      onNavigateToLine: (_) {},
      isPdf: isPdf,
      visibleLineIndices: visibleLineIndices,
    );

    return MaterialApp(
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<PersonalNotesBloc>.value(value: notesBloc),
            if (textBookBloc != null)
              BlocProvider<TextBookBloc>.value(value: textBookBloc),
          ],
          child: sidebar,
        ),
      ),
    );
  }

  testWidgets('בהרכבה נשלחות השורות הגלויות הנוכחיות של TextBookBloc', (
    tester,
  ) async {
    final notesBloc = _RecordingNotesBloc();
    addTearDown(notesBloc.close);
    final textBookBloc = _TestTextBookBloc(
      _loadedState(visibleIndices: const [10, 11, 12]),
    );
    addTearDown(textBookBloc.close);

    await tester.pumpWidget(
      buildSidebar(notesBloc: notesBloc, textBookBloc: textBookBloc),
    );
    await tester.pump();

    expect(
      notesBloc.visibleLineUpdates,
      contains(const [10, 11, 12]),
      reason: 'בלי זה הסינון פועל על רשימה ריקה ומציג את כל הספר',
    );
  });

  testWidgets('השורות הגלויות נשלחות אחרי טעינת ההערות (שמאפסת אותן)', (
    tester,
  ) async {
    final notesBloc = _RecordingNotesBloc();
    addTearDown(notesBloc.close);
    final textBookBloc = _TestTextBookBloc(
      _loadedState(visibleIndices: const [3]),
    );
    addTearDown(textBookBloc.close);

    await tester.pumpWidget(
      buildSidebar(notesBloc: notesBloc, textBookBloc: textBookBloc),
    );
    await tester.pump();

    final loadIndex = notesBloc.received.indexWhere(
      (e) => e is LoadPersonalNotes,
    );
    final visibleIndex = notesBloc.received.indexWhere(
      (e) => e is UpdateVisibleLines,
    );
    expect(loadIndex, isNonNegative);
    expect(visibleIndex, greaterThan(loadIndex));
  });

  testWidgets('גלילה (state חדש של TextBookBloc) מעדכנת את השורות הגלויות', (
    tester,
  ) async {
    final notesBloc = _RecordingNotesBloc();
    addTearDown(notesBloc.close);
    final textBookBloc = _TestTextBookBloc(
      _loadedState(visibleIndices: const [0]),
    );
    addTearDown(textBookBloc.close);

    await tester.pumpWidget(
      buildSidebar(notesBloc: notesBloc, textBookBloc: textBookBloc),
    );
    await tester.pump();

    textBookBloc.emitState(_loadedState(visibleIndices: const [40, 41]));
    await tester.pump();

    expect(notesBloc.visibleLineUpdates.last, const [40, 41]);
  });

  testWidgets('גלילה בטאב של ספר אחר אינה דורסת את השורות הגלויות', (
    tester,
  ) async {
    final notesBloc = _RecordingNotesBloc();
    addTearDown(notesBloc.close);
    final otherBookBloc = _TestTextBookBloc(
      _loadedState(visibleIndices: const [0]),
    );
    addTearDown(otherBookBloc.close);

    // ה-BLoC הגלובלי טעון על "ספר בדיקה", והחלונית כאן שייכת לספר אחר
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<PersonalNotesBloc>.value(value: notesBloc),
              BlocProvider<TextBookBloc>.value(value: otherBookBloc),
            ],
            child: PersonalNotesSidebar(
              bookId: 'ספר ברקע',
              onNavigateToLine: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    notesBloc.add(const LoadPersonalNotes('ספר בדיקה'));
    await tester.pump();
    notesBloc.received.clear();

    otherBookBloc.emitState(_loadedState(visibleIndices: const [90, 91]));
    await tester.pump();

    expect(notesBloc.visibleLineUpdates, isEmpty);
  });

  testWidgets('מסלול PDF: השורות מגיעות מהפרמטר ולא מ-TextBookBloc', (
    tester,
  ) async {
    final notesBloc = _RecordingNotesBloc();
    addTearDown(notesBloc.close);

    await tester.pumpWidget(
      buildSidebar(
        notesBloc: notesBloc,
        visibleLineIndices: const [7, 8],
        isPdf: true,
      ),
    );
    await tester.pump();

    expect(notesBloc.visibleLineUpdates, contains(const [7, 8]));
  });

  testWidgets('בלי TextBookBloc ובלי פרמטר — נטען בלי שגיאה ובלי עדכון שורות', (
    tester,
  ) async {
    final notesBloc = _RecordingNotesBloc();
    addTearDown(notesBloc.close);

    await tester.pumpWidget(buildSidebar(notesBloc: notesBloc));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(notesBloc.visibleLineUpdates, isEmpty);
  });

  group('קצה-לקצה עם BLoC אמיתי', () {
    PersonalNote note(int line) => PersonalNote(
      id: 'note-$line',
      bookId: 'ספר בדיקה',
      lineNumber: line,
      displayTitle: 'הערה בשורה $line',
      lastKnownLineNumber: line,
      status: PersonalNoteStatus.located,
      content: 'תוכן $line',
      contentPlain: 'תוכן $line',
      contentFormat: PersonalNoteContentFormat.plain,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    testWidgets('בפתיחת החלונית מוצגות רק ההערות שבטקסט הנראה', (tester) async {
      final notesBloc = PersonalNotesBloc(
        repository: _FakeRepository([note(1), note(5), note(50)]),
      );
      addTearDown(notesBloc.close);
      final textBookBloc = _TestTextBookBloc(
        _loadedState(visibleIndices: const [4]),
      );
      addTearDown(textBookBloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider<PersonalNotesBloc>.value(value: notesBloc),
                BlocProvider<TextBookBloc>.value(value: textBookBloc),
              ],
              child: PersonalNotesSidebar(
                bookId: 'ספר בדיקה',
                onNavigateToLine: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('הערה בשורה 5'), findsOneWidget);
      expect(find.text('הערה בשורה 1'), findsNothing);
      expect(find.text('הערה בשורה 50'), findsNothing);
      expect(find.text('1/3'), findsOneWidget);

      // כיבוי הסינון מציג את כל ההערות
      await tester.tap(find.text('הצג רק הערות לטקסט הנראה'));
      await tester.pumpAndSettle();

      expect(find.text('3/3'), findsOneWidget);
      expect(find.text('הערה בשורה 50'), findsOneWidget);
    });

    testWidgets('רענון החלונית אינו מבטל את הסינון', (tester) async {
      final notesBloc = PersonalNotesBloc(
        repository: _FakeRepository([note(1), note(5), note(50)]),
      );
      addTearDown(notesBloc.close);
      final textBookBloc = _TestTextBookBloc(
        _loadedState(visibleIndices: const [4]),
      );
      addTearDown(textBookBloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider<PersonalNotesBloc>.value(value: notesBloc),
                BlocProvider<TextBookBloc>.value(value: textBookBloc),
              ],
              child: PersonalNotesSidebar(
                bookId: 'ספר בדיקה',
                onNavigateToLine: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('רענן'));
      await tester.pumpAndSettle();

      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('הערה בשורה 50'), findsNothing);
    });
  });
}

class _FakeRepository extends PersonalNotesRepository {
  _FakeRepository(this.notes);

  final List<PersonalNote> notes;

  @override
  Future<List<PersonalNote>> loadNotes(
    String bookId, {
    int? categoryId,
  }) async => notes;
}

TextBookLoaded _loadedState({required List<int> visibleIndices}) =>
    TextBookLoaded(
      book: TextBook(title: 'ספר בדיקה'),
      showLeftPane: false,
      content: const ['שורה א', 'שורה ב'],
      fontSize: 18,
      showSplitView: true,
      showPageShapeView: false,
      activeCommentators: const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const <Link>[],
      visibleLinks: const <Link>[],
      linksByLine: const {},
      tableOfContents: const [],
      removeNikud: false,
      visibleIndices: visibleIndices,
      selectedIndex: null,
      pinLeftPane: false,
      searchText: '',
      scrollController: ItemScrollController(),
      positionsListener: ItemPositionsListener.create(),
    );

class _RecordingNotesBloc extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _RecordingNotesBloc() : super(const PersonalNotesState.initial()) {
    on<PersonalNotesEvent>((event, emit) {
      received.add(event);
      if (event is LoadPersonalNotes) {
        emit(state.copyWith(bookId: event.bookId));
      }
    });
  }

  final List<PersonalNotesEvent> received = [];

  List<List<int>> get visibleLineUpdates => received
      .whereType<UpdateVisibleLines>()
      .map((e) => e.visibleLineIndices)
      .toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  void emitState(TextBookState state) => emit(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
