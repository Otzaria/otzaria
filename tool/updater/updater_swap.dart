import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:otzaria/update/differential/swap_plan.dart';
import 'package:path/path.dart' as p;

/// כל פעולות מערכת הקבצים של ההחלפה, בנקודה אחת, כדי שאפשר יהיה להזריק
/// כשל אמיתי בבדיקות ולבדוק את השחזור.
class SwapFileSystem {
  const SwapFileSystem();

  bool exists(String path) => File(path).existsSync();

  void createParent(String path) =>
      Directory(p.dirname(path)).createSync(recursive: true);

  /// מחליף את [to] ב-[from], שיושב לצדו באותה תיקייה. ב-Windows זה
  /// `MoveFileEx` עם REPLACE_EXISTING: הנתיב מצביע תמיד על הישן או על החדש.
  void replace(String from, String to) => File(from).renameSync(to);

  void copy(String from, String to) {
    createParent(to);
    File(from).copySync(to);
  }

  void delete(String path) {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }

  int lengthOf(String path) => File(path).lengthSync();

  /// האם תהליך אחר מחזיק את הקובץ. פתיחה לכתיבה (בלי לכתוב דבר) נכשלת
  /// ב-Windows על exe/dll שממופה כתמונת תהליך חי — בדיוק הנעילה שמפילה החלפה.
  bool isHeldByAnotherProcess(String path) {
    try {
      File(path).openSync(mode: FileMode.append).closeSync();
      return false;
    } on FileSystemException {
      return true;
    }
  }

  String hashOf(String path) {
    final sink = _DigestSink();
    final hash = sha256.startChunkedConversion(sink);
    final file = File(path).openSync();
    final buffer = Uint8List(1024 * 1024);
    try {
      while (true) {
        final count = file.readIntoSync(buffer);
        if (count == 0) break;
        hash.add(Uint8List.sublistView(buffer, 0, count));
      }
    } finally {
      file.closeSync();
    }
    hash.close();
    return sink.digest.toString();
  }
}

class _DigestSink implements Sink<Digest> {
  late final Digest digest;

  @override
  void add(Digest value) => digest = value;

  @override
  void close() {}
}

enum SwapOutcome { succeeded, abortedBeforeAnyChange, rolledBack, corrupted }

/// תוצאת ההחלפה. [SwapOutcome.corrupted] הוא המצב היחיד שבו ההתקנה אינה
/// שלמה — הוא מדווח את הקבצים שיש לשחזר ידנית מתיקיית הגיבוי.
class SwapResult {
  SwapResult({
    required this.outcome,
    this.error,
    this.installedFiles = 0,
    this.rollbackErrors = const [],
  });

  final SwapOutcome outcome;
  final String? error;
  final int installedFiles;
  final List<String> rollbackErrors;

  bool get succeeded => outcome == SwapOutcome.succeeded;
}

/// התקנה חלקית אסור להפעיל: אוצריא הייתה עולה עם תערובת של שתי גרסאות.
bool shouldRelaunchAfterSwap(SwapOutcome outcome) =>
    outcome != SwapOutcome.corrupted;

/// האם עדיין ראוי להפעיל את אוצריא מחדש אחרי ההחלפה. מי שסגר אותה וכבר
/// עבר הלאה — או מכבה את המחשב — אינו רוצה חלון שנפתח מולו.
bool relaunchWindowStillOpen({
  required DateTime exitedAt,
  required DateTime now,
  required Duration window,
}) => now.difference(exitedAt) <= window;

/// ההודעה שהמשתמש רואה כשההחלפה והשחזור נכשלו שניהם.
String corruptedInstallMessage(String backupRoot) =>
    'העדכון נכשל באמצע, והשחזור האוטומטי לא הצליח. ההתקנה של אוצריא '
    'אינה שלמה כרגע ואין להפעיל אותה.\n\n'
    'הקבצים המקוריים שמורים בתיקייה:\n$backupRoot\n\n'
    'אפשר להעתיק אותם בחזרה לתיקיית ההתקנה, או להתקין את אוצריא מחדש '
    'מהמתקין המלא.';

/// סיומת העותק שמחכה לצד קובץ היעד עד ה-rename שמחליף אותו.
const String kIncomingSuffix = '.otzaria-incoming';

/// שם הערך ב-RunOnce. ה-"!" דוחה את מחיקתו עד שהפקודה הסתיימה, כך ששחזור
/// שנקטע בעצמו ירוץ שוב בכניסה הבאה.
const String kLogonRecoveryValueName = '!OtzariaUpdateRecovery';

/// שורת הפקודה שמשחזרת בכניסה הבאה למערכת, בלי שאוצריא תצטרך לעלות.
/// [updaterCopy] הוא העותק שמחוץ להתקנה — זה שבתוכה עשוי להיות באמצע החלפה.
String logonRecoveryCommand({
  required String updaterCopy,
  required String planPath,
}) => '"$updaterCopy" --plan "$planPath" --recover --no-relaunch --from-temp';

/// קובצי ה-exe בשורש הם נקודות הכניסה: מותקנים אחרונים, והסרות קורות רק
/// אחריהם — קבצים שהגרסה הישנה עוד צריכה לא נעלמים לפני שהיא הוחלפה.
List<SwapFile> _installOrder(List<SwapFile> files) {
  bool isEntryPoint(SwapFile file) =>
      !file.path.contains('/') && file.path.toLowerCase().endsWith('.exe');
  return [
    ...files.where((file) => !isEntryPoint(file)),
    ...files.where(isEntryPoint),
  ];
}

class _Paths {
  _Paths(this.plan);
  final SwapPlan plan;

  String install(String path) => p.join(plan.installRoot, path);
  String staging(String path) => p.join(plan.stagingRoot, path);
  String backup(String path) => p.join(plan.backupRoot, path);
  String incoming(String path) => '${install(path)}$kIncomingSuffix';

  Iterable<String> get allPaths => [
    for (final file in plan.files) file.path,
    for (final removal in plan.removals) removal.path,
  ];
}

bool _isInstalled(SwapFile file, _Paths at, SwapFileSystem fs) {
  final target = at.install(file.path);
  return fs.exists(target) && fs.hashOf(target) == file.sha256;
}

/// היעד לעולם אינו חסר: הישן מועתק לגיבוי, החדש מועתק לצדו, ורק rename
/// אחד מחליף ביניהם. ה-staging נשאר שלם, ולכן אפשר תמיד להשלים קדימה.
void _installOne(SwapFile file, _Paths at, SwapFileSystem fs) {
  final target = at.install(file.path);
  if (fs.exists(target)) fs.copy(target, at.backup(file.path));
  fs.copy(at.staging(file.path), at.incoming(file.path));
  fs.replace(at.incoming(file.path), target);
}

/// ההסרה מוחקת רק אחרי שהגיבוי הועתק במלואו.
void _removeOne(SwapRemoval removal, _Paths at, SwapFileSystem fs) {
  final target = at.install(removal.path);
  fs.copy(target, at.backup(removal.path));
  fs.delete(target);
}

void _restoreOne(String path, _Paths at, SwapFileSystem fs) {
  fs.copy(at.backup(path), at.incoming(path));
  fs.replace(at.incoming(path), at.install(path));
}

void _deleteIncoming(_Paths at, SwapFileSystem fs) {
  for (final path in at.allPaths) {
    fs.delete(at.incoming(path));
  }
}

/// מחליף את קובצי ההתקנה בקבצים שב-staging. שום קובץ אינו נמחק לפני שגובה,
/// וכשל בכל שלב מחזיר את ההתקנה כולה לגרסה הישנה.
///
/// [beforeFirstChange] רץ אחרי כל הבדיקות ולפני הנגיעה הראשונה בהתקנה —
/// כשל בו מבטל את ההחלפה כשההתקנה עוד שלמה.
SwapResult applySwapPlan(
  SwapPlan plan, {
  SwapFileSystem fs = const SwapFileSystem(),
  void Function()? beforeFirstChange,
}) {
  final at = _Paths(plan);

  try {
    _preflight(plan, fs, at);
    beforeFirstChange?.call();
    Directory(plan.backupRoot).createSync(recursive: true);
  } catch (error) {
    return SwapResult(
      outcome: SwapOutcome.abortedBeforeAnyChange,
      error: '$error',
    );
  }

  var installed = 0;
  try {
    for (final file in _installOrder(plan.files)) {
      _installOne(file, at, fs);
      installed++;
    }
    for (final removal in plan.removals) {
      if (fs.exists(at.install(removal.path))) _removeOne(removal, at, fs);
    }
  } catch (error) {
    final errors = _restoreFromBackup(plan, at, fs).errors;
    return SwapResult(
      outcome: errors.isEmpty ? SwapOutcome.rolledBack : SwapOutcome.corrupted,
      error: '$error',
      installedFiles: installed,
      rollbackErrors: errors,
    );
  }
  return SwapResult(outcome: SwapOutcome.succeeded, installedFiles: installed);
}

enum SwapRecovery {
  /// אין עדות להחלפה שנקטעה.
  nothingToDo,

  /// קובץ בהתקנה מוחזק בידי תהליך חי — לא נגעו בדבר, וינסו שוב מאוחר יותר.
  busy,

  /// ההחלפה הושלמה — ההתקנה כולה בגרסה החדשה.
  completed,

  /// ההחלפה בוטלה — ההתקנה כולה בגרסה הישנה.
  restored,

  /// לא הושלמה ולא בוטלה. תיקיית הגיבוי נשארת במקומה.
  failed,
}

class SwapRecoveryResult {
  SwapRecoveryResult(this.outcome, {this.error, this.changedFiles = 0});

  final SwapRecovery outcome;
  final String? error;
  final int changedFiles;
}

/// משלים או מבטל החלפה שהמעדכן נהרג באמצעה. המצב נגזר מהדיסק בלבד: קובץ
/// שכבר הותקן זהה ל-hash שבתוכנית, וכל שלב בהחלפה ניתן להרצה חוזרת.
///
/// הכיוון נבחר פעם אחת לכל ההחלפה — קדימה רק כשכל קובץ בתוכנית זמין —
/// ולכן ההתקנה מסתיימת בגרסה אחת שלמה ולא בתערובת.
SwapRecoveryResult recoverInterruptedSwap(
  SwapPlan plan, {
  SwapFileSystem fs = const SwapFileSystem(),
}) {
  final at = _Paths(plan);

  if (!Directory(plan.backupRoot).existsSync()) {
    return SwapRecoveryResult(SwapRecovery.nothingToDo);
  }
  // שחזור מהכניסה למערכת עשוי לרוץ כשאוצריא כבר עלתה; היא תשגר שחזור משלה.
  if (_heldTarget(at, fs) != null) {
    return SwapRecoveryResult(SwapRecovery.busy);
  }

  bool isStaged(SwapFile file) {
    final staged = at.staging(file.path);
    return fs.exists(staged) &&
        fs.lengthOf(staged) == file.size &&
        fs.hashOf(staged) == file.sha256;
  }

  var changed = 0;
  try {
    _deleteIncoming(at, fs);
    final alreadyInstalled = <String>{};
    final canComplete = plan.files.every(
      (file) {
        if (_isInstalled(file, at, fs)) {
          alreadyInstalled.add(file.path);
          return true;
        }
        return isStaged(file);
      },
    );

    if (canComplete) {
      for (final file in _installOrder(plan.files)) {
        if (alreadyInstalled.contains(file.path)) continue;
        _installOne(file, at, fs);
        changed++;
      }
      for (final removal in plan.removals) {
        final target = at.install(removal.path);
        if (!fs.exists(target)) continue;
        if (fs.hashOf(target) != removal.sha256) continue;
        _removeOne(removal, at, fs);
        changed++;
      }
      return SwapRecoveryResult(SwapRecovery.completed, changedFiles: changed);
    }

    final restore = _restoreFromBackup(plan, at, fs);
    if (restore.errors.isNotEmpty) {
      return SwapRecoveryResult(
        SwapRecovery.failed,
        error: restore.errors.join('; '),
        changedFiles: restore.changed,
      );
    }
    return SwapRecoveryResult(
      SwapRecovery.restored,
      changedFiles: restore.changed,
    );
  } catch (error) {
    return SwapRecoveryResult(
      SwapRecovery.failed,
      error: '$error',
      changedFiles: changed,
    );
  }
}

/// מחזיר את ההתקנה לגרסה הישנה לפי מה שעל הדיסק. גיבוי משמש רק כשהיעד כבר
/// השתנה — אז העתקתו הסתיימה בוודאות; גיבוי שנקטע יושב תמיד לצד יעד שלם.
({int changed, List<String> errors}) _restoreFromBackup(
  SwapPlan plan,
  _Paths at,
  SwapFileSystem fs,
) {
  final errors = <String>[];
  var changed = 0;
  void attempt(String path, void Function() action) {
    try {
      action();
      changed++;
    } catch (error) {
      errors.add('$path: $error');
    }
  }

  try {
    _deleteIncoming(at, fs);
  } catch (error) {
    errors.add('$error');
  }
  for (final removal in plan.removals.reversed) {
    if (fs.exists(at.install(removal.path))) continue;
    if (!fs.exists(at.backup(removal.path))) continue;
    attempt(removal.path, () => _restoreOne(removal.path, at, fs));
  }
  for (final file in _installOrder(plan.files).reversed) {
    if (!_isInstalled(file, at, fs)) continue;
    if (fs.exists(at.backup(file.path))) {
      attempt(file.path, () => _restoreOne(file.path, at, fs));
    } else {
      // קובץ שהגרסה החדשה הוסיפה: ההתקנה הישנה בלעדיו.
      attempt(file.path, () => fs.delete(at.install(file.path)));
    }
  }
  return (changed: changed, errors: errors);
}

String? _heldTarget(_Paths at, SwapFileSystem fs) {
  for (final path in at.allPaths) {
    final target = at.install(path);
    if (fs.exists(target) && fs.isHeldByAnotherProcess(target)) return path;
  }
  return null;
}

/// ממתין עד [timeout] שאף קובץ יעד לא יהיה מוחזק. עוזרים שרצים מתיקיית ההתקנה,
/// כמו crashpad_handler.exe, משתחררים רק רגע אחרי יציאת אוצריא.
bool waitForTargetsReleased(
  SwapPlan plan, {
  SwapFileSystem fs = const SwapFileSystem(),
  Duration timeout = const Duration(seconds: 30),
  Duration interval = const Duration(milliseconds: 250),
}) {
  final at = _Paths(plan);
  final deadline = DateTime.now().add(timeout);
  while (_heldTarget(at, fs) != null) {
    if (!DateTime.now().isBefore(deadline)) return false;
    sleep(interval);
  }
  return true;
}

/// כל הבדיקות שאפשר לעשות לפני שנוגעים בהתקנה. כשל כאן משאיר אותה כפי
/// שהייתה, וגם בלי תיקיית גיבוי — שאחרת הייתה נראית כהחלפה שנקטעה.
void _preflight(SwapPlan plan, SwapFileSystem fs, _Paths at) {
  if (!Directory(plan.installRoot).existsSync()) {
    throw StateError('the install directory is missing: ${plan.installRoot}');
  }
  if (!Directory(plan.stagingRoot).existsSync()) {
    throw StateError('the staging directory is missing: ${plan.stagingRoot}');
  }
  if (p.equals(plan.backupRoot, plan.installRoot) ||
      p.isWithin(plan.installRoot, plan.backupRoot) ||
      p.isWithin(plan.installRoot, plan.stagingRoot)) {
    throw StateError(
      'the staging and backup directories must be outside '
      'the install directory',
    );
  }
  // עדיף "העדכון לא קרה" על "העדכון בוטל באמצע": קובץ נעול מפיל את ההחלפה
  // בדרכה ומחייב שחזור, וכאן ההתקנה עוד לא נגעה.
  final held = _heldTarget(at, fs);
  if (held != null) {
    throw StateError('$held: the file is still held by another process');
  }

  for (final file in plan.files) {
    final staged = at.staging(file.path);
    if (!fs.exists(staged)) {
      throw StateError('${file.path}: the staged file is missing');
    }
    if (fs.lengthOf(staged) != file.size || fs.hashOf(staged) != file.sha256) {
      throw StateError('${file.path}: the staged file does not match the plan');
    }
  }
  for (final removal in plan.removals) {
    final target = at.install(removal.path);
    if (!fs.exists(target)) continue;
    if (fs.hashOf(target) != removal.sha256) {
      throw StateError(
        '${removal.path}: the local file is not the file being removed',
      );
    }
  }

  if (Directory(plan.backupRoot).existsSync()) {
    Directory(plan.backupRoot).deleteSync(recursive: true);
  }
}
