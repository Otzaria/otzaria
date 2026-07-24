import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
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
}
