import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/library_update/repository/library_update_repository.dart';
import 'package:otzaria/library_update/services/companion_assets_service.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

class _FakeService implements LibraryUpdateService {
  final LibraryUpdatePlan plan;
  final bool throwOnCheck;
  final bool throwOnApply;
  bool applyCalled = false;
  bool fullCalled = false;

  _FakeService(
    this.plan, {
    this.throwOnCheck = false,
    this.throwOnApply = false,
  });

  @override
  Future<RecoveryResult> recoverIfNeeded() async =>
      const RecoveryResult(RecoveryAction.none);

  @override
  Future<LibraryUpdatePlan> checkForUpdate({
    required bool allowPrerelease,
  }) async {
    if (throwOnCheck) throw Exception('check failed');
    return plan;
  }

  @override
  Future<Set<int>> applyDeltaPlan(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    applyCalled = true;
    if (throwOnApply) throw Exception('apply failed');
    return {7, 12};
  }

  @override
  Future<void> applyFullDownload(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    fullCalled = true;
    if (throwOnApply) throw Exception('full failed');
  }
}

/// שירות שמדווח על שלב applying ואז נחסם — לבדיקת חסימת ביטול אחרי כתיבת DB.
class _GatedAtApplyService implements LibraryUpdateService {
  final LibraryUpdatePlan plan;
  final Completer<void> gate;
  _GatedAtApplyService(this.plan, this.gate);

  @override
  Future<RecoveryResult> recoverIfNeeded() async =>
      const RecoveryResult(RecoveryAction.none);

  @override
  Future<LibraryUpdatePlan> checkForUpdate({
    required bool allowPrerelease,
  }) async => plan;

  @override
  Future<Set<int>> applyDeltaPlan(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    onProgress?.call(
      const LibraryUpdateProgress(phase: LibraryUpdatePhase.applying),
    );
    await gate
        .future; // מדמה apply ארוך; אחריו ה-DB עודכן — מתעלמים מ-isCancelled
    return const {};
  }

  @override
  Future<void> applyFullDownload(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {}
}

/// שירות שמדמה רצף apply אמיתי: מדידת אימות ואז תת-שלב בלי מדידה — לבדיקת
/// ניקוי applyProgress שאריתי.
class _VerifyThenCommitService implements LibraryUpdateService {
  final LibraryUpdatePlan plan;
  _VerifyThenCommitService(this.plan);

  @override
  Future<RecoveryResult> recoverIfNeeded() async =>
      const RecoveryResult(RecoveryAction.none);

  @override
  Future<LibraryUpdatePlan> checkForUpdate({
    required bool allowPrerelease,
  }) async => plan;

  @override
  Future<Set<int>> applyDeltaPlan(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    onProgress?.call(
      const LibraryUpdateProgress(
        phase: LibraryUpdatePhase.applying,
        stage: 'verifyToHash',
        applyProgress: 0.5,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    onProgress?.call(
      const LibraryUpdateProgress(
        phase: LibraryUpdatePhase.applying,
        stage: 'commit',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return const {};
  }

  @override
  Future<void> applyFullDownload(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {}
}

/// שירות שבו applyDeltaPlan נחסם עד שמשחררים את ה-gate — לבדיקת race של ביטול.
class _GatedService implements LibraryUpdateService {
  final LibraryUpdatePlan plan;
  final Completer<void> gate;
  _GatedService(this.plan, this.gate);

  @override
  Future<RecoveryResult> recoverIfNeeded() async =>
      const RecoveryResult(RecoveryAction.none);

  @override
  Future<LibraryUpdatePlan> checkForUpdate({
    required bool allowPrerelease,
  }) async => plan;

  @override
  Future<Set<int>> applyDeltaPlan(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    await gate.future; // נחסם עד שהבדיקה משחררת
    return const {};
  }

  @override
  Future<void> applyFullDownload(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {}
}

/// שירות נלווים מזויף — רושם קריאות, ואופציונלית זורק או מדווח על שינוי.
class _FakeCompanionService extends CompanionAssetsService {
  _FakeCompanionService({this.throwOnRun = false, this.changed = false});
  final bool throwOnRun;
  final bool changed;
  int calls = 0;

  @override
  Future<bool> verifyAndUpdate({
    void Function(String message)? onStatus,
    void Function(int received, int? total)? onDownloadProgress,
    bool Function()? isCancelled,
  }) async {
    calls++;
    if (throwOnRun) throw Exception('companion failed');
    onStatus?.call('בודק את התלמוד הבבלי');
    return changed;
  }
}

/// שירות נלווים שנחסם עד שחרור ה-gate — לבדיקת ביטול במהלך הריצה שלו.
class _GatedCompanionService extends CompanionAssetsService {
  _GatedCompanionService(this.gate, {this.changed = false});
  final Completer<void> gate;

  /// מדמה תלמוד/קטלוג שכבר שונו לפני שהביטול נקלט — הדגל המצטבר מוחזר.
  final bool changed;

  @override
  Future<bool> verifyAndUpdate({
    void Function(String message)? onStatus,
    void Function(int received, int? total)? onDownloadProgress,
    bool Function()? isCancelled,
  }) async {
    onStatus?.call('מוריד את התלמוד הבבלי');
    await gate.future;
    return changed;
  }
}

/// נלווים לתרחיש race: הקריאה הראשונה נחסמת ומחזירה שינוי (הנכס הוחלף לפני
/// הביטול); השנייה נחסמת ומחזירה false (הנכס כבר מעודכן).
class _RaceCompanionService extends CompanionAssetsService {
  _RaceCompanionService(this.firstGate, this.secondGate);
  final Completer<void> firstGate;
  final Completer<void> secondGate;
  int calls = 0;

  @override
  Future<bool> verifyAndUpdate({
    void Function(String message)? onStatus,
    void Function(int received, int? total)? onDownloadProgress,
    bool Function()? isCancelled,
  }) async {
    calls++;
    if (calls == 1) {
      onStatus?.call('מוריד את התלמוד הבבלי');
      await firstGate.future;
      return true;
    }
    await secondGate.future;
    return false;
  }
}

LibraryUpdateBloc _bloc(
  LibraryUpdateService service, {
  bool offline = false,
  bool updatesEnabled = true,
  bool prerelease = false,
  CompanionAssetsService? companionAssets,
  // ברירת המחדל "מחובר" מונעת גישת רשת אמיתית בבדיקות מסלולי הכשל.
  bool hasInternet = true,
}) => LibraryUpdateBloc(
  repository: service,
  isOfflineMode: () => offline,
  areUpdatesEnabled: () => updatesEnabled,
  allowPrerelease: () => prerelease,
  companionAssets: companionAssets,
  hasInternet: () async => hasInternet,
);

void main() {
  final nonePlan = LibraryUpdatePlan.none(localVersion: 3, targetVersion: 3);
  final deltaPlan = LibraryUpdatePlan.delta(
    localVersion: 1,
    targetVersion: 3,
    steps: const [],
  );
  final fullPlan = LibraryUpdatePlan.fullDownload(
    localVersion: 1,
    targetVersion: 3,
    asset: const ReleaseAsset(
      name: 'seforim.db.zst',
      downloadUrl: 'https://x',
      size: 1200000000,
    ),
    releaseTag: 'v3',
  );
  final blockedPlan = LibraryUpdatePlan.blocked(
    localVersion: 1,
    targetVersion: 3,
    reason: 'schema לא תואם',
  );

  group('LibraryUpdateBloc', () {
    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'מצב לא מקוון → idle עם הודעה, לא בודק',
      build: () => _bloc(_FakeService(nonePlan), offline: true),
      act: (b) => b.add(const StartLibraryUpdate()),
      expect: () => [
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.idle,
        ),
      ],
    );

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'עדכונים מושבתים → idle',
      build: () => _bloc(_FakeService(nonePlan), updatesEnabled: false),
      act: (b) => b.add(const StartLibraryUpdate()),
      expect: () => [
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.idle,
        ),
      ],
    );

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'plan none → completed בלי hasUpdate',
      build: () => _bloc(_FakeService(nonePlan)),
      act: (b) => b.add(const StartLibraryUpdate()),
      expect: () => [
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.checking,
        ),
        isA<LibraryUpdateState>()
            .having((s) => s.status, 'status', LibraryUpdateStatus.completed)
            .having((s) => s.hasUpdate, 'hasUpdate', false),
      ],
    );

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'plan delta → מבצע apply ומסיים עם hasUpdate',
      build: () => _bloc(_FakeService(deltaPlan)),
      act: (b) => b.add(const StartLibraryUpdate()),
      verify: (b) => expect((b.repository as _FakeService).applyCalled, isTrue),
      expect: () => [
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.checking,
        ),
        isA<LibraryUpdateState>()
            .having((s) => s.status, 'status', LibraryUpdateStatus.completed)
            .having((s) => s.hasUpdate, 'hasUpdate', true),
      ],
    );

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'plan fullDownload → needsFullConfirmation עם plan',
      build: () => _bloc(_FakeService(fullPlan)),
      act: (b) => b.add(const StartLibraryUpdate()),
      verify: (b) =>
          expect((b.repository as _FakeService).applyCalled, isFalse),
      expect: () => [
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.checking,
        ),
        isA<LibraryUpdateState>()
            .having(
              (s) => s.status,
              'status',
              LibraryUpdateStatus.needsFullConfirmation,
            )
            .having((s) => s.plan, 'plan', isNotNull),
      ],
    );

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'plan blocked → blocked',
      build: () => _bloc(_FakeService(blockedPlan)),
      act: (b) => b.add(const StartLibraryUpdate()),
      expect: () => [
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.checking,
        ),
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.blocked,
        ),
      ],
    );

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'שגיאה בבדיקה → error',
      build: () => _bloc(_FakeService(nonePlan, throwOnCheck: true)),
      act: (b) => b.add(const StartLibraryUpdate()),
      expect: () => [
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.checking,
        ),
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.error,
        ),
      ],
    );

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'שגיאה ב-apply → error',
      build: () => _bloc(_FakeService(deltaPlan, throwOnApply: true)),
      act: (b) => b.add(const StartLibraryUpdate()),
      expect: () => [
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.checking,
        ),
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.error,
        ),
      ],
    );

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'כשל בבדיקה בלי אינטרנט → מנותק ולא שגיאה',
      build: () =>
          _bloc(_FakeService(nonePlan, throwOnCheck: true), hasInternet: false),
      act: (b) => b.add(const StartLibraryUpdate()),
      expect: () => [
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.checking,
        ),
        isA<LibraryUpdateState>()
            .having((s) => s.status, 'status', LibraryUpdateStatus.disconnected)
            .having((s) => s.message, 'message', 'אין חיבור לאינטרנט')
            .having((s) => s.errorMessage, 'errorMessage', isNull),
      ],
    );

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'כשל ב-apply בלי אינטרנט נשאר שגיאה מקומית',
      build: () => _bloc(
        _FakeService(deltaPlan, throwOnApply: true),
        hasInternet: false,
      ),
      act: (b) => b.add(const StartLibraryUpdate()),
      expect: () => [
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.checking,
        ),
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.error,
        ),
      ],
    );

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'כשל בהורדה מלאה בלי אינטרנט נשאר שגיאה מקומית',
      build: () =>
          _bloc(_FakeService(fullPlan, throwOnApply: true), hasInternet: false),
      seed: () => LibraryUpdateState(
        status: LibraryUpdateStatus.needsFullConfirmation,
        plan: fullPlan,
      ),
      act: (b) => b.add(const ConfirmFullDownload()),
      expect: () => [
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.downloading,
        ),
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.error,
        ),
      ],
    );

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'מצב מנותק אינו חוסם ניסיון חוזר — לחיצה מתחילה בדיקה חדשה',
      build: () => _bloc(_FakeService(nonePlan)),
      seed: () =>
          const LibraryUpdateState(status: LibraryUpdateStatus.disconnected),
      act: (b) => b.add(const StartLibraryUpdate()),
      expect: () => [
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.checking,
        ),
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.completed,
        ),
      ],
    );

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'חזרת החיבור אחרי ניתוק → העדכון מתבצע ומצב המנותק נעלם',
      build: () => _bloc(_FakeService(deltaPlan)),
      seed: () =>
          const LibraryUpdateState(status: LibraryUpdateStatus.disconnected),
      act: (b) => b.add(const StartLibraryUpdate()),
      verify: (b) {
        expect((b.repository as _FakeService).applyCalled, isTrue);
        expect(b.state.status, LibraryUpdateStatus.completed);
        expect(b.state.hasUpdate, isTrue);
      },
    );

    test('מצב מנותק אינו busy — לא מוצג כעבודה פעילה', () {
      const state = LibraryUpdateState(
        status: LibraryUpdateStatus.disconnected,
      );
      expect(state.isBusy, isFalse);
    });

    test('בדיקת החיבור נקראת רק אחרי כשל, לא במסלול התקין', () async {
      var probes = 0;
      final bloc = LibraryUpdateBloc(
        repository: _FakeService(nonePlan),
        isOfflineMode: () => false,
        areUpdatesEnabled: () => true,
        allowPrerelease: () => false,
        hasInternet: () async {
          probes++;
          return true;
        },
      );
      bloc.add(const StartLibraryUpdate());
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(bloc.state.status, LibraryUpdateStatus.completed);
      expect(probes, 0, reason: 'בדיקת רשת עולה זמן — אסור במסלול המוצלח');
      await bloc.close();
    });

    test('כשל אחרי סגירת ה-bloc אינו פולט state', () async {
      final probeGate = Completer<bool>();
      final bloc = LibraryUpdateBloc(
        repository: _FakeService(nonePlan, throwOnCheck: true),
        isOfflineMode: () => false,
        areUpdatesEnabled: () => true,
        allowPrerelease: () => false,
        hasInternet: () => probeGate.future,
      );
      bloc.add(const StartLibraryUpdate());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await bloc.close();
      probeGate.complete(false); // הבדיקה חוזרת אחרי הסגירה
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bloc.state.status, LibraryUpdateStatus.checking);
    });

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'ConfirmFullDownload → מבצע הורדה מלאה ומסיים עם hasUpdate',
      build: () => _bloc(_FakeService(fullPlan)),
      seed: () => LibraryUpdateState(
        status: LibraryUpdateStatus.needsFullConfirmation,
        plan: fullPlan,
      ),
      act: (b) => b.add(const ConfirmFullDownload()),
      verify: (b) => expect((b.repository as _FakeService).fullCalled, isTrue),
      expect: () => [
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.downloading,
        ),
        isA<LibraryUpdateState>()
            .having((s) => s.status, 'status', LibraryUpdateStatus.completed)
            .having((s) => s.hasUpdate, 'hasUpdate', true),
      ],
    );

    test(
      'ביטול במהלך עדכון → ריצה ישנה לא פולטת completed (operation token)',
      () async {
        final gate = Completer<void>();
        final bloc = _bloc(_GatedService(deltaPlan, gate));
        final seen = <LibraryUpdateStatus>[];
        final sub = bloc.stream.listen((s) => seen.add(s.status));

        bloc.add(const StartLibraryUpdate());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        // הריצה תקועה ב-applyDeltaPlan (gate). מבטלים ומתחילים מחדש מושגית.
        bloc.add(const CancelLibraryUpdate());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(bloc.state.status, LibraryUpdateStatus.idle);

        gate.complete(); // הריצה הישנה ממשיכה — אך opId כבר התיישן
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          seen.contains(LibraryUpdateStatus.completed),
          isFalse,
          reason: 'ריצה שבוטלה לא אמורה לפלוט completed',
        );
        expect(bloc.state.status, LibraryUpdateStatus.idle);
        await sub.cancel();
        await bloc.close();
      },
    );

    test(
      'ביטול בשלב applying (דלתא) נחסם — ה-DB עודכן ולכן פולט completed',
      () async {
        final gate = Completer<void>();
        final bloc = _bloc(_GatedAtApplyService(deltaPlan, gate));
        final seen = <LibraryUpdateStatus>[];
        final sub = bloc.stream.listen((s) => seen.add(s.status));

        bloc.add(const StartLibraryUpdate());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(bloc.state.status, LibraryUpdateStatus.applying);

        // ניסיון ביטול אחרי שהחלה ל-DB התחילה — חייב להיחסם.
        bloc.add(const CancelLibraryUpdate());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          bloc.state.status,
          LibraryUpdateStatus.applying,
          reason: 'ביטול בשלב applying אמור להיחסם',
        );

        gate.complete(); // ה-apply מסתיים, ה-DB עודכן
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(bloc.state.status, LibraryUpdateStatus.completed);
        expect(
          bloc.state.hasUpdate,
          isTrue,
          reason: 'עדכון שהושלם חייב להפעיל ריענון ספרייה/אינדוקס',
        );
        expect(
          seen.contains(LibraryUpdateStatus.idle),
          isFalse,
          reason: 'ביטול שנחסם לא אמור להחזיר ל-idle',
        );
        await sub.cancel();
        await bloc.close();
      },
    );

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'הקבצים הנלווים נבדקים אחרי עדכון דלתא, לפני completed',
      build: () => _bloc(
        _FakeService(deltaPlan),
        companionAssets: _FakeCompanionService(),
      ),
      act: (b) => b.add(const StartLibraryUpdate()),
      verify: (b) =>
          expect((b.companionAssets as _FakeCompanionService).calls, 1),
      expect: () => [
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.checking,
        ),
        isA<LibraryUpdateState>().having(
          (s) => s.message,
          'message',
          'בודק את התלמוד הבבלי',
        ),
        isA<LibraryUpdateState>()
            .having((s) => s.status, 'status', LibraryUpdateStatus.completed)
            .having((s) => s.hasUpdate, 'hasUpdate', true),
      ],
    );

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'הקבצים הנלווים נבדקים גם כשאין עדכון (plan none)',
      build: () => _bloc(
        _FakeService(nonePlan),
        companionAssets: _FakeCompanionService(),
      ),
      act: (b) => b.add(const StartLibraryUpdate()),
      verify: (b) =>
          expect((b.companionAssets as _FakeCompanionService).calls, 1),
      expect: () => [
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.checking,
        ),
        isA<LibraryUpdateState>().having(
          (s) => s.message,
          'message',
          'בודק את התלמוד הבבלי',
        ),
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.completed,
        ),
      ],
    );

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'plan none אך הנלווים עדכנו בפועל → completed עם hasUpdate (ריענון)',
      build: () => _bloc(
        _FakeService(nonePlan),
        companionAssets: _FakeCompanionService(changed: true),
      ),
      act: (b) => b.add(const StartLibraryUpdate()),
      expect: () => [
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.checking,
        ),
        isA<LibraryUpdateState>().having(
          (s) => s.message,
          'message',
          'בודק את התלמוד הבבלי',
        ),
        isA<LibraryUpdateState>()
            .having((s) => s.status, 'status', LibraryUpdateStatus.completed)
            .having((s) => s.hasUpdate, 'hasUpdate', true),
      ],
    );

    test(
      'plan none: ביטול בזמן הנלווים שכבר שינו את הספרייה → completed עם hasUpdate',
      () async {
        final gate = Completer<void>();
        final bloc = _bloc(
          _FakeService(nonePlan),
          companionAssets: _GatedCompanionService(gate, changed: true),
        );

        bloc.add(const StartLibraryUpdate());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(bloc.state.message, 'מוריד את התלמוד הבבלי');
        bloc.add(const CancelLibraryUpdate());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(bloc.state.message, 'העדכון בוטל');

        // השירות מחזיר את הדגל המצטבר — תלמוד/קטלוג כבר שונו לפני הביטול.
        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(bloc.state.status, LibraryUpdateStatus.completed);
        expect(
          bloc.state.hasUpdate,
          isTrue,
          reason: 'הספרייה כבר השתנתה — ביטול לא יכול לאבד את הריענון/אינדוקס',
        );
        await bloc.close();
      },
    );

    test(
      'plan none: ביטול והתחלה מיידית של ריצה חדשה → השינוי מהריצה שבוטלה מדווח',
      () async {
        final firstGate = Completer<void>();
        final secondGate = Completer<void>();
        final bloc = _bloc(
          _FakeService(nonePlan),
          companionAssets: _RaceCompanionService(firstGate, secondGate),
        );

        bloc.add(const StartLibraryUpdate());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(bloc.state.message, 'מוריד את התלמוד הבבלי');
        bloc.add(const CancelLibraryUpdate());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(bloc.state.message, 'העדכון בוטל');

        // המשתמש לוחץ שוב "עדכון" לפני שהריצה הישנה חזרה — הריצה החדשה busy.
        bloc.add(const StartLibraryUpdate());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(bloc.state.isBusy, isTrue);

        // הריצה הישנה חוזרת עם שינוי, אך לא פולטת כי הריצה החדשה busy.
        firstGate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(bloc.state.isBusy, isTrue);

        // הריצה החדשה רואה את הנכס כבר מעודכן — אך חייבת לדווח את השינוי השמור.
        secondGate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(bloc.state.status, LibraryUpdateStatus.completed);
        expect(
          bloc.state.hasUpdate,
          isTrue,
          reason:
              'הספרייה השתנתה בריצה שבוטלה — הריענון/אינדוקס לא יכולים ללכת לאיבוד',
        );
        await bloc.close();
      },
    );

    test(
      'plan none: ביטול בזמן נלווים שלא שינו דבר → נשאר מבוטל, בלי completed',
      () async {
        final gate = Completer<void>();
        final bloc = _bloc(
          _FakeService(nonePlan),
          companionAssets: _GatedCompanionService(gate),
        );

        bloc.add(const StartLibraryUpdate());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        bloc.add(const CancelLibraryUpdate());
        await Future<void>.delayed(const Duration(milliseconds: 20));

        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(bloc.state.status, LibraryUpdateStatus.idle);
        expect(
          bloc.state.message,
          'העדכון בוטל',
          reason: 'שום דבר לא השתנה — אין לפלוט completed מריצה שבוטלה',
        );
        await bloc.close();
      },
    );

    test(
      'ביטול בשלב הנלווים אחרי עדכון דלתא → עדיין completed עם hasUpdate',
      () async {
        final gate = Completer<void>();
        final bloc = _bloc(
          _FakeService(deltaPlan),
          companionAssets: _GatedCompanionService(gate),
        );
        final seen = <LibraryUpdateStatus>[];
        final sub = bloc.stream.listen((s) => seen.add(s.status));

        bloc.add(const StartLibraryUpdate());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        // ה-DB כבר עודכן; הריצה תקועה בהורדת הנלווים והמשתמש מבטל.
        expect(bloc.state.message, 'מוריד את התלמוד הבבלי');
        bloc.add(const CancelLibraryUpdate());
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(bloc.state.status, LibraryUpdateStatus.completed);
        expect(
          bloc.state.hasUpdate,
          isTrue,
          reason: 'ה-DB הוחלף — ביטול הנלווים לא יכול לאבד את הריענון/אינדוקס',
        );
        expect(seen.contains(LibraryUpdateStatus.idle), isFalse);

        gate.complete(); // הריצה הישנה מסתיימת — לא דורסת את ה-state
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(bloc.state.status, LibraryUpdateStatus.completed);
        await sub.cancel();
        await bloc.close();
      },
    );

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'כשל בקבצים הנלווים לא מפיל את העדכון — עדיין completed',
      build: () => _bloc(
        _FakeService(deltaPlan),
        companionAssets: _FakeCompanionService(throwOnRun: true),
      ),
      act: (b) => b.add(const StartLibraryUpdate()),
      expect: () => [
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.checking,
        ),
        isA<LibraryUpdateState>()
            .having((s) => s.status, 'status', LibraryUpdateStatus.completed)
            .having((s) => s.hasUpdate, 'hasUpdate', true),
      ],
    );

    test('אירוע stage בלי מדידה מנקה applyProgress שאריתי מהאימות', () async {
      final bloc = _bloc(_VerifyThenCommitService(deltaPlan));
      final seen = <LibraryUpdateState>[];
      final sub = bloc.stream.listen(seen.add);

      bloc.add(const StartLibraryUpdate());
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final applying = seen
          .where((s) => s.status == LibraryUpdateStatus.applying)
          .toList();
      expect(applying, hasLength(2));
      expect(applying[0].applyProgress, 0.5);
      expect(
        applying[1].applyProgress,
        isNull,
        reason:
            'commit ללא מדידה חייב לנקות את אחוז האימות הקודם, '
            'אחרת המד מציג ערך שאריתי',
      );
      await sub.cancel();
      await bloc.close();
    });

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'StartLibraryUpdate בזמן busy → מתעלם (guard נגד עדכון כפול)',
      build: () => _bloc(_FakeService(deltaPlan)),
      seed: () =>
          const LibraryUpdateState(status: LibraryUpdateStatus.checking),
      act: (b) => b.add(const StartLibraryUpdate()),
      verify: (b) =>
          expect((b.repository as _FakeService).applyCalled, isFalse),
      expect: () => const <LibraryUpdateState>[],
    );

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'DeclineFullDownload → ממשיך עם הנוכחי, בלי הורדה',
      build: () => _bloc(_FakeService(fullPlan)),
      seed: () => LibraryUpdateState(
        status: LibraryUpdateStatus.needsFullConfirmation,
        plan: fullPlan,
      ),
      act: (b) => b.add(const DeclineFullDownload()),
      verify: (b) => expect((b.repository as _FakeService).fullCalled, isFalse),
      expect: () => [
        isA<LibraryUpdateState>()
            .having((s) => s.status, 'status', LibraryUpdateStatus.completed)
            .having((s) => s.hasUpdate, 'hasUpdate', false),
      ],
    );
  });
}
