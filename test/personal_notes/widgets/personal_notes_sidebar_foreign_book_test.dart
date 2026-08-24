// רגרסיה ל-issue #870: rebuild מההורה עוקף את buildWhen, ולכן חלונית
// שנבנתה כשה-state עוד מחזיק ספר אחר הציגה את ההערות של הספר הזר.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_sidebar.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  PersonalNote note(String bookId) => PersonalNote(
    id: 'note-$bookId',
    bookId: bookId,
    lineNumber: 3,
    displayTitle: 'הערה של $bookId',
    lastKnownLineNumber: 3,
    status: PersonalNoteStatus.located,
    content: 'תוכן',
    contentPlain: 'תוכן',
    contentFormat: PersonalNoteContentFormat.plain,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  Widget buildSidebar({
    required PersonalNotesBloc bloc,
    required String bookId,
  }) => MaterialApp(
    home: Scaffold(
      body: BlocProvider<PersonalNotesBloc>.value(
        value: bloc,
        child: PersonalNotesSidebar(
          bookId: bookId,
          onNavigateToLine: (_) {},
        ),
      ),
    ),
  );

  testWidgets('state של ספר אחר מציג טעינה ולא את ההערות הזרות', (
    tester,
  ) async {
    final bloc = _SeededNotesBloc(
      const PersonalNotesState.initial().copyWith(
        bookId: 'ספר א',
        locatedNotes: [note('ספר א')],
      ),
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(buildSidebar(bloc: bloc, bookId: 'ספר ב'));
    await tester.pump();

    expect(find.text('הערה של ספר א'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('state של אותו ספר מציג את ההערות כרגיל', (tester) async {
    final bloc = _SeededNotesBloc(
      const PersonalNotesState.initial().copyWith(
        bookId: 'ספר א',
        locatedNotes: [note('ספר א')],
      ),
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(buildSidebar(bloc: bloc, bookId: 'ספר א'));
    await tester.pump();

    expect(find.text('הערה של ספר א'), findsOneWidget);
  });
}

/// bloc זרוע שמתעלם מאירועים — משמר את ה-state כמו בחלון שבין הבנייה
/// לסיום הטעינה של הספר הנכון.
class _SeededNotesBloc extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _SeededNotesBloc(super.initialState) {
    on<PersonalNotesEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
