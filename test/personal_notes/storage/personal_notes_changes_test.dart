import 'dart:async';
import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
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

  test('מחיקת כל הערות הספר מודיעה על הספר', () async {
    await db.insertNote(_note('1', bookId: 'רש"י'));
    await delivered();
    changes.clear();

    await db.deleteBookNotes('רש"י');

    expect(await delivered(), ['רש"י']);
  });

  test('עדכון הערה שאינה קיימת אינו מודיע', () async {
    await db.updateNote(_note('missing', bookId: 'רש"י'));
    expect(await delivered(), isEmpty);
  });

  test('מחיקת ספר ללא הערות אינה מודיעה', () async {
    await db.deleteBookNotes('רש"י');
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
