import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as path;

import '../../data/data_providers/database_library_provider.dart';
import '../database/daos/database.dart';
import '../database/repository/seforim_repository.dart';
import '../database/sql/query_loader.dart';
import '../../settings/services/custom_folders/custom_folder.dart';
import 'file_sync_service.dart';

/// חלון "אין התקדמות" — האיזולייט נהרג רק אם לא דווחה שום התקדמות אמיתית
/// (שלב או ספר) במשך פרק זמן זה. גדול דיו כדי לכסות insert סינכרוני של ספר
/// גדול יחיד שחוסם את לולאת האירועים; רק תקיעה שמעֵברת אותו נחשבת אמיתית.
/// ההריגה (`Isolate.kill`) חיונית: בלעדיה האיזולייט היה ממשיך לכתוב אחרי
/// שה-RO נפתח מחדש — כותב יתום במרוץ.
const Duration _isolateNoProgressTimeout = Duration(minutes: 8);

/// תקרת-זמן כוללת קשיחה: גם אם ההתקדמות נמשכת, סנכרון שחורג ממנה נהרג.
/// גיבוי אחרון מפני לולאה פתולוגית שמדווחת התקדמות אך לעולם אינה מסתיימת.
const Duration _isolateTotalCeiling = Duration(minutes: 45);

/// סמן פינג-ההתקדמות שנשלח על ה-SendPort. מחרוזת (לא Map), כדי להבחין בבירור
/// ממפת התוצאה הסופית.
const String _workerHeartbeat = 'otzaria.sync.progress';

/// Runs a full custom-folders DB sync inside a background isolate.
///
/// All calls are serialised through [DatabaseLibraryProvider.operationQueue]
/// so that concurrent writes to the same SQLite file are impossible,
/// regardless of which call site invokes this function.
///
/// [QueryLoader] is pre-initialised on the main isolate and its cache is
/// forwarded in the payload, avoiding any [rootBundle] access inside the
/// worker isolate.
///
/// [dbPath] — נתיב `seforim.db` (לתוכן רשמי + links).
/// [userBooksDbPath] — נתיב `user_books.db` (לתיקיות מותאמות אישית).
///
/// [prepareForWrite]/[restoreAfterWrite] — וו אופציונלי שהקורא מזריק כדי לסגור
/// ולפתוח-מחדש את חיבור הקריאה ל-seforim.db (closeForExternalWrite/reopen).
/// הם רצים *בתוך* יחידת התור (לא בזמן ההמתנה בתור), צמודים ב-try/finally כך
/// שה-RO נסגר רק למשך הכתיבה ולא בזמן שפעולת תור אחרת (למשל סריקת ספרים
/// אישיים) רצה לפנינו. שכבת הנתונים עצמה אינה תלויה ב-SqliteDataProvider —
/// הקורא (שכבת האפליקציה) מזריק את הלוגיקה.
Future<FileSyncResult> runCustomFoldersDbSyncInIsolate({
  required String dbPath,
  required String userBooksDbPath,
  required String libraryPath,
  required List<CustomFolder> customFolders,
  String folderName = '',
  String? onlyFolderPath,
  Future<void> Function()? prepareForWrite,
  Future<void> Function()? restoreAfterWrite,
}) async {
  Map<String, Object?> buildPayload({
    required bool syncFolders,
    required bool syncLinks,
  }) => <String, Object?>{
    'queryCache': QueryLoader.cacheSnapshot,
    'dbPath': dbPath,
    'userBooksDbPath': userBooksDbPath,
    'libraryPath': libraryPath,
    'folderName': folderName,
    'customFolders': customFolders.map((f) => f.toJson()).toList(),
    'syncFolders': syncFolders,
    'syncLinks': syncLinks,
    'onlyFolderPath': onlyFolderPath,
  };

  // שלב 1 — כתיבת הספרים האישיים ל-user_books.db. seforim.db נפתח RO (רק
  // קריאות), ולכן *אין* קריאה ל-prepareForWrite/restoreAfterWrite: ה-RO הראשי
  // נשאר פתוח וקריאות עובדות לכל אורך החלק הכבד הזה.
  final folders = await DatabaseLibraryProvider.operationQueue.enqueue(
    () async {
      await QueryLoader.initialize();
      final resultMap = await _runWorkerIsolate(
        buildPayload(syncFolders: true, syncLinks: false),
        isDelete: false,
      );
      return _resultFromMap(resultMap);
    },
  );

  // שלב 2 — עיבוד ה-links → seforim.db (RW). רץ *רק* כשיש קבצי links שטרם
  // עובדו: קבצי links מעובדים פעם אחת ונמחקים (ראה
  // [LinkProcessor.processLinksDirectory]), ולכן בפתיחה רגילה אין מה לעבד.
  // דילוג מונע סגירת ה-RO ופתיחת seforim.db RW לחינם — מקור לחסימת פתיחת
  // ספרים בעלייה ולסגירה תקועה כשסוגרים את התוכנה תוך כדי הסנכרון.
  // הבדיקה רצה *בתוך* יחידת התור כדי שתהיה סריאלית: אם קריאת סנכרון אחרת
  // עיבדה ומחקה את ה-links לפנינו, נראה זאת ולא נסגור את ה-RO לחינם.
  final links = await DatabaseLibraryProvider.operationQueue.enqueue(() async {
    if (!await _hasPendingLinkFiles(libraryPath)) {
      return const FileSyncResult();
    }
    // *רק כאן* סוגרים את ה-RO הראשי (prepareForWrite) ופותחים מחדש
    // (restoreAfterWrite), לזמן הקצר של כתיבת ה-links בלבד.
    await QueryLoader.initialize();
    final payload = buildPayload(syncFolders: false, syncLinks: true);
    if (prepareForWrite != null) await prepareForWrite();
    try {
      final resultMap = await _runWorkerIsolate(payload, isDelete: false);
      return _resultFromMap(resultMap);
    } finally {
      if (restoreAfterWrite != null) await restoreAfterWrite();
    }
  });

  return FileSyncResult(
    addedBooks: folders.addedBooks + links.addedBooks,
    updatedBooks: folders.updatedBooks + links.updatedBooks,
    addedCategories: folders.addedCategories + links.addedCategories,
    addedLinks: folders.addedLinks + links.addedLinks,
    skippedFiles: folders.skippedFiles + links.skippedFiles,
    errors: [...folders.errors, ...links.errors],
    duration: folders.duration + links.duration,
    updatedBookIds: [...folders.updatedBookIds, ...links.updatedBookIds],
  );
}

/// בודק אם תיקיית ה-`links` תחת [libraryPath] מכילה קובץ links שטרם עובד.
/// קבצי links מעובדים פעם אחת ונמחקים, והתיקייה נמחקת כשהיא מתרוקנת — כך
/// שדילוג כאן מונע את שלב הכתיבה היקר (סגירת RO + פתיחת seforim.db RW) כשאין בו צורך.
Future<bool> _hasPendingLinkFiles(String libraryPath) async {
  final linksDir = Directory(path.join(libraryPath, 'links'));
  try {
    if (!await linksDir.exists()) return false;
    await for (final entity in linksDir.list()) {
      if (entity is File &&
          path.extension(entity.path) == '.json' &&
          !path.basename(entity.path).endsWith('_headings.json')) {
        return true;
      }
    }
  } on FileSystemException {
    // תיקייה לא נגישה (הרשאות/מחיקה תוך כדי) — מדלגים על שלב ה-links; אם
    // באמת יש links הם ייתפסו בפתיחה הבאה, ואין סיבה להפיל את כל הסנכרון.
    return false;
  }
  return false;
}

FileSyncResult _resultFromMap(Map<String, Object?> resultMap) => FileSyncResult(
  addedBooks: resultMap['addedBooks'] as int,
  updatedBooks: resultMap['updatedBooks'] as int,
  addedCategories: resultMap['addedCategories'] as int,
  addedLinks: resultMap['addedLinks'] as int,
  skippedFiles: resultMap['skippedFiles'] as int,
  errors: List<String>.from(resultMap['errors'] as List),
  duration: Duration(milliseconds: resultMap['durationMs'] as int),
  updatedBookIds: List<int>.from(
    (resultMap['updatedBookIds'] as List?) ?? const [],
  ),
);

/// מטען ההודעה לאיזולייט. נושא רק ערכים שליחים (SendPort + מפת payload + דגל),
/// כך ש-[_workerIsolateMain] נשאר top-level וסוגר על כלום — ולעולם לא "סוחב"
/// את ה-SqliteDataProvider/FfiDatabase הלא-שליח של הפונקציה הקוראת
/// (Illegal argument in isolate message: object is unsendable).
class _WorkerMessage {
  final SendPort responsePort;
  final Map<String, Object?> payload;
  final bool isDelete;
  const _WorkerMessage(this.responsePort, this.payload, this.isDelete);
}

/// נקודת הכניסה לאיזולייט. שולחת בחזרה את מפת התוצאה (ריקה עבור מחיקה); חריגה
/// מנותבת אוטומטית ל-onError port (`errorsAreFatal`).
Future<void> _workerIsolateMain(_WorkerMessage message) async {
  final Map<String, Object?> result;
  if (message.isDelete) {
    await _deleteWorkerEntryPoint(message.payload);
    result = const <String, Object?>{};
  } else {
    // כל התקדמות אמיתית (שלב/ספר) שולחת פינג שמאפס את ה-watchdog בצד הקורא —
    // כך תקיעה אמיתית (ללא התקדמות) נהרגת, אך ייבוא איטי שמתקדם לא.
    result = await _syncWorkerEntryPoint(
      message.payload,
      onProgress: () => message.responsePort.send(_workerHeartbeat),
    );
  }
  message.responsePort.send(result);
}

/// מריץ worker באיזולייט עם watchdog מבוסס-התקדמות שמסוגל *להרוג* אותו בפועל.
/// כל פינג-התקדמות מאפס את שעון "אין-התקדמות"; רק היעדר התקדמות ל-
/// [_isolateNoProgressTimeout] רצוף (תקיעה אמיתית), או חריגה מ-
/// [_isolateTotalCeiling] הכולל, הורגים את האיזולייט לפני שה-finally של הקורא
/// פותח מחדש את ה-RO, כך שלא נשאר כותב יתום. ההריגה ב-finally רצה גם בנתיב
/// ההצלחה — איזולייט מ-[Isolate.spawn] אינו מסתיים מעצמו (בניגוד ל-Isolate.run).
Future<Map<String, Object?>> _runWorkerIsolate(
  Map<String, Object?> payload, {
  required bool isDelete,
}) async {
  final responsePort = ReceivePort();
  final errorPort = ReceivePort();
  final completer = Completer<Map<String, Object?>>();

  Timer? noProgressWatchdog;
  void armNoProgressWatchdog() {
    noProgressWatchdog?.cancel();
    noProgressWatchdog = Timer(_isolateNoProgressTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException(
            'sync worker hang: no progress',
            _isolateNoProgressTimeout,
          ),
        );
      }
    });
  }

  responsePort.listen((message) {
    // פינג-התקדמות — מאפס את שעון "אין-התקדמות" ואינו מסיים את הפעולה. כל
    // הודעה אחרת היא מפת התוצאה הסופית.
    if (message == _workerHeartbeat) {
      armNoProgressWatchdog();
      return;
    }
    if (!completer.isCompleted) {
      completer.complete((message as Map).cast<String, Object?>());
    }
  });
  errorPort.listen((error) {
    if (!completer.isCompleted) {
      final parts = error as List;
      completer.completeError(
        Exception('sync worker failed: ${parts.first}'),
        StackTrace.fromString('${parts.length > 1 ? parts[1] : ''}'),
      );
    }
  });

  final isolate = await Isolate.spawn(
    _workerIsolateMain,
    _WorkerMessage(responsePort.sendPort, payload, isDelete),
    onError: errorPort.sendPort,
    errorsAreFatal: true,
  );

  armNoProgressWatchdog();
  // תקרה כוללת קשיחה — לא מתאפסת בהתקדמות, גיבוי אחרון לסנכרון שלא נגמר.
  final totalCeiling = Timer(_isolateTotalCeiling, () {
    if (!completer.isCompleted) {
      completer.completeError(
        TimeoutException(
          'sync worker exceeded total ceiling',
          _isolateTotalCeiling,
        ),
      );
    }
  });
  try {
    return await completer.future;
  } finally {
    noProgressWatchdog?.cancel();
    totalCeiling.cancel();
    isolate.kill(priority: Isolate.immediate);
    responsePort.close();
    errorPort.close();
  }
}

/// Runs a folder-delete operation inside a background isolate.
///
/// [folderPath] הוא הנתיב המלא של התיקייה — ממנו נגזר שם ה-`source`
/// הייחודי שלפיו מזוהים ספרי התיקייה למחיקה. זיהוי לפי source (ולא לפי שם
/// קטגוריה) מונע פגיעה בתיקייה אחרת בעלת אותו basename.
/// Serialised through the same [DatabaseLibraryProvider.operationQueue].
///
/// [userBooksDbPath] — נתיב `user_books.db` (שם נמצאות התיקיות המותאמות).
/// [dbPath] — נתיב `seforim.db`. נדרש כי `FileSyncService` מצפה לשני repos.
///
/// [otherConfiguredFolderPaths] — נתיבי התיקיות שנשארות מוגדרות: ספר legacy
/// בתיקיית-בן מקוננת לא יימחק יחד עם תיקיית-האב.
Future<void> runDeleteFolderFromDbInIsolate({
  required String dbPath,
  required String userBooksDbPath,
  required String folderPath,
  List<String> otherConfiguredFolderPaths = const [],
  Future<void> Function()? prepareForWrite,
  Future<void> Function()? restoreAfterWrite,
}) {
  return DatabaseLibraryProvider.operationQueue.enqueue(() async {
    await QueryLoader.initialize();
    // Build payload on the main isolate so cacheSnapshot is evaluated here,
    // not lazily inside the worker closure.
    final payload = <String, Object?>{
      'queryCache': QueryLoader.cacheSnapshot,
      'dbPath': dbPath,
      'userBooksDbPath': userBooksDbPath,
      'folderPath': folderPath,
      'otherConfiguredFolderPaths': otherConfiguredFolderPaths,
    };
    // [prepareForWrite]/[restoreAfterWrite] רצים בתוך יחידת התור — ראה ההסבר
    // ב-[runCustomFoldersDbSyncInIsolate].
    if (prepareForWrite != null) await prepareForWrite();
    try {
      await _runWorkerIsolate(payload, isDelete: true);
    } finally {
      if (restoreAfterWrite != null) await restoreAfterWrite();
    }
  });
}

// ── worker entry points (top-level so they're transferable) ──────────────────

Future<Map<String, Object?>> _syncWorkerEntryPoint(
  Map<String, Object?> payload, {
  void Function()? onProgress,
}) async {
  QueryLoader.seedCache(
    (payload['queryCache'] as Map).cast<String, Map<String, String>>(),
  );

  final dbPath = payload['dbPath'] as String;
  final userBooksDbPath = payload['userBooksDbPath'] as String;
  final libraryPath = payload['libraryPath'] as String;
  final folderName = (payload['folderName'] as String?) ?? '';
  final syncFolders = (payload['syncFolders'] as bool?) ?? true;
  final syncLinks = (payload['syncLinks'] as bool?) ?? true;
  final onlyFolderPath = payload['onlyFolderPath'] as String?;
  final rawFolders = (payload['customFolders'] as List)
      .cast<Map<String, dynamic>>();
  final customFolders = rawFolders.map(CustomFolder.fromJson).toList();

  // seforim.db נפתח RW *רק* כשמעבדים links (היחיד שכותב לשם). בשלב הספרים
  // האישיים אנחנו רק קוראים מ-seforim.db (בדיקת dedup), ולכן פותחים אותו RO —
  // כך החיבור הראשי לא צריך להיסגר והקריאות ממשיכות לעבוד לכל אורך הכתיבה.
  final database = MyDatabase.withPath(dbPath, readOnly: !syncLinks);
  final repository = SeforimRepository(database);
  await repository.ensureInitialized();

  final userBooksDatabase = MyDatabase.withPath(userBooksDbPath);
  final userBooksRepository = SeforimRepository(userBooksDatabase);
  await userBooksRepository.ensureInitialized();

  final service = FileSyncService.createForWorker(
    repository,
    userBooksRepository: userBooksRepository,
  );

  try {
    final result = await service.syncCustomFoldersWithInputs(
      libraryPath: libraryPath,
      customFolders: customFolders,
      folderName: folderName,
      syncFolders: syncFolders,
      syncLinks: syncLinks,
      onlyFolderPath: onlyFolderPath,
      onProgress: onProgress == null ? null : (_, _) => onProgress(),
    );
    return {
      'addedBooks': result.addedBooks,
      'updatedBooks': result.updatedBooks,
      'addedCategories': result.addedCategories,
      'addedLinks': result.addedLinks,
      'skippedFiles': result.skippedFiles,
      'errors': result.errors,
      'durationMs': result.duration.inMilliseconds,
      'updatedBookIds': result.updatedBookIds,
    };
  } finally {
    database.close();
    userBooksDatabase.close();
  }
}

Future<void> _deleteWorkerEntryPoint(Map<String, Object?> payload) async {
  QueryLoader.seedCache(
    (payload['queryCache'] as Map).cast<String, Map<String, String>>(),
  );

  final dbPath = payload['dbPath'] as String;
  final userBooksDbPath = payload['userBooksDbPath'] as String;
  final folderPath = payload['folderPath'] as String;
  final otherConfiguredFolderPaths =
      ((payload['otherConfiguredFolderPaths'] as List?) ?? const [])
          .cast<String>();

  // מחיקת תיקייה כותבת רק ל-user_books.db; seforim.db נפתח read-only כדי לא
  // להפוך אותו ל-WAL ולא להריץ עליו DDL (CREATE TABLE) שמזהם את ה-DB הרשמי.
  final database = MyDatabase.withPath(dbPath, readOnly: true);
  final repository = SeforimRepository(database);
  await repository.ensureInitialized();

  final userBooksDatabase = MyDatabase.withPath(userBooksDbPath);
  final userBooksRepository = SeforimRepository(userBooksDatabase);
  await userBooksRepository.ensureInitialized();

  final service = FileSyncService.createForWorker(
    repository,
    userBooksRepository: userBooksRepository,
  );

  try {
    await service.deleteFolderFromDatabase(
      folderPath,
      otherConfiguredFolderPaths: otherConfiguredFolderPaths,
    );
  } finally {
    database.close();
    userBooksDatabase.close();
  }
}
