import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/user_content_import/services/user_import_library.dart';
import 'package:path/path.dart' as p;

import '../../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late int fileId;
  final previousDataRoot = AppPaths.cachedDataRootPath;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_import_files');
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(p.join(tempDir.path, 'data_root'));

    // קובץ דורות עם כותרת בלבד: נקלט בלי ספרים במסד, ולכן מתאים לבדיקת
    // החיווט של ה-bloc בלי תלות בספרייה.
    final csv = File(p.join(tempDir.path, 'דורות.csv'))
      ..writeAsStringSync('ספר,דור,מחבר\n');
    final userDb = (await UserBooksDatabaseHolder.instance.repository).database;
    final library = UserImportLibrary(userDb);
    await library.addFiles([csv.path]);
    fileId = (await library.list()).single.id;
  });

  tearDown(() async {
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(previousDataRoot);
    await tempDir.delete(recursive: true);
  });

  CustomFoldersBloc build() => CustomFoldersBloc(addLibraryEvent: (_) {});

  blocTest<CustomFoldersBloc, CustomFoldersState>(
    'LoadUserImportFiles טוען את הקבצים השמורים',
    build: build,
    act: (bloc) => bloc.add(const LoadUserImportFiles()),
    verify: (bloc) {
      expect(bloc.state.importFiles.single.name, 'דורות.csv');
      expect(bloc.state.importFiles.single.enabled, isTrue);
    },
  );

  blocTest<CustomFoldersBloc, CustomFoldersState>(
    'SetUserImportFileEnabled משהה ומרענן את הרשימה',
    build: build,
    // הכתיבה רצה ב-isolate, ולכן ממתינים לסיום ולא רק לתור האירועים.
    act: (bloc) async {
      bloc.add(SetUserImportFileEnabled(fileId, enabled: false));
      await bloc.stream.firstWhere((state) => !state.isSyncing);
    },
    verify: (bloc) {
      expect(bloc.state.isSyncing, isFalse);
      expect(bloc.state.error, isNull);
      expect(bloc.state.importFiles.single.enabled, isFalse);
    },
  );

  blocTest<CustomFoldersBloc, CustomFoldersState>(
    'RemoveUserImportFile מסיר את הקובץ מהרשימה',
    build: build,
    act: (bloc) async {
      bloc.add(RemoveUserImportFile(fileId));
      await bloc.stream.firstWhere((state) => !state.isSyncing);
    },
    verify: (bloc) {
      expect(bloc.state.isSyncing, isFalse);
      expect(bloc.state.error, isNull);
      expect(bloc.state.importFiles, isEmpty);
    },
  );

  group('הודעת הייבוא סופרת רק את הקבצים שנבחרו (issue #4511)', () {
    late CustomFoldersBloc bloc;

    setUp(() async {
      final raw = await (await UserBooksDatabaseHolder.instance.repository)
          .database
          .database;
      raw.execute('PRAGMA foreign_keys = OFF');
      final bookFile = File(p.join(tempDir.path, 'מקור.txt'))
        ..writeAsStringSync('א\nב\nג\nד\nה\n');
      raw.execute(
        'INSERT INTO book (categoryId, sourceId, title, filePath, fileType) '
        "VALUES (1, 1, 'מקור', ?, 'txt')",
        [bookFile.path],
      );
      raw.execute(
        "INSERT INTO book (categoryId, sourceId, title) VALUES (1, 1, 'מפרש')",
      );
      final targetId = raw.lastInsertRowId;
      raw.execute("INSERT INTO tocText (text) VALUES ('פרק א')");
      raw.execute(
        'INSERT INTO tocEntry (bookId, textId, level, lineIndex) '
        'VALUES (?, ?, 1, 7)',
        [targetId, raw.lastInsertRowId],
      );
      bloc = build();
    });

    tearDown(() => bloc.close());

    String write(String folder, String name, String content) {
      final dir = Directory(p.join(tempDir.path, folder))..createSync();
      return (File(p.join(dir.path, name))..writeAsStringSync(content)).path;
    }

    /// קובץ קישורים מ"מקור" אל "מפרש", קישור לכל שורת מקור מ-[first] עד [last].
    String linksFile(String folder, int first, int last) => write(
      folder,
      'מקור.links.csv',
      [
        'מקור_אישי,מקור,ספר_יעד,מיקום_יעד,סוג,יעד_אישי',
        for (var line = first; line <= last; line++)
          'כן,$line,מפרש,פרק א,הפניה,כן',
      ].join('\n'),
    );

    Future<String?> import(List<String> paths) async {
      bloc.add(ImportUserContentFiles(paths));
      final state = await bloc.stream.firstWhere((s) => !s.isSyncing);
      expect(state.error, isNull);
      return state.message;
    }

    test('ייבוא נוסף מדווח את קישורי הקובץ החדש, לא את סך הספרייה', () async {
      expect(await import([linksFile('א', 1, 2)]), 'יובאו 2 קישורים');
      expect(await import([linksFile('ב', 3, 5)]), 'יובאו 3 קישורים');
    });

    test('ייבוא חוזר של אותו קובץ מדווח את הקישורים שבו', () async {
      final first = linksFile('א', 1, 2);
      await import([first]);
      await import([linksFile('ב', 3, 5)]);
      expect(await import([first]), 'יובאו 2 קישורים');
    });

    test('קובץ שחלק מקישוריו כבר יובאו מדווח את כל קישוריו', () async {
      await import([linksFile('א', 1, 2)]);
      expect(await import([linksFile('ג', 2, 4)]), 'יובאו 3 קישורים');
    });

    test('דורות, כותרות וגרסאות נספרים רק בייבוא שהביא אותם', () async {
      await import([linksFile('א', 1, 2)]);
      expect(
        await import([
          write('נתונים', 'דורות.csv', 'ספר,דור\nמקור,ראשונים\n'),
          write('נתונים', 'מקור.כותרות.csv', 'כותרת,שורה\nפתיחה,1\n'),
          write('נתונים', 'גרסאות.csv', 'ראשי,גרסה\nמקור,מפרש\n'),
        ]),
        'יובאו 1 דורות ו-כותרות ל-1 ספרים ו-1 גרסאות',
      );
      expect(await import([linksFile('ב', 3, 3)]), 'יובאו 1 קישורים');
    });
  });
}
