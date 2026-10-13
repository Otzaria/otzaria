import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/data/data_providers/catalogue_order_revision.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/indexing/models/index_update_mode.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:path/path.dart' as p;

void main() {
  group('TantivyDataProvider.migratePersonalOrderRange', () {
    late Directory dir;
    late _MigrationEngine engine;
    late Set<String> indexed;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('personal_range_');
      engine = _MigrationEngine();
      indexed = {'id:1', 'uid:1', 'uid:2'};
      WindowRole.isSecondary = false;
    });

    tearDown(() {
      WindowRole.isSecondary = false;
      dir.deleteSync(recursive: true);
    });

    Future<void> migrate({
      IndexUpdateMode mode = IndexUpdateMode.all,
      String? indexPath,
    }) => TantivyDataProvider.migratePersonalOrderRange(
      engine,
      indexPath ?? dir.path,
      indexed,
      mode: () => mode,
    );

    test('מוחק פעם אחת את רשומות uid: וחותם', () async {
      await migrate();
      expect(engine.deleted, [
        ['uid:1', 'uid:2'],
      ]);
      expect(engine.commits, 1);
      expect(indexed, {'id:1'});
      expect(CatalogueOrderRevision.hasPersonalOrderRange(dir.path), isTrue);

      indexed.add('uid:1');
      await migrate();
      expect(engine.deleted, hasLength(1));
    });

    test('חלון משני אינו נוגע באינדקס', () async {
      WindowRole.isSecondary = true;
      await migrate();
      expect(engine.deleted, isEmpty);
      expect(CatalogueOrderRevision.hasPersonalOrderRange(dir.path), isFalse);
    });

    test('עדכון אוטומטי כבוי: נדחה בלי מחיקה ובלי חותם', () async {
      await migrate(mode: IndexUpdateMode.off);
      expect(engine.deleted, isEmpty);
      expect(indexed, contains('uid:1'));
      expect(CatalogueOrderRevision.hasPersonalOrderRange(dir.path), isFalse);
    });

    test('אינדקס בלי ספרים אישיים נחתם גם כשהעדכון כבוי', () async {
      indexed = {'id:1'};
      await migrate(mode: IndexUpdateMode.off);
      expect(engine.deleted, isEmpty);
      expect(CatalogueOrderRevision.hasPersonalOrderRange(dir.path), isTrue);
    });

    test('כשל בכתיבת החותם: אין מחיקה', () async {
      final blocker = File(p.join(dir.path, 'file'))..writeAsStringSync('');
      await migrate(indexPath: p.join(blocker.path, 'index'));
      expect(engine.deleted, isEmpty);
      expect(indexed, contains('uid:1'));
    });

    test('כשל במחיקה: rollback, והחותם חוזר לנסות בהפעלה הבאה', () async {
      engine.failCommit = true;
      await migrate();
      expect(engine.rollbacks, 1);
      expect(indexed, contains('uid:1'));
      expect(CatalogueOrderRevision.hasPersonalOrderRange(dir.path), isFalse);
    });
  });

  group('TantivyDataProvider.isRebuildRequiredStatus', () {
    test('מחזיר true כשהאינדקס ישן מדי עבור המנוע (rebuild_required)', () {
      expect(
        TantivyDataProvider.isRebuildRequiredStatus('rebuild_required'),
        isTrue,
      );
    });

    test('מחזיר true כשהאינדקס נוצר ע"י מנוע חדש יותר (engine_too_old)', () {
      expect(
        TantivyDataProvider.isRebuildRequiredStatus('engine_too_old'),
        isTrue,
      );
    });

    test('מחזיר false לאינדקס תקין', () {
      expect(
        TantivyDataProvider.isRebuildRequiredStatus('compatible'),
        isFalse,
      );
      expect(
        TantivyDataProvider.isRebuildRequiredStatus('legacy_compatible'),
        isFalse,
      );
    });

    test('מחזיר false כשאין אינדקס - אינדוקס רגיל יבנה אותו', () {
      expect(
        TantivyDataProvider.isRebuildRequiredStatus('missing_index'),
        isFalse,
      );
    });

    test('מחזיר false כשבדיקת התאימות לא רצה (null)', () {
      expect(TantivyDataProvider.isRebuildRequiredStatus(null), isFalse);
    });
  });

  group('TantivyDataProvider — סנטינל פתיחת המנוע', () {
    test('תוכן מספרי נקרא כמספר הכשלונות', () {
      expect(TantivyDataProvider.sentinelFailedAttempts('1'), 1);
      expect(TantivyDataProvider.sentinelFailedAttempts(' 2 '), 2);
    });

    test('פורמט ישן (תאריך) או תוכן לא קריא — נספר ככישלון יחיד', () {
      // סנטינל מגרסה קודמת שמר DateTime; חובה שלא ייחשב כשני כשלונות
      // (ניגוב מיידי) אלא יקבל ניסיון פתיחה נוסף.
      expect(
        TantivyDataProvider.sentinelFailedAttempts('2026-07-20 10:00:00.000'),
        1,
      );
      expect(TantivyDataProvider.sentinelFailedAttempts(null), 1);
      expect(TantivyDataProvider.sentinelFailedAttempts(''), 1);
    });

    test('האינדקס מוזז הצידה רק אחרי שני כשלונות רצופים', () {
      // רגרסיה: כישלון בודד (למשל kill של המשתמש בזמן האתחול) ניגב מיד
      // אינדקס תקין של שעות עבודה.
      expect(TantivyDataProvider.shouldDiscardIndex(0), isFalse);
      expect(TantivyDataProvider.shouldDiscardIndex(1), isFalse);
      expect(TantivyDataProvider.shouldDiscardIndex(2), isTrue);
      expect(TantivyDataProvider.shouldDiscardIndex(3), isTrue);
    });
  });

  group('ReopenGate', () {
    test('force בזמן reopen רץ — ממתין לו ואז פותח פתיחה חדשה משלו', () async {
      // רגרסיה: force שהסתפק ב-reopen שכבר רץ קיבל פתיחה שהתחילה לפני
      // הכשל — והיא עלולה הייתה לקרוא מהדיסק מצב ישן ולהשאיר מעקב מעופש.
      final gate = ReopenGate();
      final firstStarted = Completer<void>();
      final firstRelease = Completer<void>();
      final log = <String>[];

      final first = gate.run(() async {
        log.add('start-1');
        firstStarted.complete();
        await firstRelease.future;
        log.add('end-1');
      });
      await firstStarted.future;

      final forced = gate.run(() async {
        log.add('start-2');
      }, force: true);

      // הפתיחה הכפויה ממתינה — היא לא מתחילה לפני שהראשונה הסתיימה.
      await Future<void>.delayed(Duration.zero);
      expect(log, ['start-1']);

      firstRelease.complete();
      expect(await first, isTrue);
      expect(await forced, isTrue);
      expect(log, ['start-1', 'end-1', 'start-2']);
    });

    test(
      'בלי force בזמן reopen רץ — ממתין ומחזיר true בלי פתיחה שנייה',
      () async {
        final gate = ReopenGate();
        final release = Completer<void>();
        var calls = 0;

        final first = gate.run(() async {
          calls++;
          await release.future;
        });
        final second = gate.run(() async {
          calls++;
        });

        release.complete();
        expect(await first, isTrue);
        expect(await second, isTrue);
        expect(calls, 1);
      },
    );

    test('קריאה שנייה בתוך 5 שניות מדולגת (false) — אלא אם force', () async {
      final gate = ReopenGate();
      var calls = 0;

      expect(await gate.run(() async => calls++), isTrue);
      expect(await gate.run(() async => calls++), isFalse);
      expect(calls, 1);
      expect(await gate.run(() async => calls++, force: true), isTrue);
      expect(calls, 2);
    });

    test(
      'force אחרי reopen רץ שנכשל — לא יורש את כשלו ופותח פתיחה חדשה',
      () async {
        final gate = ReopenGate();
        final release = Completer<void>();
        var forcedRan = false;

        final first = gate.run(() async {
          await release.future;
          throw StateError('reopen failed');
        });
        final forced = gate.run(() async {
          forcedRan = true;
        }, force: true);

        release.complete();
        await expectLater(first, throwsStateError);
        expect(await forced, isTrue);
        expect(forcedRan, isTrue);
      },
    );

    test(
      'reopen שנכשל בלי ממתין מקביל — לא מדליף unhandled async error',
      () async {
        // רגרסיה: העותק העטוף שנשמר ב-_inFlight ירש את השגיאה, וכשאיש לא
        // המתין לו היא דווחה כשגיאה אסינכרונית לא-מטופלת.
        final gate = ReopenGate();

        await expectLater(
          gate.run(() async => throw StateError('reopen failed')),
          throwsStateError,
        );
        // ניקוז תור המיקרוטסקים — שגיאה לא-מטופלת הייתה מפילה את הבדיקה.
        await Future<void>.delayed(Duration.zero);
      },
    );
  });

  group('TantivyDataProvider.isQuarantinedIndexSiblingName', () {
    test('מזהה תיקיות _corrupted_ ו-_new_ של האינדקס הפעיל', () {
      expect(
        TantivyDataProvider.isQuarantinedIndexSiblingName(
          'index_corrupted_123',
          'index',
        ),
        isTrue,
      );
      expect(
        TantivyDataProvider.isQuarantinedIndexSiblingName(
          'index_new_456',
          'index',
        ),
        isTrue,
      );
    });

    test('לא מזהה את תיקיית האינדקס הפעילה עצמה או תיקיות לא-קשורות', () {
      expect(
        TantivyDataProvider.isQuarantinedIndexSiblingName('index', 'index'),
        isFalse,
      );
      expect(
        TantivyDataProvider.isQuarantinedIndexSiblingName(
          'index_backup',
          'index',
        ),
        isFalse,
      );
      expect(
        TantivyDataProvider.isQuarantinedIndexSiblingName(
          'other_index_corrupted_123',
          'index',
        ),
        isFalse,
      );
    });
  });

  group('TantivyDataProvider.deleteQuarantinedIndexSiblings', () {
    test(
      'מוחק תיקיות _corrupted_/_new_ ליד האינדקס ומשאירה תיקיות אחרות',
      () async {
        // רגרסיה ל-issue #835 (BUG-07): תיקיות שהוזזו הצידה ב-_initEngine
        // בכשל פתיחה כפול נשארו לנצח ותפחו לגדלים של GB-ים.
        final parent = Directory.systemTemp.createTempSync(
          'otzaria_index_gc_test_',
        );
        addTearDown(() {
          if (parent.existsSync()) parent.deleteSync(recursive: true);
        });

        final indexPath = '${parent.path}/index';
        Directory(indexPath).createSync(recursive: true);
        final corrupted = Directory('${indexPath}_corrupted_111')
          ..createSync(recursive: true);
        final orphanedNew = Directory('${indexPath}_new_222')
          ..createSync(recursive: true);
        final unrelated = Directory('${parent.path}/other_index_corrupted_1')
          ..createSync(recursive: true);

        await TantivyDataProvider.deleteQuarantinedIndexSiblings(indexPath);

        expect(Directory(indexPath).existsSync(), isTrue);
        expect(corrupted.existsSync(), isFalse);
        expect(orphanedNew.existsSync(), isFalse);
        expect(unrelated.existsSync(), isTrue);
      },
    );

    test('לא זורק כשתיקיית ההורה לא קיימת', () async {
      final missingParent =
          '${Directory.systemTemp.path}'
          '/otzaria_missing_${DateTime.now().microsecondsSinceEpoch}';
      await expectLater(
        TantivyDataProvider.deleteQuarantinedIndexSiblings(
          '$missingParent/index',
        ),
        completes,
      );
    });

    test('אינו מוחק fallback פעיל מסוג _new_', () async {
      final parent = Directory.systemTemp.createTempSync(
        'otzaria_active_fallback_gc_test_',
      );
      addTearDown(() async {
        if (parent.existsSync()) await parent.delete(recursive: true);
      });

      final indexPath = '${parent.path}/index';
      final activeFallback = Directory('${indexPath}_new_222')
        ..createSync(recursive: true);
      final staleFallback = Directory('${indexPath}_new_111')
        ..createSync(recursive: true);
      final corrupted = Directory('${indexPath}_corrupted_333')
        ..createSync(recursive: true);

      await TantivyDataProvider.deleteQuarantinedIndexSiblings(
        indexPath,
        activeIndexPath: activeFallback.path,
      );

      expect(activeFallback.existsSync(), isTrue);
      expect(staleFallback.existsSync(), isFalse);
      expect(corrupted.existsSync(), isFalse);
    });
  });

  group('RetryableInit', () {
    test('ensure מחזיר את אותו ניסיון כל עוד הוא לא נכשל', () async {
      var calls = 0;
      final slot = RetryableInit<int>();
      Future<int> create() async {
        calls++;
        return 7;
      }

      final first = slot.ensure(create);
      final second = slot.ensure(create);

      expect(identical(first, second), isTrue);
      expect(await first, 7);
      expect(calls, 1);
    });

    test('ניסיון שנכשל אינו נשמר — הגישה הבאה פותחת מחדש ומצליחה', () async {
      var calls = 0;
      final slot = RetryableInit<int>();
      Future<int> create() async {
        calls++;
        if (calls == 1) throw StateError('index locked');
        return 42;
      }

      await expectLater(slot.ensure(create), throwsStateError);
      // הניקוי קורה במיקרו-טסק שאחרי הכשל
      await Future<void>.delayed(Duration.zero);

      expect(slot.current, isNull);
      expect(await slot.ensure(create), 42);
      expect(calls, 2);
    });

    test('כשל שאיש אינו ממתין לו אינו מדווח כשגיאה לא-מטופלת', () async {
      final slot = RetryableInit<int>();
      slot.start(() async => throw StateError('boom'));

      await Future<void>.delayed(Duration.zero);

      expect(slot.current, isNull);
    });
  });
}

class _MigrationEngine implements SearchEngine {
  final deleted = <List<String>>[];
  var commits = 0;
  var rollbacks = 0;
  var failCommit = false;

  @override
  Future<void> deleteDocumentsByFilePaths({
    required List<String> filePaths,
  }) async => deleted.add(filePaths);

  @override
  Future<void> commit() async {
    if (failCommit) throw StateError('commit');
    commits++;
  }

  @override
  Future<void> rollback() async => rollbacks++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
