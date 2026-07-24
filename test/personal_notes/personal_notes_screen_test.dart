import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/view/personal_notes_screen.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import '../test_helpers/memory_cache_provider.dart';

class MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class FakePersonalNotesRepository extends PersonalNotesRepository {
  FakePersonalNotesRepository({
    required this.books,
    required this.notesByBookId,
  });

  final List<BookNotesInfo> books;
  final Map<String, List<PersonalNote>> notesByBookId;

  @override
  Future<List<BookNotesInfo>> listBooksWithNotes() async => books;

  @override
  Future<List<PersonalNote>> loadNotes(
    String bookId, {
    int? categoryId,
  }) async {
    return notesByBookId[bookId] ?? const [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('טוען הערות כבר בכניסה הראשונה למסך', (tester) async {
    final note = PersonalNote(
      id: 'note-1',
      bookId: 'ספר בדיקה',
      lineNumber: 12,
      displayTitle: 'כותרת הערה',
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.located,
      content: 'תוכן הערה ראשונית',
      contentPlain: 'תוכן הערה ראשונית',
      contentFormat: PersonalNoteContentFormat.plain,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 2),
    );
    final repository = FakePersonalNotesRepository(
      books: [
        BookNotesInfo(
          bookId: 'ספר בדיקה',
          noteCount: 1,
          lastUpdated: DateTime(2025, 1, 2),
        ),
      ],
      notesByBookId: {
        'ספר בדיקה': [note],
      },
    );
    final personalNotesBloc = PersonalNotesBloc(repository: repository);
    final settingsBloc = SettingsBloc(repository: SettingsRepository());
    final libraryBloc = MockLibraryBloc();
    final libraryState = LibraryState(
      library: Library(categories: []),
      isLoading: false,
      currentCategory: null,
    );

    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: libraryState,
    );

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<LibraryBloc>.value(value: libraryBloc),
          BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(
            body: PersonalNotesManagerScreen(repository: repository),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('ספר בדיקה'), findsOneWidget);
    expect(find.text('כותרת הערה'), findsOneWidget);
    expect(find.text('תוכן הערה ראשונית'), findsOneWidget);
  });

  group('noteWithinDateRange - סינון לפי טווח תאריכים', () {
    PersonalNote noteUpdatedAt(DateTime updatedAt) => PersonalNote(
      id: 'n',
      bookId: 'ספר',
      lineNumber: 1,
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.located,
      content: 'תוכן',
      contentPlain: 'תוכן',
      contentFormat: PersonalNoteContentFormat.plain,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: updatedAt,
    );

    test('טווח null כולל כל הערה', () {
      expect(
        noteWithinDateRange(noteUpdatedAt(DateTime(2020, 5, 5)), null),
        isTrue,
      );
    });

    test('הערה בתוך הטווח נכללת', () {
      final range = DateTimeRange(
        start: DateTime(2025, 3, 1),
        end: DateTime(2025, 3, 31),
      );
      expect(
        noteWithinDateRange(noteUpdatedAt(DateTime(2025, 3, 15)), range),
        isTrue,
      );
    });

    test('הערה לפני תחילת הטווח לא נכללת', () {
      final range = DateTimeRange(
        start: DateTime(2025, 3, 1),
        end: DateTime(2025, 3, 31),
      );
      expect(
        noteWithinDateRange(noteUpdatedAt(DateTime(2025, 2, 28)), range),
        isFalse,
      );
    });

    test('הערה אחרי סוף הטווח לא נכללת', () {
      final range = DateTimeRange(
        start: DateTime(2025, 3, 1),
        end: DateTime(2025, 3, 31),
      );
      expect(
        noteWithinDateRange(noteUpdatedAt(DateTime(2025, 4, 1)), range),
        isFalse,
      );
    });

    test('הגבולות נכללים (כולל קצוות), בהתעלם מהשעה', () {
      final range = DateTimeRange(
        start: DateTime(2025, 3, 1),
        end: DateTime(2025, 3, 31),
      );
      // קצה תחתון, אפילו עם שעה מאוחרת באותו יום
      expect(
        noteWithinDateRange(noteUpdatedAt(DateTime(2025, 3, 1, 23, 59)), range),
        isTrue,
      );
      // קצה עליון, אפילו עם שעה מאוחרת באותו יום
      expect(
        noteWithinDateRange(
          noteUpdatedAt(DateTime(2025, 3, 31, 23, 59)),
          range,
        ),
        isTrue,
      );
    });
  });
}
