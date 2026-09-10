import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';
import 'package:otzaria/personal_notes/widgets/note_tile.dart';
import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('NoteTile פותח אוטומטית עריכה כשיש טיוטה להערה קיימת', (
    tester,
  ) async {
    final draftService = PersonalNoteDraftService();
    await draftService.saveDraft(
      bookId: 'ספר מבחן',
      noteId: 'note-1',
      draft: PersonalNoteDraft(
        content: 'טיוטה חדשה',
        contentPlain: 'טיוטה חדשה',
        contentFormat: PersonalNoteContentFormat.plain,
        updatedAt: DateTime(2026, 1, 5),
        noteId: 'note-1',
      ),
    );

    final note = PersonalNote(
      id: 'note-1',
      bookId: 'ספר מבחן',
      lineNumber: 4,
      displayTitle: 'שורה 4',
      lastKnownLineNumber: 4,
      status: PersonalNoteStatus.located,
      content: 'תוכן שמור',
      contentPlain: 'תוכן שמור',
      contentFormat: PersonalNoteContentFormat.plain,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteTile(
            note: note,
            defaultExpanded: false,
            bookId: 'ספר מבחן',
            linkableNotes: const [],
            onSave: (_) {},
            onDelete: () {},
            onLinkTap: (_) {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('שמור'), findsOneWidget);
    expect(find.text('ביטול'), findsOneWidget);
  });

  PersonalNote buildNote() => PersonalNote(
    id: 'note-expand',
    bookId: 'ספר מבחן',
    lineNumber: 7,
    displayTitle: 'שורה 7',
    lastKnownLineNumber: 7,
    status: PersonalNoteStatus.located,
    content: 'תוכן ההערה',
    contentPlain: 'תוכן ההערה',
    contentFormat: PersonalNoteContentFormat.plain,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  Widget wrap(NoteTile tile) => MaterialApp(home: Scaffold(body: tile));

  testWidgets('NoteTile נשאר סגור כש-defaultExpanded=false ואין expandToken', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        NoteTile(
          note: buildNote(),
          defaultExpanded: false,
          bookId: 'ספר מבחן',
          linkableNotes: const [],
          onSave: (_) {},
          onDelete: () {},
          onLinkTap: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('תוכן ההערה'), findsNothing);
  });

  testWidgets('NoteTile נפתח בכפייה כש-expandToken מוגדר באתחול', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        NoteTile(
          note: buildNote(),
          defaultExpanded: false,
          expandToken: 1,
          bookId: 'ספר מבחן',
          linkableNotes: const [],
          onSave: (_) {},
          onDelete: () {},
          onLinkTap: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('תוכן ההערה'), findsOneWidget);
  });

  testWidgets('NoteTile נפתח כש-expandToken משתנה לאחר בנייה', (tester) async {
    NoteTile tile(int? token) => NoteTile(
      note: buildNote(),
      defaultExpanded: false,
      expandToken: token,
      bookId: 'ספר מבחן',
      linkableNotes: const [],
      onSave: (_) {},
      onDelete: () {},
      onLinkTap: (_) {},
    );

    await tester.pumpWidget(wrap(tile(null)));
    await tester.pumpAndSettle();
    expect(find.text('תוכן ההערה'), findsNothing);

    await tester.pumpWidget(wrap(tile(1)));
    await tester.pumpAndSettle();
    expect(find.text('תוכן ההערה'), findsOneWidget);
  });

  testWidgets('לחיצה על עריכה מציגה כרטיס עריכה עם כותרת "עריכת הערה" ואייקון ביטול', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(NoteTile(
      note: buildNote(),
      defaultExpanded: true,
      bookId: 'ספר מבחן',
      linkableNotes: const [],
      onSave: (_) {},
      onDelete: () {},
      onLinkTap: (_) {},
    )));
    await tester.pumpAndSettle();

    // בהתחלה מוצגת שורת ההערה הרגילה עם תוכן ההערה וכפתור עריכה
    expect(find.text('עריכת הערה - שורה 7'), findsNothing);
    expect(find.byTooltip('עריכה'), findsOneWidget);

    // לחיצה על עריכה
    await tester.tap(find.byTooltip('עריכה'));
    await tester.pumpAndSettle();

    // כעת מוצג כרטיס העריכה
    expect(find.text('עריכת הערה - שורה 7'), findsOneWidget);
    expect(find.text('שמור'), findsOneWidget);
    expect(find.byTooltip('ביטול'), findsOneWidget);

    // לחיצה על כפתור הביטול בכותרת סוגרת את העריכה ומחזירה לתצוגה רגילה
    await tester.tap(find.byTooltip('ביטול'));
    await tester.pumpAndSettle();

    expect(find.text('עריכת הערה - שורה 7'), findsNothing);
    expect(find.byTooltip('עריכה'), findsOneWidget);
  });

  testWidgets('ביטול מכותרת העורך מוחק טיוטה קיימת', (tester) async {
    final draftService = PersonalNoteDraftService();
    final note = buildNote();
    await draftService.saveDraft(
      bookId: note.bookId,
      noteId: note.id,
      draft: PersonalNoteDraft(
        content: 'טיוטה לביטול',
        contentPlain: 'טיוטה לביטול',
        contentFormat: PersonalNoteContentFormat.plain,
        updatedAt: DateTime(2026, 1, 5),
        noteId: note.id,
      ),
    );

    await tester.pumpWidget(
      wrap(
        NoteTile(
          note: note,
          defaultExpanded: false,
          bookId: note.bookId,
          linkableNotes: const [],
          onSave: (_) {},
          onDelete: () {},
          onLinkTap: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('ביטול'));
    await tester.pumpAndSettle();

    expect(
      await draftService.loadDraft(bookId: note.bookId, noteId: note.id),
      isNull,
    );
  });
}
