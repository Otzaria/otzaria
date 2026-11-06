import 'dart:convert';
import 'dart:io';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_book_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
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
    AppPaths.debugOverrideDataRootPath(null);
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
  test(
    'portable PDF draft survives a root change through exact and latest lookup',
    () async {
      final service = PersonalNoteDraftService();
      for (final source in [BookSource.official, BookSource.user]) {
        await Settings.setValue(
          SettingsRepository.keyLibraryPath,
          r'C:\old\library',
        );
        final old = PdfBook(
          id: 42,
          title: 'ספר',
          path: r'C:\old\library\one\ספר.pdf',
          source: source,
        );
        final anchor = PdfNoteAnchor(
          pageNumber: 2,
          x: .3,
          y: .7,
          documentId: pdfPersonalNoteDocumentId(old),
        );
        final bookId = personalNotesBookKey(old);
        await service.saveDraft(
          bookId: bookId,
          lineNumber: 2,
          draft: PersonalNoteDraft(
            content: 'טיוטה ניידת',
            contentPlain: 'טיוטה ניידת',
            contentFormat: PersonalNoteContentFormat.plain,
            updatedAt: DateTime(2026),
            lineNumber: 2,
            pdfAnchor: anchor,
          ),
        );
        await Settings.setValue(
          SettingsRepository.keyLibraryPath,
          '/new/library',
        );
        final moved = PdfBook(
          id: 42,
          title: 'ספר',
          path: '/new/library/one/ספר.pdf',
          source: source,
        );
        final movedAnchor = PdfNoteAnchor(
          pageNumber: 2,
          x: .3,
          y: .7,
          documentId: pdfPersonalNoteDocumentId(moved),
        );
        final exact = await service.loadDraft(
          bookId: bookId,
          lineNumber: 2,
          pdfAnchor: movedAnchor,
        );
        final latest = await service.loadLatestNewNoteDraft(
          bookId: bookId,
          pdfDocumentId: movedAnchor.documentId,
          pdfDocumentIds: pdfPersonalNoteDocumentIds(moved),
        );
        expect(exact?.contentPlain, 'טיוטה ניידת');
        expect(latest?.contentPlain, 'טיוטה ניידת');
        expect(exact?.pdfAnchor, anchor);
        await service.clearDraft(
          bookId: bookId,
          lineNumber: 2,
          pdfAnchor: movedAnchor,
        );
        expect(
          await service.loadLatestNewNoteDraft(
            bookId: bookId,
            pdfDocumentId: movedAnchor.documentId,
          ),
          isNull,
        );
      }
    },
  );

  test(
    'legacy current-path PDF draft restores through exact and accepted latest identities',
    () async {
      final service = PersonalNoteDraftService();
      await Settings.setValue(SettingsRepository.keyLibraryPath, '/library');
      final book = PdfBook(
        id: 42,
        title: 'ספר',
        path: '/library/one/ספר.pdf',
        source: BookSource.user,
      );
      final anchor = PdfNoteAnchor(
        pageNumber: 2,
        x: .3,
        y: .7,
        documentId: 'u|${Uri.encodeComponent(book.path)}',
      );
      await service.saveDraft(
        bookId: 'ספר|user',
        lineNumber: 2,
        draft: PersonalNoteDraft(
          content: 'טיוטה קודמת',
          contentPlain: 'טיוטה קודמת',
          contentFormat: PersonalNoteContentFormat.plain,
          updatedAt: DateTime(2026),
          lineNumber: 2,
          pdfAnchor: anchor,
        ),
      );
      final latest = await service.loadLatestNewNoteDraft(
        bookId: 'ספר|user',
        pdfDocumentId: pdfPersonalNoteDocumentId(book),
        pdfDocumentIds: pdfPersonalNoteDocumentIds(book),
      );
      expect(latest?.pdfAnchor, anchor);
      expect(
        (await service.loadDraft(
          bookId: 'ספר|user',
          lineNumber: 2,
          pdfAnchor: latest!.pdfAnchor,
        ))?.contentPlain,
        'טיוטה קודמת',
      );
      final other = PdfBook(
        id: 43,
        title: 'ספר',
        path: '/library/two/ספר.pdf',
        source: BookSource.user,
      );
      expect(
        await service.loadLatestNewNoteDraft(
          bookId: 'ספר|user',
          pdfDocumentId: pdfPersonalNoteDocumentId(other),
          pdfDocumentIds: pdfPersonalNoteDocumentIds(other),
        ),
        isNull,
      );
    },
  );
  test('imported PDF draft restores after moving the data root', () async {
    final service = PersonalNoteDraftService();
    AppPaths.debugOverrideDataRootPath('/old/profile');
    final old = PdfBook(
      id: 42,
      title: 'ספר',
      path: '/old/profile/הספרים שלי/nested/ספר.pdf',
      source: BookSource.user,
    );
    final anchor = PdfNoteAnchor(
      pageNumber: 2,
      x: .3,
      y: .7,
      documentId: pdfPersonalNoteDocumentId(old),
    );
    await service.saveDraft(
      bookId: 'ספר|user',
      lineNumber: 2,
      draft: PersonalNoteDraft(
        content: 'טיוטת ספר מיובא',
        contentPlain: 'טיוטת ספר מיובא',
        contentFormat: PersonalNoteContentFormat.plain,
        updatedAt: DateTime(2026),
        lineNumber: 2,
        pdfAnchor: anchor,
      ),
    );
    AppPaths.debugOverrideDataRootPath('/new/profile');
    final moved = PdfBook(
      id: 42,
      title: 'ספר',
      path: '/new/profile/הספרים שלי/nested/ספר.pdf',
      source: BookSource.user,
    );
    final movedAnchor = PdfNoteAnchor(
      pageNumber: 2,
      x: .3,
      y: .7,
      documentId: pdfPersonalNoteDocumentId(moved),
    );
    expect(
      (await service.loadDraft(
        bookId: 'ספר|user',
        lineNumber: 2,
        pdfAnchor: movedAnchor,
      ))?.contentPlain,
      'טיוטת ספר מיובא',
    );
    expect(
      (await service.loadLatestNewNoteDraft(
        bookId: 'ספר|user',
        pdfDocumentId: movedAnchor.documentId,
        pdfDocumentIds: pdfPersonalNoteDocumentIds(moved),
      ))?.contentPlain,
      'טיוטת ספר מיובא',
    );
  });
}
