import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';

import '../../test_helpers/memory_cache_provider.dart';

/// סינון "הצג רק הערות לטקסט הנראה" — ההערות המסוננות (`filteredLocatedNotes`)
/// הן מה שהחלונית מציגה. `visibleLineIndices` הם אינדקסים 0-based של השורות
/// הגלויות, ו-`note.lineNumber` הוא 1-based.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  const bookId = 'ספר בדיקה';

  PersonalNote note({
    required String id,
    int? lineNumber,
    String content = 'תוכן',
  }) => PersonalNote(
    id: id,
    bookId: bookId,
    lineNumber: lineNumber,
    lastKnownLineNumber: lineNumber,
    status: lineNumber == null
        ? PersonalNoteStatus.missing
        : PersonalNoteStatus.located,
    content: content,
    contentPlain: content,
    contentFormat: PersonalNoteContentFormat.plain,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  final located = [
    note(id: 'a', lineNumber: 1, content: 'הערה על שורה ראשונה'),
    note(id: 'b', lineNumber: 5, content: 'הערה על שורה חמישית'),
    note(id: 'c', lineNumber: 50, content: 'הערה רחוקה'),
  ];
  final missing = [note(id: 'd', content: 'הערה בלי מיקום')];

  List<String> ids(List<PersonalNote> notes) => notes.map((n) => n.id).toList();

  PersonalNotesBloc buildBloc() =>
      PersonalNotesBloc(repository: _FakeRepository([...located, ...missing]));

  group('סינון לפי טקסט נראה', () {
    test('showOnlyVisible דלוק כברירת מחדל', () {
      expect(const PersonalNotesState.initial().showOnlyVisible, isTrue);
    });

    blocTest<PersonalNotesBloc, PersonalNotesState>(
      'שורות גלויות מסננות את ההערות לשורות הללו בלבד',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const LoadPersonalNotes(bookId));
        await bloc.stream.firstWhere((s) => !s.isLoading);
        bloc.add(const UpdateVisibleLines([4, 5, 6]));
      },
      skip: 2,
      expect: () => [
        isA<PersonalNotesState>()
            .having((s) => ids(s.filteredLocatedNotes), 'מסוננות', ['b'])
            .having((s) => s.locatedNotes.length, 'סה"כ ממוקמות', 3),
      ],
    );

    blocTest<PersonalNotesBloc, PersonalNotesState>(
      'הערות חסרות מיקום מוסתרות כשהסינון דלוק ומוצגות כשהוא כבוי',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const LoadPersonalNotes(bookId));
        await bloc.stream.firstWhere((s) => !s.isLoading);
        bloc.add(const UpdateVisibleLines([4]));
        bloc.add(const ToggleShowOnlyVisible());
      },
      skip: 2,
      expect: () => [
        isA<PersonalNotesState>().having(
          (s) => s.filteredMissingNotes,
          'חסרות מיקום מוסתרות',
          isEmpty,
        ),
        isA<PersonalNotesState>()
            .having((s) => ids(s.filteredMissingNotes), 'חסרות מיקום', ['d'])
            .having((s) => ids(s.filteredLocatedNotes), 'כל הממוקמות', [
              'a',
              'b',
              'c',
            ]),
      ],
    );

    blocTest<PersonalNotesBloc, PersonalNotesState>(
      'חיפוש מצטבר על הסינון לפי טקסט נראה ולא מבטל אותו',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const LoadPersonalNotes(bookId));
        await bloc.stream.firstWhere((s) => !s.isLoading);
        bloc.add(const UpdateVisibleLines([0, 1, 2, 3, 4]));
        bloc.add(const UpdateSearchQuery('חמישית'));
      },
      skip: 3,
      expect: () => [
        isA<PersonalNotesState>().having(
          (s) => ids(s.filteredLocatedNotes),
          'רק מה שגלוי וגם תואם',
          ['b'],
        ),
      ],
    );

    blocTest<PersonalNotesBloc, PersonalNotesState>(
      'רשימת שורות גלויות ריקה אינה מסננת (fallback מכוון — עדיף הצגה מלאה '
      'מעל חלונית ריקה)',
      build: buildBloc,
      act: (bloc) => bloc.add(const LoadPersonalNotes(bookId)),
      skip: 1,
      expect: () => [
        isA<PersonalNotesState>().having(
          (s) => ids(s.filteredLocatedNotes),
          'הכל מוצג',
          ['a', 'b', 'c'],
        ),
      ],
    );
  });

  group('טעינה מחדש שומרת על הסינון', () {
    blocTest<PersonalNotesBloc, PersonalNotesState>(
      'רענון אותו ספר שומר את השורות הגלויות (אחרת הסינון היה נופל '
      'וכל הספר היה מוצג)',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const LoadPersonalNotes(bookId));
        await bloc.stream.firstWhere((s) => !s.isLoading);
        bloc.add(const UpdateVisibleLines([4]));
        bloc.add(const LoadPersonalNotes(bookId));
        await bloc.stream.firstWhere((s) => !s.isLoading);
      },
      verify: (bloc) {
        expect(bloc.state.visibleLineIndices, [4]);
        expect(ids(bloc.state.filteredLocatedNotes), ['b']);
      },
    );

    blocTest<PersonalNotesBloc, PersonalNotesState>(
      'רענון אותו ספר שומר את מילת החיפוש',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const LoadPersonalNotes(bookId));
        await bloc.stream.firstWhere((s) => !s.isLoading);
        bloc.add(const UpdateSearchQuery('רחוקה'));
        bloc.add(const LoadPersonalNotes(bookId));
        await bloc.stream.firstWhere((s) => !s.isLoading);
      },
      verify: (bloc) {
        expect(bloc.state.searchQuery, 'רחוקה');
        expect(ids(bloc.state.filteredLocatedNotes), ['c']);
      },
    );

    blocTest<PersonalNotesBloc, PersonalNotesState>(
      'מעבר לספר אחר מאפס שורות גלויות וחיפוש',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const LoadPersonalNotes(bookId));
        await bloc.stream.firstWhere((s) => !s.isLoading);
        bloc.add(const UpdateVisibleLines([4]));
        bloc.add(const UpdateSearchQuery('רחוקה'));
        bloc.add(const LoadPersonalNotes('ספר אחר'));
        await bloc.stream.firstWhere((s) => !s.isLoading);
      },
      verify: (bloc) {
        expect(bloc.state.visibleLineIndices, isEmpty);
        expect(bloc.state.searchQuery, isEmpty);
      },
    );

    blocTest<PersonalNotesBloc, PersonalNotesState>(
      'אותו שם ספר בקטגוריה אחרת נחשב ספר אחר ומאפס',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const LoadPersonalNotes(bookId, categoryId: 1));
        await bloc.stream.firstWhere((s) => !s.isLoading);
        bloc.add(const UpdateVisibleLines([4]));
        bloc.add(const LoadPersonalNotes(bookId, categoryId: 2));
        await bloc.stream.firstWhere((s) => !s.isLoading);
      },
      verify: (bloc) => expect(bloc.state.visibleLineIndices, isEmpty),
    );
  });

  group('עדכוני הערות שומרים על הסינון', () {
    blocTest<PersonalNotesBloc, PersonalNotesState>(
      'מחיקת הערה לא מבטלת את הסינון',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const LoadPersonalNotes(bookId));
        await bloc.stream.firstWhere((s) => !s.isLoading);
        bloc.add(const UpdateVisibleLines([4]));
        bloc.add(const DeletePersonalNote(bookId: bookId, noteId: 'a'));
        await bloc.stream.firstWhere((s) => !s.isLoading);
      },
      verify: (bloc) => expect(ids(bloc.state.filteredLocatedNotes), ['b']),
    );
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

  @override
  Future<List<PersonalNote>> deleteNote({
    required String bookId,
    required String noteId,
    int? categoryId,
  }) async => notes.where((n) => n.id != noteId).toList();
}
