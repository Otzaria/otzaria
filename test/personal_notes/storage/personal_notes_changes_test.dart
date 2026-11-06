import 'dart:async';
import 'dart:io';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_changes.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';

import '../../test_helpers/memory_cache_provider.dart';

/// כל כתיבה של המשתמש למסד ההערות מודיעה על הספר שהשתנה, כדי שתצוגות
/// שמחזיקות עותק (טורי המפרש בצורת הדף) לא ימשיכו להדגיש הערה שנמחקה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dataRoot;
  late List<String> changes;
  late int initialRevision;
  late StreamSubscription<String> subscription;
  final db = PersonalNotesDatabase.instance;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() async {
    dataRoot = await Directory.systemTemp.createTemp('notes_changes_test_');
    AppPaths.debugOverrideDataRootPath(dataRoot.path);
    await db.close();
    await Settings.setValue(
      SettingsRepository.keyDatabasesPath,
      '${dataRoot.path}/databases',
    );
    changes = [];
    initialRevision = db.revision.value;
    subscription = PersonalNotesChanges.stream.listen(changes.add);
  });

  tearDown(() async {
    await subscription.cancel();
    await db.close();
    AppPaths.debugOverrideDataRootPath(null);
    await Settings.setValue(SettingsRepository.keyDatabasesPath, '');
    try {
      await dataRoot.delete(recursive: true);
    } catch (_) {}
  });

  /// מחכה למסירת האירועים — הזרם אינו סינכרוני.
  Future<List<String>> delivered() async {
    await pumpEventQueue();
    expect(db.revision.value - initialRevision, changes.isEmpty ? 0 : 1);
    initialRevision = db.revision.value;
    return changes;
  }

  test('הוספת הערה מודיעה על ספר ההערה', () async {
    await db.insertNote(_note('1', bookId: 'רש"י'));

    expect(await delivered(), ['רש"י']);
  });

  test('עדכון הערה מודיע על ספר ההערה', () async {
    await db.insertNote(_note('1', bookId: 'רש"י'));
    await delivered();
    changes.clear();

    await db.updateNote(_note('1', bookId: 'רש"י', content: 'תוכן חדש'));

    expect(await delivered(), ['רש"י']);
  });

  test('מחיקת הערה מודיעה על הספר שלה, אף שהקריאה מקבלת רק מזהה', () async {
    await db.insertNote(_note('1', bookId: 'תוספות'));
    await delivered();
    changes.clear();

    await db.deleteNote('1');

    expect(await delivered(), ['תוספות']);
    expect(await db.getNote('1'), isNull);
  });

  test('מחיקת הערה שאינה קיימת אינה מודיעה', () async {
    await db.deleteNote('לא-קיים');

    expect(await delivered(), isEmpty);
  });

  test('עדכון הערה שאינה קיימת נדחה ואינו מודיע', () async {
    await expectLater(
      db.updateNote(_note('missing', bookId: 'רש"י')),
      throwsStateError,
    );
    expect(await delivered(), isEmpty);
  });

  test('ייבוא חוזר אינו מודיע וסופר רק רשומות שנוספו', () async {
    final original = _note('1', bookId: 'רש"י');
    await db.insertNote(original);
    await delivered();
    changes.clear();

    expect(await db.batchInsertNotes([original]), 0);
    expect(await delivered(), isEmpty);
    expect(await db.batchInsertNotes([]), 0);
    expect(await delivered(), isEmpty);
    expect(
      await db.batchInsertNotes([
        original,
        _note('2', bookId: 'תוספות'),
        _note('2', bookId: 'תוספות'),
      ]),
      1,
    );
    expect(await delivered(), ['תוספות']);
  });

  test('איגוד הודעות מפרסם את הספרים רק אחרי הכתיבות', () async {
    final result = await db.batchNotifications((batch) async {
      await batch.insertNote(_note('1', bookId: 'א'));
      await batch.updateNote(_note('1', bookId: 'א', content: 'עודכן'));
      await batch.insertNote(_note('2', bookId: 'ב'));
      expect(await delivered(), isEmpty);
      expect((await db.getNote('1'))!.content, 'עודכן');
      return 2;
    });

    expect(result, 2);
    expect(await delivered(), ['א', 'ב']);
  });

  test('עדכון חסר באצוות הודעות שומר ומפרסם כתיבות קודמות', () async {
    await expectLater(
      db.batchNotifications((batch) async {
        await batch.insertNote(_note('1', bookId: 'א'));
        await batch.insertNote(_note('2', bookId: 'א'));
        await batch.updateNote(_note('missing', bookId: 'ב'));
      }),
      throwsStateError,
    );

    expect(await delivered(), ['א']);
    expect((await db.loadNotes('א')).map((note) => note.id), ['1', '2']);
    expect(await db.getNote('missing'), isNull);
  });

  test('פעולה מקבילה אינה מצטרפת לאצוות הודעות ממתינה', () async {
    final started = Completer<void>();
    final resume = Completer<void>();
    addTearDown(() {
      if (!resume.isCompleted) resume.complete();
    });
    final batch = db.batchNotifications((batch) async {
      await batch.insertNote(_note('1', bookId: 'א'));
      started.complete();
      await resume.future;
      await batch.insertNote(_note('2', bookId: 'א'));
    });
    await started.future;
    expect(await delivered(), isEmpty);

    await db.insertNote(_note('3', bookId: 'ב'));
    expect(await delivered(), ['ב']);
    changes.clear();
    resume.complete();
    await batch;
    expect(await delivered(), ['א']);
  });

  test('הוספת אצווה מודיעה פעם אחת על כל ספר', () async {
    await db.batchInsertNotes([
      _note('1', bookId: 'רש"י'),
      _note('2', bookId: 'רש"י'),
      _note('3', bookId: 'תוספות'),
    ]);

    expect(await delivered(), unorderedEquals(['רש"י', 'תוספות']));
  });

  test(
    'יישוב מיקומים בזמן טעינה אינו מודיע — אחרת מאזין שטוען ייכנס ללולאה',
    () async {
      await db.insertNote(_note('1', bookId: 'רש"י'));
      await delivered();
      changes.clear();

      await db.batchUpdateNotes([_note('1', bookId: 'רש"י', lineNumber: 4)]);

      expect(await delivered(), isEmpty);
      expect((await db.getNote('1'))!.lineNumber, 4);
    },
  );
}

PersonalNote _note(
  String id, {
  required String bookId,
  String content = 'תוכן',
  int lineNumber = 1,
}) {
  final now = DateTime(2026, 10, 4);
  return PersonalNote(
    id: id,
    bookId: bookId,
    lineNumber: lineNumber,
    displayTitle: 'שורה',
    lastKnownLineNumber: lineNumber,
    status: PersonalNoteStatus.located,
    content: content,
    contentPlain: content,
    contentFormat: PersonalNoteContentFormat.plain,
    createdAt: now,
    updatedAt: now,
  );
}
