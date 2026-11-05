import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>(HiveCache.keyName);
    await Settings.init(cacheProvider: HiveCache());
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test(
    'loadLatestNewNoteDraft מחזיר את הטיוטה החדשה האחרונה של הספר',
    () async {
      final service = PersonalNoteDraftService();

      await service.saveDraft(
        bookId: 'ספר א',
        lineNumber: 3,
        draft: PersonalNoteDraft(
          content: 'ישן',
          contentPlain: 'ישן',
          contentFormat: PersonalNoteContentFormat.plain,
          updatedAt: DateTime(2026, 1, 1),
          lineNumber: 3,
        ),
      );
      await service.saveDraft(
        bookId: 'ספר א',
        lineNumber: 7,
        draft: PersonalNoteDraft(
          content: 'חדש',
          contentPlain: 'חדש',
          contentFormat: PersonalNoteContentFormat.plain,
          updatedAt: DateTime(2026, 1, 2),
          lineNumber: 7,
          referenceText: 'כותרת',
        ),
      );
      await service.saveDraft(
        bookId: 'ספר א',
        noteId: 'note-1',
        draft: PersonalNoteDraft(
          content: 'טיוטת עריכה',
          contentPlain: 'טיוטת עריכה',
          contentFormat: PersonalNoteContentFormat.plain,
          updatedAt: DateTime(2026, 1, 3),
          noteId: 'note-1',
        ),
      );

      final latest = await service.loadLatestNewNoteDraft(bookId: 'ספר א');

      expect(latest, isNotNull);
      expect(latest!.lineNumber, 7);
      expect(latest.contentPlain, 'חדש');
      expect(latest.referenceText, 'כותרת');
    },
  );

  test('אפשר לשמור ולטעון טיוטה של הערה קיימת לפי noteId', () async {
    final service = PersonalNoteDraftService();

    await service.saveDraft(
      bookId: 'ספר ב',
      noteId: 'note-42',
      draft: PersonalNoteDraft(
        content: '{"ops":[{"insert":"שלום"}]}',
        contentPlain: 'שלום',
        contentFormat: PersonalNoteContentFormat.quillDelta,
        updatedAt: DateTime(2026, 1, 4),
        noteId: 'note-42',
      ),
    );

    final loaded = await service.loadDraft(
      bookId: 'ספר ב',
      noteId: 'note-42',
    );

    expect(loaded, isNotNull);
    expect(loaded!.noteId, 'note-42');
    expect(loaded.contentPlain, 'שלום');
    expect(loaded.contentFormat, PersonalNoteContentFormat.quillDelta);
  });

  test('loadLatestNewNoteDraft מחזיר null כשה-Hive box סגור', () async {
    // סוגר את ה-box מבלי לפתוח מחדש
    await Hive.close();

    final service = PersonalNoteDraftService();
    final result = await service.loadLatestNewNoteDraft(bookId: 'ספר כלשהו');

    expect(result, isNull);

    // פותח מחדש לתקינות tearDown
    await Hive.openBox<dynamic>(HiveCache.keyName);
    await Settings.init(cacheProvider: HiveCache());
  });

  test('clearDraft מוחק את המפתח מה-Box', () async {
    final service = PersonalNoteDraftService();

    await service.saveDraft(
      bookId: 'ספר ג',
      lineNumber: 5,
      draft: PersonalNoteDraft(
        content: 'טיוטה זמנית',
        contentPlain: 'טיוטה זמנית',
        contentFormat: PersonalNoteContentFormat.plain,
        updatedAt: DateTime(2026, 1, 5),
        lineNumber: 5,
      ),
    );

    final box = Hive.box<dynamic>(HiveCache.keyName);
    expect(box.containsKey('personal_note_draft:ספר ג:5'), isTrue);

    await service.clearDraft(bookId: 'ספר ג', lineNumber: 5);

    expect(box.containsKey('personal_note_draft:ספר ג:5'), isFalse);
    expect(await service.loadDraft(bookId: 'ספר ג', lineNumber: 5), isNull);
  });

  test('טיוטת PDF משמרת נקודה פיזית בשמירה ובשחזור האחרון', () async {
    const anchor = PdfNoteAnchor(pageNumber: 12, x: .37, y: .82);
    final service = PersonalNoteDraftService();
    await service.saveDraft(
      bookId: 'מסמך בדיקה|user',
      lineNumber: 12,
      draft: PersonalNoteDraft(
        content: 'טיוטה',
        contentPlain: 'טיוטה',
        contentFormat: PersonalNoteContentFormat.plain,
        updatedAt: DateTime.utc(2026, 1, 1),
        lineNumber: 12,
        pdfAnchor: anchor,
      ),
    );
    expect(
      (await service.loadDraft(
        bookId: 'מסמך בדיקה|user',
        lineNumber: 12,
        pdfAnchor: anchor,
      ))!.pdfAnchor,
      anchor,
    );
    expect(
      (await service.loadLatestNewNoteDraft(
        bookId: 'מסמך בדיקה|user',
      ))!.pdfAnchor,
      anchor,
    );
  });

  test(
    'טיוטות בשתי נקודות באותו עמוד אינן דורסות או מוחקות זו את זו',
    () async {
      final service = PersonalNoteDraftService();
      const first = PdfNoteAnchor(pageNumber: 4, x: .2, y: .3);
      const second = PdfNoteAnchor(pageNumber: 4, x: .7, y: .8);
      for (final (anchor, content) in [
        (first, 'נקודה א'),
        (second, 'נקודה ב'),
      ]) {
        await service.saveDraft(
          bookId: 'מסמך בדיקה',
          categoryId: 7,
          lineNumber: 4,
          draft: PersonalNoteDraft(
            content: content,
            contentPlain: content,
            contentFormat: PersonalNoteContentFormat.plain,
            updatedAt: DateTime.utc(2026, 1, 1),
            pdfAnchor: anchor,
          ),
        );
      }
      expect(
        (await service.loadDraft(
          bookId: 'מסמך בדיקה',
          categoryId: 7,
          lineNumber: 4,
          pdfAnchor: first,
        ))?.contentPlain,
        'נקודה א',
      );
      expect(
        (await service.loadDraft(
          bookId: 'מסמך בדיקה',
          categoryId: 7,
          lineNumber: 4,
          pdfAnchor: second,
        ))?.contentPlain,
        'נקודה ב',
      );
      expect(
        await service.loadDraft(
          bookId: 'מסמך בדיקה',
          categoryId: 7,
          lineNumber: 4,
        ),
        isNull,
      );
      await service.clearDraft(
        bookId: 'מסמך בדיקה',
        categoryId: 7,
        lineNumber: 4,
        pdfAnchor: second,
      );
      expect(
        await service.loadDraft(
          bookId: 'מסמך בדיקה',
          categoryId: 7,
          lineNumber: 4,
          pdfAnchor: second,
        ),
        isNull,
      );
      expect(
        (await service.loadDraft(
          bookId: 'מסמך בדיקה',
          categoryId: 7,
          lineNumber: 4,
          pdfAnchor: first,
        ))?.contentPlain,
        'נקודה א',
      );
    },
  );

  test('טיוטת נקודה במפתח ישן נטענת רק לאותו עוגן ומועברת בלי אובדן', () async {
    final service = PersonalNoteDraftService();
    const anchor = PdfNoteAnchor(pageNumber: 4, x: .2, y: .3);
    final legacy = PersonalNoteDraft(
      content: 'טיוטה ישנה',
      contentPlain: 'טיוטה ישנה',
      contentFormat: PersonalNoteContentFormat.plain,
      updatedAt: DateTime.utc(2026, 1, 1),
      lineNumber: 4,
      pdfAnchor: anchor,
    );
    await Settings.setValue<String>(
      'personal_note_draft:מסמך בדיקה@7:4',
      jsonEncode(legacy.toJson()),
    );
    expect(
      await service.loadDraft(
        bookId: 'מסמך בדיקה',
        categoryId: 7,
        lineNumber: 4,
      ),
      isNull,
    );
    expect(
      await service.loadDraft(
        bookId: 'מסמך בדיקה',
        categoryId: 7,
        lineNumber: 4,
        pdfAnchor: const PdfNoteAnchor(pageNumber: 4, x: .8, y: .9),
      ),
      isNull,
    );
    expect(
      (await service.loadDraft(
        bookId: 'מסמך בדיקה',
        categoryId: 7,
        lineNumber: 4,
        pdfAnchor: anchor,
      ))?.contentPlain,
      'טיוטה ישנה',
    );
    await service.clearDraft(
      bookId: 'מסמך בדיקה',
      categoryId: 7,
      lineNumber: 4,
    );
    await service.saveDraft(
      bookId: 'מסמך בדיקה',
      categoryId: 7,
      lineNumber: 4,
      draft: PersonalNoteDraft(
        content: 'טיוטת טקסט',
        contentPlain: 'טיוטת טקסט',
        contentFormat: PersonalNoteContentFormat.plain,
        updatedAt: DateTime.utc(2026, 1, 2),
      ),
    );
    expect(
      (await service.loadDraft(
        bookId: 'מסמך בדיקה',
        categoryId: 7,
        lineNumber: 4,
        pdfAnchor: anchor,
      ))?.contentPlain,
      'טיוטה ישנה',
    );
    expect(
      (await service.loadDraft(
        bookId: 'מסמך בדיקה',
        categoryId: 7,
        lineNumber: 4,
      ))?.contentPlain,
      'טיוטת טקסט',
    );
  });

  test('טיוטות באותה נקודה במסמכים בעלי אותו שם נשמרות בנפרד', () async {
    final service = PersonalNoteDraftService();
    const first = PdfNoteAnchor(
      pageNumber: 4,
      x: .2,
      y: .3,
      documentId: 'edition-a',
    );
    const second = PdfNoteAnchor(
      pageNumber: 4,
      x: .2,
      y: .3,
      documentId: 'edition-b',
    );
    for (final (anchor, content, day) in [
      (first, 'מסמך א', 1),
      (second, 'מסמך ב', 2),
    ]) {
      await service.saveDraft(
        bookId: 'מסמך בדיקה',
        categoryId: 7,
        lineNumber: 4,
        draft: PersonalNoteDraft(
          content: content,
          contentPlain: content,
          contentFormat: PersonalNoteContentFormat.plain,
          updatedAt: DateTime.utc(2026, 1, day),
          pdfAnchor: anchor,
        ),
      );
    }
    expect(
      (await service.loadLatestNewNoteDraft(
        bookId: 'מסמך בדיקה',
        categoryId: 7,
        pdfDocumentId: 'edition-a',
      ))?.contentPlain,
      'מסמך א',
    );
    expect(
      (await service.loadLatestNewNoteDraft(
        bookId: 'מסמך בדיקה',
        categoryId: 7,
        pdfDocumentId: 'edition-b',
      ))?.contentPlain,
      'מסמך ב',
    );
    await service.clearDraft(
      bookId: 'מסמך בדיקה',
      categoryId: 7,
      lineNumber: 4,
      pdfAnchor: second,
    );
    expect(
      (await service.loadDraft(
        bookId: 'מסמך בדיקה',
        categoryId: 7,
        lineNumber: 4,
        pdfAnchor: first,
      ))?.contentPlain,
      'מסמך א',
    );
    expect(
      await service.loadDraft(
        bookId: 'מסמך בדיקה',
        categoryId: 7,
        lineNumber: 4,
        pdfAnchor: second,
      ),
      isNull,
    );
  });

  test('שחזור אחרון שומר על ספר וקטגוריה ומאפשר להחריג נקודות PDF', () async {
    final service = PersonalNoteDraftService();
    for (final (bookId, category, anchor, day, content) in [
      ('מסמך בדיקה|user', 7, null, 1, 'טקסט'),
      (
        'מסמך בדיקה|user',
        7,
        const PdfNoteAnchor(pageNumber: 4, x: .2, y: .3),
        2,
        'נקודה',
      ),
      ('מסמך בדיקה|user', 8, null, 3, 'קטגוריה אחרת'),
      ('מסמך בדיקה|other', 7, null, 4, 'מקור אחר'),
    ]) {
      await service.saveDraft(
        bookId: bookId,
        categoryId: category,
        lineNumber: 4,
        draft: PersonalNoteDraft(
          content: content,
          contentPlain: content,
          contentFormat: PersonalNoteContentFormat.plain,
          updatedAt: DateTime.utc(2026, 1, day),
          pdfAnchor: anchor,
        ),
      );
    }
    expect(
      (await service.loadLatestNewNoteDraft(
        bookId: 'מסמך בדיקה|user',
        categoryId: 7,
      ))?.contentPlain,
      'נקודה',
    );
    expect(
      (await service.loadLatestNewNoteDraft(
        bookId: 'מסמך בדיקה|user',
        categoryId: 7,
        includePdfAnchors: false,
      ))?.contentPlain,
      'טקסט',
    );
  });
}
