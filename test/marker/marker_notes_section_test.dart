import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/repository/marker_repository.dart';
import 'package:otzaria/marker/services/marker_book_cache.dart';
import 'package:otzaria/marker/services/marker_note_requests.dart';
import 'package:otzaria/marker/services/marker_settings.dart';
import 'package:otzaria/marker/storage/marker_database.dart';
import 'package:otzaria/marker/view/reader/marker_notes_section.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/widgets/commentary_notes_section.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';

import 'marker_test_helpers.dart';

class _FakePersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _FakePersonalNotesBloc(String search)
    : super(
        PersonalNotesState(
          isLoading: false,
          bookId: '',
          locatedNotes: const [],
          missingNotes: const [],
          errorMessage: null,
          filteredLocatedNotes: const [],
          filteredMissingNotes: const [],
          searchQuery: search,
        ),
      ) {
    on<PersonalNotesEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _line = 'בראשית ברא אלהים את השמים ואת הארץ';

void main() {
  late Directory hiveDir;
  late MarkerDatabase db;
  late MarkerBookCache previous;
  late MarkerRepository repository;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('marker_notes_');
    Hive.init(hiveDir.path);
    await Hive.openBox<dynamic>(HiveCache.keyName);
    await Settings.init(cacheProvider: HiveCache());
    MarkerSettings.instance.reload();
    final store = openTestMarkerStore();
    db = store.db;
    repository = store.repository;
    previous = MarkerBookCache.instance;
    MarkerBookCache.instance = MarkerBookCache(
      repository: store.repository,
      changes: store.changes,
    );
    await store.repository.importHighlights([
      MarkerHighlight(
        id: 'p3',
        bookTitle: 'ספר',
        bookUid: null,
        segments: [segmentFor(3, _line, 'אלהים')],
        pdf: true,
        text: 'אלהים',
        colorId: 'yellow',
        colorHex: '#F1E784',
        note: const MarkerNote(content: 'הערה בעמוד', plain: 'הערה בעמוד'),
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
      MarkerHighlight(
        id: 'p5',
        bookTitle: 'ספר',
        bookUid: null,
        segments: [segmentFor(5, _line, 'הארץ')],
        pdf: true,
        text: 'הארץ',
        colorId: 'green',
        colorHex: '#A5D6A7',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    ]);
    await MarkerBookCache.instance.ensureLoaded('ספר', null, pdf: true);
  });

  tearDown(() async {
    MarkerNoteRequests.reset();
    MarkerBookCache.instance.dispose();
    MarkerBookCache.instance = previous;
    db.close();
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  Future<void> pump(
    WidgetTester tester, {
    String search = '',
    required void Function(int) onNavigate,
    double width = 400,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<PersonalNotesBloc>.value(
                value: _FakePersonalNotesBloc(search),
              ),
              BlocProvider<SettingsBloc>.value(value: _FakeSettingsBloc()),
            ],
            child: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topRight,
                child: SizedBox(
                  width: width,
                  child: MarkerNotesSection(
                    book: PdfBook(title: 'ספר', path: 'C:/books/ספר.pdf'),
                    pdf: true,
                    onNavigate: onNavigate,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('a PDF lists only marks with notes and opens their page', (
    tester,
  ) async {
    int? page;
    await pump(tester, onNavigate: (value) => page = value);
    await tester.pumpAndSettle();
    expect(find.text('הערות על סימונים'), findsOneWidget);
    expect(find.text('הערה בעמוד', findRichText: true), findsOneWidget);
    expect(find.text('הארץ'), findsNothing);
    await tester.tap(find.text('אלהים'));
    expect(page, 3);
  });

  testWidgets('the notes search filters the marks too', (tester) async {
    await pump(tester, search: 'אחר', onNavigate: (_) {});
    await tester.pumpAndSettle();
    expect(find.text('הערות על סימונים'), findsNothing);
  });

  testWidgets('hiding the marks in all books hides their notes too', (
    tester,
  ) async {
    await pump(tester, onNavigate: (_) {});
    await tester.pumpAndSettle();
    expect(find.text('הערות על סימונים'), findsOneWidget);
    await tester.runAsync(
      () => MarkerSettings.instance.setShowHighlights(false),
    );
    await tester.pump();
    expect(find.text('הערות על סימונים'), findsNothing);
    await tester.runAsync(
      () => MarkerSettings.instance.setShowHighlights(true),
    );
    await tester.pump();
    expect(find.text('הערות על סימונים'), findsOneWidget);
  });

  testWidgets('notes on a commentary are rows under its name', (tester) async {
    final commentary = TextBook(title: 'רש"י על ספר');
    await tester.runAsync(() async {
      await repository.importHighlights([
        highlightFor(
          'c1',
          [segmentFor(2, _line, 'השמים')],
          book: commentary.title,
          uid: null,
          text: 'השמים',
          note: const MarkerNote(content: 'הערה במפרש', plain: 'הערה במפרש'),
        ),
        highlightFor(
          'c2',
          [segmentFor(4, _line, 'הארץ')],
          book: commentary.title,
          uid: null,
          text: 'הארץ',
        ),
      ]);
      await MarkerBookCache.instance.ensureLoaded(commentary.title, null);
    });
    (TextBook, int)? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarkerCommentaryNoteTiles(
              commentaries: [commentary],
              onNavigate: (book, section) => opened = (book, section),
              builder: (context, tiles) => CommentaryNotesSection(
                bookIds: [commentary.title],
                loader: (_, {categoryId}) async => const [],
                revision: ValueNotifier(0),
                onOpenNote: (_, _) {},
                extraTiles: tiles,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('הערות על המפרשים המוצגים'), findsOneWidget);
    expect(find.text(commentary.title), findsOneWidget);
    expect(find.text('הערה במפרש'), findsOneWidget);
    // סימון בלי הערה אינו ברשימה.
    expect(find.text('הארץ', findRichText: true), findsNothing);
    await tester.tap(find.text('הערה במפרש'));
    expect(opened, (commentary, 2));
    await tester.runAsync(
      () => MarkerSettings.instance.setShowHighlights(false),
    );
    await tester.pumpAndSettle();
    expect(find.text('הערות על המפרשים המוצגים'), findsNothing);
  });

  testWidgets('a request opens the editor in the card, also for a new note', (
    tester,
  ) async {
    await pump(tester, onNavigate: (_) {});
    await tester.pumpAndSettle();
    // לסימון p5 אין הערה, ולכן הוא אינו ברשימה עד שמבקשים להוסיף לו.
    expect(find.text('הארץ'), findsNothing);
    MarkerNoteRequests.open('p5');
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(MarkerNoteRequests.isShown('p5'), isTrue);
    expect(find.text('הערה חדשה לסימון'), findsOneWidget);
    // טיימרי העורך (פוקוס, שמירת טיוטה).
    await tester.pump(const Duration(seconds: 1));

    // החלונית נבנית מחדש (למשל כשהיא נפתחת): הכרטיס החדש לוקח את העורך.
    await tester.pumpWidget(const SizedBox());
    expect(MarkerNoteRequests.isShown('p5'), isFalse);
    await pump(tester, onNavigate: (_) {});
    await tester.pump();
    await tester.pump();
    expect(find.text('הערה חדשה לסימון'), findsOneWidget);
    // העורך נלקח שוב לפני שהיה נסגר כעזוב.
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('הערה חדשה לסימון'), findsOneWidget);

    MarkerNoteRequests.close('p5');
    await tester.pump();
    expect(find.text('הערה חדשה לסימון'), findsNothing);
    expect(find.text('הארץ'), findsNothing);
  });

  Widget tabs({required bool firstActive}) => MaterialApp(
    home: Scaffold(
      body: MultiBlocProvider(
        providers: [
          BlocProvider<PersonalNotesBloc>.value(
            value: _FakePersonalNotesBloc(''),
          ),
          BlocProvider<SettingsBloc>.value(value: _FakeSettingsBloc()),
        ],
        // אותו ספר בשתי כרטיסיות; רק אחת מהן פעילה.
        child: Column(
          children: [
            for (final first in [true, false])
              Expanded(
                key: ValueKey(first),
                child: TickerMode(
                  enabled: first == firstActive,
                  child: SingleChildScrollView(
                    child: MarkerNotesSection(
                      book: PdfBook(title: 'ספר', path: 'C:/books/ספר.pdf'),
                      pdf: true,
                      onNavigate: (_) {},
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  testWidgets('only the active tab shows the editor, and it moves with it', (
    tester,
  ) async {
    await tester.pumpWidget(tabs(firstActive: true));
    MarkerNoteRequests.open('p5');
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(MarkerNoteRequests.isShown('p5'), isTrue);
    expect(find.text('הערה חדשה לסימון'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));

    // הכרטיסייה השנייה נעשית פעילה: העורך עובר אליה.
    await tester.pumpWidget(tabs(firstActive: false));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(MarkerNoteRequests.isShown('p5'), isTrue);
    expect(find.text('הערה חדשה לסימון'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('an editor that no card shows is closed', (tester) async {
    await pump(tester, onNavigate: (_) {});
    MarkerNoteRequests.open('p5');
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // החלונית נסגרה.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(MarkerNoteRequests.editing.value, isEmpty);
  });

  testWidgets('a long note is shown short, with a button to show it all', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 300,
              child: CollapsibleMarkerNote(
                child: Column(
                  children: [
                    for (var i = 0; i < 12; i++) Text('שורה $i'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('הצגת ההערה כולה'), findsOneWidget);
    expect(
      tester.getSize(find.byType(CollapsibleMarkerNote)).height,
      lessThan(CollapsibleMarkerNote.collapsedHeight + 60),
    );
    await tester.tap(find.text('הצגת ההערה כולה'));
    await tester.pumpAndSettle();
    expect(find.text('הצגה מקוצרת'), findsOneWidget);
    expect(find.text('שורה 11'), findsOneWidget);
  });

  testWidgets('a short note has no expand button', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CollapsibleMarkerNote(child: Text('הערה קצרה')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('הצגת ההערה כולה'), findsNothing);
  });

  testWidgets('a narrow pane folds the card actions into one menu', (
    tester,
  ) async {
    await pump(tester, onNavigate: (_) {}, width: 250);
    await tester.pumpAndSettle();
    expect(find.byTooltip('פעולות נוספות'), findsOneWidget);
    expect(find.byTooltip('שינוי הצבע'), findsNothing);
    await pump(tester, onNavigate: (_) {}, width: 400);
    await tester.pumpAndSettle();
    expect(find.byTooltip('שינוי הצבע'), findsOneWidget);
    expect(find.byTooltip('שינוי המיקום'), findsOneWidget);
    expect(find.byTooltip('מחיקה'), findsOneWidget);
  });
}
