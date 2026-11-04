import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/note_tile.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_sidebar.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';

import '../../test_helpers/memory_cache_provider.dart';

const _bookId = 'ספר בדיקה';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  PersonalNote note(int index, {bool missing = false}) => PersonalNote(
    id: '${missing ? 'missing' : 'note'}-$index',
    bookId: _bookId,
    lineNumber: missing ? null : index + 1,
    displayTitle: 'הערה ${index + 1}',
    lastKnownLineNumber: index + 1,
    status: missing ? PersonalNoteStatus.missing : PersonalNoteStatus.located,
    content: 'תוכן הערה $index',
    contentPlain: 'תוכן הערה $index',
    contentFormat: PersonalNoteContentFormat.plain,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  final located = List.generate(4, note);
  final missing = List.generate(2, (i) => note(i, missing: true));

  Future<List<NoteTile>> pumpTiles(WidgetTester tester) async {
    final notesBloc = _StubNotesBloc(located, missing);
    addTearDown(notesBloc.close);
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: BlocProvider<PersonalNotesBloc>.value(
              value: notesBloc,
              child: PersonalNotesSidebar(
                bookId: _bookId,
                onNavigateToLine: (_, {note}) {},
                visibleLineIndices: const [],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.widgetList<NoteTile>(find.byType(NoteTile)).toList();
  }

  /// ה-Material של כל כרטיס: הראשון בתוך כל NoteTile.
  List<Finder> cards(WidgetTester tester) => [
    for (var i = 0; i < find.byType(NoteTile).evaluate().length; i++)
      find
          .descendant(
            of: find.byType(NoteTile).at(i),
            matching: find.byType(Material),
          )
          .first,
  ];

  testWidgets('כל הכרטיסים מקבלים את כל הערות הספר לקישור', (tester) async {
    final tiles = await pumpTiles(tester);

    expect(tiles, hasLength(located.length + missing.length));
    for (final tile in tiles) {
      expect(tile.linkableNotes, [...located, ...missing]);
    }
  });

  testWidgets('כל ההערות כרטיסים על AppSurfaces.tintedRow (#3086, review-r5)', (
    tester,
  ) async {
    final tiles = await pumpTiles(tester);
    final cs = Theme.of(
      tester.element(find.byType(NoteTile).first),
    ).colorScheme;

    for (final tile in tiles) {
      expect(
        tile.backgroundColor,
        AppSurfaces.tintedRow(cs),
        reason: tile.note.id,
      );
    }
    // הרקע נצבע בפועל על כרטיס מעוגל, לא רק עובר כפרמטר.
    for (final card in cards(tester)) {
      final material = tester.widget<Material>(card);
      expect(material.color, AppSurfaces.tintedRow(cs));
      expect(material.borderRadius, AppTokens.borderRadiusAll);
    }
  });

  testWidgets('בין כרטיסי ההערות רווח spaceSM ואין קווים (review-r5)', (
    tester,
  ) async {
    await pumpTiles(tester);

    expect(
      find.descendant(
        of: find.byType(NoteTile),
        matching: find.byType(Divider),
      ),
      findsNothing,
    );
    final rects = [for (final card in cards(tester)) tester.getRect(card)]
      ..sort((a, b) => a.top.compareTo(b.top));
    expect(rects, hasLength(located.length + missing.length));
    // אף מפריד של החלונית (למשל מתחת לסרגל) אינו בין הכרטיסים.
    final dividers = find.byType(Divider);
    for (var i = 0; i < dividers.evaluate().length; i++) {
      expect(
        tester.getRect(dividers.at(i)).bottom,
        lessThanOrEqualTo(rects.first.top),
      );
    }
    // הממוקמות רצופות; לפני חסרות המיקום באה הכותרת שלהן.
    for (var i = 1; i < located.length; i++) {
      expect(rects[i].top - rects[i - 1].bottom, AppTokens.spaceSM);
    }
    for (var i = located.length + 1; i < rects.length; i++) {
      expect(rects[i].top - rects[i - 1].bottom, AppTokens.spaceSM);
    }
    final heading = tester.getRect(find.text('הערות חסרות מיקום'));
    expect(heading.top, greaterThan(rects[located.length - 1].bottom));
    expect(heading.bottom, lessThan(rects[located.length].top));
  });

  testWidgets('רשימת הקישור נבנית פעם אחת לבנייה ולא לכל כרטיס', (
    tester,
  ) async {
    final tiles = await pumpTiles(tester);

    final first = tiles.first.linkableNotes;
    for (final tile in tiles) {
      expect(tile.linkableNotes, same(first));
    }
  });
}

class _StubNotesBloc extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _StubNotesBloc(this.located, this.missing)
    : super(const PersonalNotesState.initial()) {
    on<PersonalNotesEvent>((event, emit) {
      if (event is LoadPersonalNotes) {
        emit(
          state.copyWith(
            bookId: event.bookId,
            locatedNotes: located,
            missingNotes: missing,
            showOnlyVisible: false,
            isLoading: false,
          ),
        );
      }
    });
  }

  final List<PersonalNote> located;
  final List<PersonalNote> missing;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
