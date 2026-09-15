import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/cache_database_holder.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart' as migration_models;
import 'package:otzaria/migration/models/category.dart' as migration_models;
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;

/// ספר שתוכנו יושב בקובץ DOCX חיצוני נקרא בעבר ב-`readAsString`, שזורק על ZIP
/// בינארי. ה-catch החזיר תוכן ריק, ולכן ההערות איבדו את העיגון לטקסט ונפלו
/// למסלול העיגון-לפי-עמוד שנועד ל-PDF בלבד.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase seforimDb;
  late SeforimRepository seforimRepo;
  late int categoryId;
  late PersonalNotesRepository notesRepository;

  const bookLines = [
    'בראשית ברא אלהים את השמים ואת הארץ',
    'והארץ היתה תהו ובהו וחשך על פני תהום',
    'ויאמר אלהים יהי אור ויהי אור',
  ];

  // docxToText מוסיף שורת <h1> עם שם הספר בראש הפלט, ולכן שורות הספר מתחילות
  // ב-2. מספרי השורות בהערות הם 1-based.
  const firstBookLine = 2;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('notes-file-backed-');
    final libraryPath = p.join(tempDir.path, 'library');
    final dataRootPath = p.join(tempDir.path, 'data_root');
    await Directory(libraryPath).create(recursive: true);

    await Settings.init(cacheProvider: _MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath(dataRootPath);
    await UserBooksDatabaseHolder.instance.close();

    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      libraryPath,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryFolderName,
      '',
    );
    await Settings.setValue<String>(SettingsRepository.keyDbEffectivePath, '');

    final dbPath = p.join(libraryPath, DatabaseConstants.databaseFileName);
    seforimDb = MyDatabase.withPath(dbPath);
    seforimRepo = SeforimRepository(seforimDb);
    await seforimRepo.ensureInitialized();
    categoryId = await seforimRepo.insertCategory(
      const migration_models.Category(title: 'שורש'),
    );

    await SqliteDataProvider.instance.dispose();
    await SqliteDataProvider.instance.initialize();

    notesRepository = PersonalNotesRepository();
  });

  tearDown(() async {
    await SqliteDataProvider.instance.dispose();
    await UserBooksDatabaseHolder.instance.close();
    // שני המסדים יושבים בתיקייה הזמנית; פתוחים — Windows מסרב למחוק אותה.
    await CacheDatabaseHolder.instance.close();
    await PersonalNotesDatabase.instance.close();
    seforimDb.close();
    AppPaths.debugOverrideDataRootPath(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// כותב DOCX תקין שכל פסקה בו היא שורה בספר.
  Future<File> writeDocx(String name, List<String> paragraphs) async {
    final body = paragraphs
        .map((line) => '<w:p><w:r><w:t>$line</w:t></w:r></w:p>')
        .join();
    final xml = utf8.encode(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>$body</w:body>'
      '</w:document>',
    );
    final archive = Archive()
      ..addFile(ArchiveFile('word/document.xml', xml.length, xml));
    final file = File(p.join(tempDir.path, name));
    await file.writeAsBytes(Uint8List.fromList(ZipEncoder().encode(archive)));
    return file;
  }

  Future<void> registerBook(String title, File file, String fileType) async {
    final sourceId = await seforimRepo.insertSource('test::$title', -1);
    await seforimRepo.insertBook(
      migration_models.Book(
        categoryId: categoryId,
        sourceId: sourceId,
        title: title,
        fileType: fileType,
        filePath: file.path,
        // הספר שחשף את הבאג היה בדיוק כך: קובץ חיצוני שההמרה שלו נכשלה,
        // ולכן ה-DB נשאר עם 0 שורות.
        totalLines: 0,
      ),
    );
  }

  test('הערה על ספר DOCX מקבלת כותרת תצוגה מן השורה', () async {
    const title = 'ספר וורד';
    await registerBook(
      title,
      await writeDocx('$title.docx', bookLines),
      'docx',
    );

    final notes = await notesRepository.addNote(
      bookId: title,
      lineNumber: firstBookLine + 2,
      content: 'הערה על יהי אור',
      contentPlain: 'הערה על יהי אור',
      contentFormat: PersonalNoteContentFormat.plain,
      categoryId: categoryId,
    );

    expect(notes, hasLength(1));
    expect(
      notes.single.displayTitle,
      contains('ויאמר אלהים יהי אור'),
      reason: 'תוכן ריק היה משאיר את כותרת התצוגה ריקה',
    );
  });

  test('הערה על ספר DOCX נשארת מעוגנת בטעינה מחדש', () async {
    const title = 'ספר מעוגן';
    await registerBook(
      title,
      await writeDocx('$title.docx', bookLines),
      'docx',
    );

    await notesRepository.addNote(
      bookId: title,
      lineNumber: firstBookLine + 1,
      content: 'הערה',
      contentPlain: 'הערה',
      contentFormat: PersonalNoteContentFormat.plain,
      selectedText: 'תהו ובהו',
      categoryId: categoryId,
    );

    final loaded = await notesRepository.loadNotes(
      title,
      categoryId: categoryId,
    );

    expect(loaded, hasLength(1));
    expect(loaded.single.status, PersonalNoteStatus.located);
    expect(
      loaded.single.anchorText,
      contains('תהו ובהו'),
      reason: 'בלי תוכן אמיתי אין מול מה לחשב עוגן',
    );
  });

  test('העוגן עוקב אחרי השורה כשהקובץ נערך ושורה נוספה בראשו', () async {
    const title = 'ספר נערך';
    final file = await writeDocx('$title.docx', bookLines);
    await registerBook(title, file, 'docx');

    await notesRepository.addNote(
      bookId: title,
      lineNumber: firstBookLine + 2,
      content: 'הערה',
      contentPlain: 'הערה',
      contentFormat: PersonalNoteContentFormat.plain,
      selectedText: 'יהי אור',
      categoryId: categoryId,
    );

    // הקובץ נערך: נוספה שורה בראש, ולכן הטקסט המעוגן זז שורה אחת קדימה.
    await writeDocx('$title.docx', ['הקדמה חדשה', ...bookLines]);

    final loaded = await notesRepository.loadNotes(
      title,
      categoryId: categoryId,
    );

    expect(loaded.single.status, PersonalNoteStatus.located);
    expect(
      loaded.single.lineNumber,
      firstBookLine + 3,
      reason: 'בלי תוכן אמיתי אין מול מה לעגן, וההערה נשארת במקומה הישן',
    );
  });

  test('ספר טקסט רגיל ממשיך לעבוד', () async {
    const title = 'ספר טקסט';
    final file = File(p.join(tempDir.path, '$title.txt'));
    await file.writeAsString(bookLines.join('\n'));
    await registerBook(title, file, 'txt');

    final notes = await notesRepository.addNote(
      bookId: title,
      lineNumber: 1,
      content: 'הערה',
      contentPlain: 'הערה',
      contentFormat: PersonalNoteContentFormat.plain,
      categoryId: categoryId,
    );

    expect(notes.single.displayTitle, contains('בראשית ברא אלהים'));
  });

  test('ספר PDF נשאר בעיגון-לפי-עמוד — המספר אינו נכווץ', () async {
    const title = 'ספר פידיאף';
    final file = File(p.join(tempDir.path, '$title.pdf'));
    await file.writeAsBytes(const [0x25, 0x50, 0x44, 0x46]);
    await registerBook(title, file, 'pdf');

    final notes = await notesRepository.addNote(
      bookId: title,
      lineNumber: 42,
      content: 'הערה על עמוד 42',
      contentPlain: 'הערה על עמוד 42',
      contentFormat: PersonalNoteContentFormat.plain,
      categoryId: categoryId,
    );

    expect(
      notes.single.lineNumber,
      42,
      reason: 'ל-PDF אין שורות, ומספר העמוד נשמר כפי שהוא',
    );
  });
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) return value;
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }
}
