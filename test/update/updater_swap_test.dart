import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/update/differential/swap_plan.dart';
import 'package:path/path.dart' as p;

import '../../tool/updater/updater_swap.dart';

/// כשל אמיתי באמצע ההחלפה: הקובץ שלא ניתן להעתיק או להחליף (נעול).
class _LockedFileSystem extends SwapFileSystem {
  _LockedFileSystem(this.lockedSource);

  final String lockedSource;

  void _check(String from) {
    if (p.basename(from) == lockedSource) {
      throw const FileSystemException('the file is locked by another process');
    }
  }

  @override
  void copy(String from, String to) {
    _check(from);
    super.copy(from, to);
  }

  @override
  void replace(String from, String to) {
    _check(from);
    super.replace(from, to);
  }
}

/// כשל שגם השחזור אינו מתאושש ממנו — מהכשל הראשון אף שינוי אינו מצליח.
class _UnrecoverableFileSystem extends _LockedFileSystem {
  _UnrecoverableFileSystem(super.lockedSource);

  bool _broken = false;

  @override
  void _check(String from) {
    if (_broken) throw const FileSystemException('the disk is gone');
    try {
      super._check(from);
    } on FileSystemException {
      _broken = true;
      rethrow;
    }
  }

  @override
  void delete(String path) {
    if (_broken) throw const FileSystemException('the disk is gone');
    super.delete(path);
  }
}

/// מות התהליך: מהשינוי ה-[crashAt] ואילך שום שינוי אינו קורה עוד. אחרי כל
/// שינוי שכן קרה נבדק [invariant] — מצב ביניים שהמשתמש עלול לראות.
class _CrashingFileSystem extends SwapFileSystem {
  _CrashingFileSystem({required this.crashAt, required this.invariant});

  final int crashAt;
  final void Function() invariant;
  int mutations = 0;

  void _step(void Function() change) {
    if (mutations >= crashAt) {
      throw const FileSystemException('the process died');
    }
    mutations++;
    change();
    invariant();
  }

  @override
  void copy(String from, String to) => _step(() => super.copy(from, to));

  @override
  void replace(String from, String to) => _step(() => super.replace(from, to));

  @override
  void delete(String path) => _step(() => super.delete(path));
}

/// רושם את סדר השינויים בהתקנה.
class _RecordingFileSystem extends SwapFileSystem {
  final List<String> changes = [];

  @override
  void replace(String from, String to) {
    changes.add('replace ${p.basename(to)}');
    super.replace(from, to);
  }

  @override
  void delete(String path) {
    if (File(path).existsSync()) changes.add('delete ${p.basename(path)}');
    super.delete(path);
  }
}

class _CountingHashFileSystem extends SwapFileSystem {
  final hashes = <String, int>{};

  @override
  String hashOf(String path) {
    hashes.update(path, (count) => count + 1, ifAbsent: () => 1);
    return super.hashOf(path);
  }
}

/// קובץ יעד שתהליך אחר מחזיק — בלי לנעול קובץ אמיתי במערכת ההפעלה.
class _HeldFileSystem extends SwapFileSystem {
  _HeldFileSystem(this.held);

  final Set<String> held;

  @override
  bool isHeldByAnotherProcess(String path) =>
      held.any((name) => p.basename(path) == p.basename(name));
}

/// קובץ שתהליך אחר מחזיק במספר הבדיקות הראשונות ואז משחרר, כמו
/// crashpad_handler.exe שיוצא רגע אחרי אוצריא.
class _ReleasingFileSystem extends SwapFileSystem {
  _ReleasingFileSystem(this.name, {required this.heldChecks});

  final String name;
  int heldChecks;

  @override
  bool isHeldByAnotherProcess(String path) {
    if (p.basename(path) != name || heldChecks == 0) return false;
    heldChecks--;
    return true;
  }
}

String _hash(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

Map<String, String> _hashTree(Directory root) {
  final hashes = <String, String>{};
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File) continue;
    hashes[p.relative(entity.path, from: root.path).replaceAll('\\', '/')] =
        _hash(entity.path);
  }
  return hashes;
}

bool _sameTree(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

void _write(String path, String content) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

void main() {
  late Directory temp;
  late Directory install;
  late Directory staging;
  late Directory backup;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('otzaria-updater-swap');
    install = Directory(p.join(temp.path, 'install'))..createSync();
    staging = Directory(p.join(temp.path, 'work', 'staging'))
      ..createSync(recursive: true);
    backup = Directory(p.join(temp.path, 'work', 'backup'));

    _write(p.join(install.path, 'otzaria.exe'), 'old binary');
    _write(p.join(install.path, 'data', 'a.dat'), 'old a');
    _write(p.join(install.path, 'data', 'b.dat'), 'old b');
    _write(p.join(install.path, 'legacy.dll'), 'obsolete');
    // נתוני משתמש בתוך שורש ההתקנה — מצב נייד.
    _write(p.join(install.path, 'otzaria_data', 'settings.hive'), 'mine');

    _write(p.join(staging.path, 'otzaria.exe'), 'new binary');
    _write(p.join(staging.path, 'data', 'a.dat'), 'new a');
    _write(p.join(staging.path, 'data', 'b.dat'), 'new b');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('hash בזרימה נשאר נכון בגבול מקטע הקריאה ובקובץ ריק', () {
    final file = File(p.join(temp.path, 'hash-test.bin'));
    file.writeAsBytesSync([]);
    expect(
      const SwapFileSystem().hashOf(file.path),
      sha256.convert([]).toString(),
    );
    final bytes = List<int>.generate(1024 * 1024 + 17, (i) => i & 0xff);
    file.writeAsBytesSync(bytes);
    expect(
      const SwapFileSystem().hashOf(file.path),
      sha256.convert(bytes).toString(),
    );
  });

  SwapPlan plan({List<SwapRemoval>? removals}) => SwapPlan(
    platform: 'windows',
    architecture: 'x64',
    fromReleaseTag: '0.9.97+100',
    toReleaseTag: '0.9.97+101',
    installRoot: install.path,
    stagingRoot: staging.path,
    backupRoot: backup.path,
    files: [
      for (final path in const ['otzaria.exe', 'data/a.dat', 'data/b.dat'])
        SwapFile(
          path: path,
          sha256: _hash(p.join(staging.path, path)),
          size: File(p.join(staging.path, path)).lengthSync(),
        ),
    ],
    removals:
        removals ??
        [
          SwapRemoval(
            path: 'legacy.dll',
            sha256: _hash(p.join(install.path, 'legacy.dll')),
          ),
        ],
  );

  test('החלפה מוצלחת כותבת את הקבצים החדשים ומסירה את המיושן', () {
    final result = applySwapPlan(plan());

    expect(result.outcome, SwapOutcome.succeeded);
    expect(result.installedFiles, 3);
    expect(
      File(p.join(install.path, 'otzaria.exe')).readAsStringSync(),
      'new binary',
    );
    expect(
      File(p.join(install.path, 'data', 'b.dat')).readAsStringSync(),
      'new b',
    );
    expect(File(p.join(install.path, 'legacy.dll')).existsSync(), isFalse);
    // הקובץ שהוסר שמור בגיבוי ולא נמחק לצמיתות בשלב הזה.
    expect(File(p.join(backup.path, 'legacy.dll')).existsSync(), isTrue);
  });

  test('נתוני המשתמש בשורש ההתקנה אינם נוגעים בהחלפה', () {
    final userFile = p.join(install.path, 'otzaria_data', 'settings.hive');
    applySwapPlan(plan());
    expect(File(userFile).readAsStringSync(), 'mine');
  });

  test('כשל באמצע ההחלפה משחזר את ההתקנה בית-בית', () {
    final before = _hashTree(install);

    final result = applySwapPlan(
      plan(),
      fs: _LockedFileSystem('b.dat'),
    );

    expect(result.outcome, SwapOutcome.rolledBack);
    expect(result.rollbackErrors, isEmpty);
    expect(result.error, contains('locked'));
    expect(_hashTree(install), before);
    expect(
      File(p.join(install.path, 'otzaria.exe')).readAsStringSync(),
      'old binary',
    );
    expect(File(p.join(install.path, 'legacy.dll')).existsSync(), isTrue);
  });

  test('כשל גם בשחזור: corrupted, עם מניין הקבצים שכבר הוחלפו', () {
    final result = applySwapPlan(
      plan(),
      fs: _UnrecoverableFileSystem('b.dat'),
    );

    expect(result.outcome, SwapOutcome.corrupted);
    expect(result.rollbackErrors, isNotEmpty);
    // a.dat כבר הותקן לפני ש-b.dat נכשל — בלי המניין הלוג אינו מראה כמה
    // רחוק הגיעה ההחלפה.
    expect(result.installedFiles, 1);
  });

  test('ה-exe מוחלף אחרון, וההסרות קורות רק אחריו', () {
    final fs = _RecordingFileSystem();
    expect(applySwapPlan(plan(), fs: fs).outcome, SwapOutcome.succeeded);

    final replaced = fs.changes.where((c) => c.startsWith('replace'));
    expect(replaced.last, 'replace otzaria.exe');
    expect(fs.changes.last, 'delete legacy.dll');
  });

  test('כשל ברישום השחזור לכניסה הבאה מבטל לפני כל שינוי', () {
    final before = _hashTree(install);

    final result = applySwapPlan(
      plan(),
      beforeFirstChange: () => throw StateError('registry denied'),
    );

    expect(result.outcome, SwapOutcome.abortedBeforeAnyChange);
    expect(_hashTree(install), before);
    // בלי גיבוי אין עדות להחלפה, ואף שחזור לא "ישלים" עדכון שלא התחיל.
    expect(backup.existsSync(), isFalse);
  });

  test('שורת השחזור בכניסה למערכת מריצה את העותק שמחוץ להתקנה', () {
    const copy = r'C:\Users\a b\AppData\Local\Temp\u1\otzaria_updater.exe';
    const planPath =
        r'C:\Users\a b\AppData\Local\Temp\otzaria_small_update\swap-plan.json';
    final command = logonRecoveryCommand(updaterCopy: copy, planPath: planPath);

    expect(command, startsWith('"$copy" '));
    expect(command, contains('--plan "$planPath"'));
    for (final flag in ['--recover', '--no-relaunch', '--from-temp']) {
      expect(command, contains(flag));
    }
    // RunOnce מתעלם משורת פקודה ארוכה מ-260 תווים.
    expect(command.length, lessThan(260));
    expect(kLogonRecoveryValueName, startsWith('!'));
  });

  test('התקנה חלקית אינה מופעלת מחדש, והמשתמש מקבל את נתיב הגיבוי', () {
    expect(shouldRelaunchAfterSwap(SwapOutcome.corrupted), isFalse);
    for (final outcome in [
      SwapOutcome.succeeded,
      SwapOutcome.rolledBack,
      SwapOutcome.abortedBeforeAnyChange,
    ]) {
      expect(shouldRelaunchAfterSwap(outcome), isTrue);
    }
    expect(corruptedInstallMessage(backup.path), contains(backup.path));
  });

  test('קובץ להסרה שאינו זהה למניפסט עוצר לפני כל שינוי', () {
    final built = plan();
    _write(p.join(install.path, 'legacy.dll'), 'the user replaced this');
    final before = _hashTree(install);

    final result = applySwapPlan(built);

    expect(result.outcome, SwapOutcome.abortedBeforeAnyChange);
    expect(_hashTree(install), before);
  });

  test('קובץ staging שאינו תואם את התוכנית עוצר לפני כל שינוי', () {
    final built = plan();
    _write(p.join(staging.path, 'data', 'a.dat'), 'tampered');
    final before = _hashTree(install);

    final result = applySwapPlan(built);

    expect(result.outcome, SwapOutcome.abortedBeforeAnyChange);
    expect(_hashTree(install), before);
    expect(backup.existsSync(), isFalse);
  });

  test('תיקיית גיבוי בתוך ההתקנה נדחית', () {
    final inside = SwapPlan(
      platform: 'windows',
      architecture: 'x64',
      fromReleaseTag: 'a',
      toReleaseTag: 'b',
      installRoot: install.path,
      stagingRoot: staging.path,
      backupRoot: p.join(install.path, 'backup-inside'),
      files: const [],
      removals: const [],
    );
    expect(
      applySwapPlan(inside).outcome,
      SwapOutcome.abortedBeforeAnyChange,
    );
  });

  group('קובץ נעול', () {
    test('החלפה נדחית לפני כל שינוי כשקובץ יעד מוחזק', () {
      final before = _hashTree(install);

      final result = applySwapPlan(plan(), fs: _HeldFileSystem({'data/a.dat'}));

      expect(result.outcome, SwapOutcome.abortedBeforeAnyChange);
      expect(result.error, contains('held by another process'));
      expect(_hashTree(install), before);
      // ההחלפה נדחתה, ולכן גם אין ממה להתאושש.
      expect(backup.existsSync(), isFalse);
    });

    test('קובץ שנועד להסרה ומוחזק דוחה אף הוא', () {
      final result = applySwapPlan(plan(), fs: _HeldFileSystem({'legacy.dll'}));
      expect(result.outcome, SwapOutcome.abortedBeforeAnyChange);
    });

    test('קובץ שמשתחרר זמן קצר אחרי יציאת אוצריא אינו מבטל את העדכון '
        '(issue #4317)', () {
      final fs = _ReleasingFileSystem('otzaria.exe', heldChecks: 3);

      final released = waitForTargetsReleased(
        plan(),
        fs: fs,
        interval: Duration.zero,
      );
      final result = applySwapPlan(plan(), fs: fs);

      expect(released, isTrue);
      expect(result.outcome, SwapOutcome.succeeded);
      expect(
        File(p.join(install.path, 'otzaria.exe')).readAsStringSync(),
        'new binary',
      );
    });

    test('ההמתנה לשחרור מוגבלת בזמן', () {
      final released = waitForTargetsReleased(
        plan(),
        fs: _HeldFileSystem({'data/a.dat'}),
        timeout: const Duration(milliseconds: 50),
        interval: const Duration(milliseconds: 10),
      );
      expect(released, isFalse);
    });
  });

  group('שחזור החלפה שנקטעה', () {
    /// מדמה מעדכן שנהרג אחרי שהחליף את `otzaria.exe` בלבד.
    SwapPlan halfApplied() {
      final built = plan();
      backup.createSync(recursive: true);
      File(
        p.join(install.path, 'otzaria.exe'),
      ).copySync(p.join(backup.path, 'otzaria.exe'));
      File(
        p.join(staging.path, 'otzaria.exe'),
      ).copySync(p.join(install.path, 'otzaria.exe'));
      return built;
    }

    test('קובץ שכבר הותקן מאומת פעם אחת בלבד בשחזור', () {
      final fs = _CountingHashFileSystem();
      final result = recoverInterruptedSwap(halfApplied(), fs: fs);

      expect(result.outcome, SwapRecovery.completed);
      expect(fs.hashes[p.join(install.path, 'otzaria.exe')], 1);
    });

    test('קובץ מוחזק בידי תהליך חי — לא נוגעים, והגיבוי נשאר', () {
      final built = halfApplied();
      final before = _hashTree(install);

      final result = recoverInterruptedSwap(
        built,
        fs: _HeldFileSystem({'otzaria.exe'}),
      );

      expect(result.outcome, SwapRecovery.busy);
      expect(_hashTree(install), before);
      expect(backup.existsSync(), isTrue);
    });

    test('ללא עדות להחלפה שנקטעה לא נוגעים בדבר', () {
      final before = _hashTree(install);
      final result = recoverInterruptedSwap(plan());

      expect(result.outcome, SwapRecovery.nothingToDo);
      expect(_hashTree(install), before);
    });

    test('כל הקבצים זמינים — ההתקנה מושלמת לגרסה החדשה', () {
      final result = recoverInterruptedSwap(halfApplied());

      expect(result.outcome, SwapRecovery.completed);
      expect(
        File(p.join(install.path, 'otzaria.exe')).readAsStringSync(),
        'new binary',
      );
      expect(
        File(p.join(install.path, 'data', 'a.dat')).readAsStringSync(),
        'new a',
      );
      expect(
        File(p.join(install.path, 'data', 'b.dat')).readAsStringSync(),
        'new b',
      );
      expect(File(p.join(install.path, 'legacy.dll')).existsSync(), isFalse);
      expect(
        File(
          p.join(install.path, 'otzaria_data', 'settings.hive'),
        ).readAsStringSync(),
        'mine',
      );
    });

    test('קובץ staging חסר — ההתקנה חוזרת כולה לגרסה הישנה', () {
      final built = halfApplied();
      File(p.join(staging.path, 'data', 'b.dat')).deleteSync();

      final result = recoverInterruptedSwap(built);

      expect(result.outcome, SwapRecovery.restored);
      expect(
        File(p.join(install.path, 'otzaria.exe')).readAsStringSync(),
        'old binary',
      );
      expect(
        File(p.join(install.path, 'data', 'a.dat')).readAsStringSync(),
        'old a',
      );
      expect(File(p.join(install.path, 'legacy.dll')).existsSync(), isTrue);
    });

    test('קובץ חדש שאין לו גיבוי מוסר בביטול', () {
      _write(p.join(staging.path, 'brandnew.dll'), 'brand new');
      final built = SwapPlan(
        platform: 'windows',
        architecture: 'x64',
        fromReleaseTag: '0.9.97+100',
        toReleaseTag: '0.9.97+101',
        installRoot: install.path,
        stagingRoot: staging.path,
        backupRoot: backup.path,
        files: [
          for (final path in const ['brandnew.dll', 'data/b.dat'])
            SwapFile(
              path: path,
              sha256: _hash(p.join(staging.path, path)),
              size: File(p.join(staging.path, path)).lengthSync(),
            ),
        ],
        removals: const [],
      );
      backup.createSync(recursive: true);
      File(
        p.join(staging.path, 'brandnew.dll'),
      ).renameSync(p.join(install.path, 'brandnew.dll'));
      File(p.join(staging.path, 'data', 'b.dat')).deleteSync();

      final result = recoverInterruptedSwap(built);

      expect(result.outcome, SwapRecovery.restored);
      expect(File(p.join(install.path, 'brandnew.dll')).existsSync(), isFalse);
      expect(
        File(p.join(install.path, 'data', 'b.dat')).readAsStringSync(),
        'old b',
      );
    });

    test('נתוני המשתמש אינם נוגעים בביטול ההחלפה', () {
      final built = halfApplied();
      File(p.join(staging.path, 'data', 'b.dat')).deleteSync();

      recoverInterruptedSwap(built);

      expect(
        File(
          p.join(install.path, 'otzaria_data', 'settings.hive'),
        ).readAsStringSync(),
        'mine',
      );
    });

    test('כשל בשחזור אינו מוחק את הגיבוי', () {
      final built = halfApplied();
      File(p.join(staging.path, 'data', 'b.dat')).deleteSync();

      final result = recoverInterruptedSwap(
        built,
        fs: _LockedFileSystem('otzaria.exe'),
      );

      expect(result.outcome, SwapRecovery.failed);
      expect(File(p.join(backup.path, 'otzaria.exe')).existsSync(), isTrue);
    });
  });

  group('מות התהליך בכל שלב', () {
    late Map<String, String> oldTree;
    late Map<String, String> newTree;
    late List<String> alwaysPresent;

    setUp(() {
      oldTree = _hashTree(install);
      newTree = Map.of(oldTree)..remove('legacy.dll');
      for (final path in const ['otzaria.exe', 'data/a.dat', 'data/b.dat']) {
        newTree[path] = _hash(p.join(staging.path, path));
      }
      alwaysPresent = const ['otzaria.exe', 'data/a.dat', 'data/b.dat'];
    });

    void noTargetMissing() {
      for (final path in alwaysPresent) {
        expect(
          File(p.join(install.path, path)).existsSync(),
          isTrue,
          reason: '$path is missing in an intermediate state',
        );
      }
    }

    /// מספר השינויים שההחלפה המלאה עושה — כל אחד הוא נקודת מוות אפשרית.
    int stepsOf(void Function(SwapFileSystem fs) run) {
      final counter = _CrashingFileSystem(crashAt: 1 << 30, invariant: () {});
      run(counter);
      return counter.mutations;
    }

    void resetTo(Map<String, Map<String, String>> snapshot) {
      for (final root in [install, staging, backup]) {
        if (root.existsSync()) root.deleteSync(recursive: true);
      }
      for (final entry in snapshot.entries) {
        final root = Directory(entry.key)..createSync(recursive: true);
        for (final file in entry.value.entries) {
          _write(p.join(root.path, file.key), file.value);
        }
      }
    }

    Map<String, String> contentsOf(Directory root) => {
      if (root.existsSync())
        for (final entity in root.listSync(recursive: true))
          if (entity is File)
            p.relative(entity.path, from: root.path).replaceAll('\\', '/'):
                entity.readAsStringSync(),
    };

    test('ההתקנה אינה חסרה קובץ, והשחזור מסיים בגרסה אחת שלמה', () {
      final built = plan();
      final pristine = {
        install.path: contentsOf(install),
        staging.path: contentsOf(staging),
      };
      final applySteps = stepsOf((fs) => applySwapPlan(built, fs: fs));
      expect(applySteps, greaterThan(5));

      for (var crash = 0; crash <= applySteps; crash++) {
        resetTo(pristine);
        applySwapPlan(
          built,
          fs: _CrashingFileSystem(crashAt: crash, invariant: noTargetMissing),
        );
        noTargetMissing();
        final crashed = {
          install.path: contentsOf(install),
          staging.path: contentsOf(staging),
          if (backup.existsSync()) backup.path: contentsOf(backup),
        };

        final recoverySteps = stepsOf((fs) {
          resetTo(crashed);
          recoverInterruptedSwap(built, fs: fs);
        });
        // גם השחזור עצמו עלול להיקטע — ושחזור נוסף חייב להשלים אותו.
        for (var second = 0; second <= recoverySteps; second++) {
          resetTo(crashed);
          recoverInterruptedSwap(
            built,
            fs: _CrashingFileSystem(
              crashAt: second,
              invariant: noTargetMissing,
            ),
          );
          noTargetMissing();
          final result = recoverInterruptedSwap(built);

          final tree = _hashTree(install);
          final reason = 'crash at $crash, recovery crash at $second';
          if (crash == applySteps) {
            expect(tree, newTree, reason: reason);
          } else {
            expect(
              _sameTree(tree, oldTree) || _sameTree(tree, newTree),
              isTrue,
              reason: '$reason: ${result.outcome} left a mixed install',
            );
          }
        }
      }
    });

    test('staging שנעלם אחרי המוות — השחזור מחזיר לגרסה הישנה', () {
      final built = plan();
      final pristine = {
        install.path: contentsOf(install),
        staging.path: contentsOf(staging),
      };
      final applySteps = stepsOf((fs) => applySwapPlan(built, fs: fs));

      for (var crash = 0; crash < applySteps; crash++) {
        resetTo(pristine);
        applySwapPlan(
          built,
          fs: _CrashingFileSystem(crashAt: crash, invariant: noTargetMissing),
        );
        final bStillOld =
            _hash(p.join(install.path, 'data', 'b.dat')) ==
            oldTree['data/b.dat'];
        File(p.join(staging.path, 'data', 'b.dat')).deleteSync();

        final result = recoverInterruptedSwap(built);

        final tree = _hashTree(install);
        if (bStillOld) {
          expect(result.outcome, SwapRecovery.restored, reason: '$crash');
          expect(tree, oldTree, reason: 'crash at $crash');
        } else {
          expect(_sameTree(tree, newTree), isTrue, reason: 'crash at $crash');
        }
      }
    });
  });

  group('חלון ההפעלה מחדש', () {
    test('פתוח מיד אחרי היציאה, סגור אחרי שחלף', () {
      final exitedAt = DateTime(2026, 1, 1, 12);
      const window = Duration(minutes: 2);

      expect(
        relaunchWindowStillOpen(
          exitedAt: exitedAt,
          now: exitedAt.add(const Duration(seconds: 30)),
          window: window,
        ),
        isTrue,
      );
      expect(
        relaunchWindowStillOpen(
          exitedAt: exitedAt,
          now: exitedAt.add(const Duration(minutes: 20)),
          window: window,
        ),
        isFalse,
      );
    });
  });

  group('תוכנית ההחלפה', () {
    test('round-trip שומר על כל השדות', () {
      final decoded = SwapPlan.decode(plan().encode());
      expect(decoded.files.map((f) => f.path), [
        'otzaria.exe',
        'data/a.dat',
        'data/b.dat',
      ]);
      expect(decoded.removals.single.path, 'legacy.dll');
      expect(decoded.installRoot, install.path);
      expect(decoded.waitTimeout, const Duration(minutes: 2));
    });

    test('נתיב נתוני משתמש בתוכנית נדחה בקריאה', () {
      final tampered = plan().encode().replaceFirst(
        '"legacy.dll"',
        '"otzaria_data/settings.hive"',
      );
      expect(
        () => SwapPlan.decode(tampered),
        throwsA(isA<SwapPlanException>()),
      );
    });

    test('נתיב מוחלט בתוכנית נדחה בקריאה', () {
      final tampered = plan().encode().replaceFirst(
        '"legacy.dll"',
        '"C:/Windows/System32/kernel32.dll"',
      );
      expect(
        () => SwapPlan.decode(tampered),
        throwsA(isA<SwapPlanException>()),
      );
    });
  });
}
