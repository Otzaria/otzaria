import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/library_update/repository/library_update_repository.dart';
import 'package:otzaria/library_update/services/companion_assets_service.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

class _FakeService implements LibraryUpdateService {
  final LibraryUpdatePlan plan;
  final bool throwOnCheck;
  final bool throwOnApply;

  /// שגיאה ספציפית לזריקה מ-applyDeltaPlan (קודמת ל-[throwOnApply]).
  final Object? applyError;
  bool applyCalled = false;
  bool fullCalled = false;

  _FakeService(
    this.plan, {
    this.throwOnCheck = false,
    this.throwOnApply = false,
    this.applyError,
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
  Future<LibraryDeltaApplyResult> applyDeltaPlan(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    applyCalled = true;
    if (applyError != null) throw applyError!;
    if (throwOnApply) throw Exception('apply failed');
    return const LibraryDeltaApplyResult(changedBookIds: {7, 12});
  }

  @override
  Future<void> applyFullDownload(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    FullDbReplacedCallback? onDbReplaced,
    bool Function()? isCancelled,
  }) async {
    fullCalled = true;
    if (throwOnApply) throw Exception('full failed');
  }
}

class _FullVerifyingService extends _FakeService {
  _FullVerifyingService(super.plan);

  @override
  Future<void> applyFullDownload(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    FullDbReplacedCallback? onDbReplaced,
    bool Function()? isCancelled,
  }) async {
    fullCalled = true;
    onProgress?.call(
      const LibraryUpdateProgress(phase: LibraryUpdatePhase.verifying),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _CancellableFullService extends _FakeService {
  _CancellableFullService(super.plan, this.gate);

  final Completer<void> gate;

  @override
  Future<void> applyFullDownload(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    FullDbReplacedCallback? onDbReplaced,
    bool Function()? isCancelled,
  }) async {
    fullCalled = true;
    await gate.future;
    if (isCancelled?.call() ?? false) {
      throw const PatchDownloadCancelled();
    }
  }
}

class _FullRefreshFailingService extends _FakeService {
  _FullRefreshFailingService(super.plan);

  @override
  Future<void> applyFullDownload(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    FullDbReplacedCallback? onDbReplaced,
    bool Function()? isCancelled,
  }) async {
    fullCalled = true;
    onDbReplaced?.call();
    onProgress?.call(
      const LibraryUpdateProgress(phase: LibraryUpdatePhase.refreshing),
    );
    await Future<void>.delayed(Duration.zero);
    throw Exception('runtime refresh failed after DB replacement');
  }
}

class _GatedAfterFullReplacementService extends _FakeService {
  _GatedAfterFullReplacementService(super.plan, this.gate);

  final Completer<void> gate;

  @override
  Future<void> applyFullDownload(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    FullDbReplacedCallback? onDbReplaced,
    bool Function()? isCancelled,
  }) async {
    fullCalled = true;
    // repository אמיתי מדווח commit מיד אחרי rename, ורק אחרי reopen מדווח
    // refreshing. ה-gate מדמה את חלון ה-reopen שביניהם.
    onDbReplaced?.call();
    await gate.future;
    onProgress?.call(
      const LibraryUpdateProgress(phase: LibraryUpdatePhase.refreshing),
    );
  }
}

/// שירות שמדמה הורדה המדווחת התקדמות על כל chunk — לבדיקת ויסות ההצפה.
class _ChunkFloodService extends _FakeService {
  final void Function(int chunk)? beforeChunk;

  _ChunkFloodService(super.plan, {this.beforeChunk});

  @override
  Future<LibraryDeltaApplyResult> applyDeltaPlan(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    for (var i = 1; i <= 100; i++) {
      beforeChunk?.call(i);
      onProgress?.call(
        LibraryUpdateProgress(
          phase: LibraryUpdatePhase.downloading,
          totalSteps: 1,
          bytesDownloaded: i * 1000,
          bytesTotal: 100000,
        ),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return const LibraryDeltaApplyResult(appliedSteps: 1);
  }
}

/// שירות שמדווח על שלב applying ואז נחסם — לבדיקת חסימת ביטול אחרי כתיבת DB.
class _GatedAtApplyService implements LibraryUpdateService {
  final LibraryUpdatePlan plan;
  final Completer<void> gate;
  final bool reportNextStepDownload;
  _GatedAtApplyService(
    this.plan,
    this.gate, {
    this.reportNextStepDownload = false,
  });

  @override
  Future<RecoveryResult> recoverIfNeeded() async =>
      const RecoveryResult(RecoveryAction.none);

  @override
  Future<LibraryUpdatePlan> checkForUpdate({
    required bool allowPrerelease,
  }) async => plan;

  @override
  Future<LibraryDeltaApplyResult> applyDeltaPlan(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    onProgress?.call(
      const LibraryUpdateProgress(phase: LibraryUpdatePhase.applying),
    );
    if (reportNextStepDownload) {
      onProgress?.call(
        const LibraryUpdateProgress(
          phase: LibraryUpdatePhase.downloading,
          stepIndex: 1,
          totalSteps: 2,
        ),
      );
    }
    await gate
        .future; // מדמה apply ארוך; אחריו ה-DB עודכן — מתעלמים מ-isCancelled
    return const LibraryDeltaApplyResult(appliedSteps: 1);
  }

  @override
  Future<void> applyFullDownload(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    FullDbReplacedCallback? onDbReplaced,
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
  Future<LibraryDeltaApplyResult> applyDeltaPlan(
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
    return const LibraryDeltaApplyResult(appliedSteps: 1);
  }

  @override
  Future<void> applyFullDownload(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    FullDbReplacedCallback? onDbReplaced,
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
  Future<LibraryDeltaApplyResult> applyDeltaPlan(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    await gate.future; // נחסם עד שהבדיקה משחררת
    return const LibraryDeltaApplyResult(appliedSteps: 1);
  }

  @override
  Future<void> applyFullDownload(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    FullDbReplacedCallback? onDbReplaced,
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
    CompanionAssetStatusCallback? onStatus,
    void Function(int received, int? total)? onDownloadProgress,
    bool Function()? isCancelled,
  }) async {
    calls++;
    if (throwOnRun) throw Exception('companion failed');
    onStatus?.call('בודק את התלמוד הבבלי', CompanionAssetPhase.checking);
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
    CompanionAssetStatusCallback? onStatus,
    void Function(int received, int? total)? onDownloadProgress,
    bool Function()? isCancelled,
  }) async {
    onStatus?.call(
      'מוריד את התלמוד הבבלי',
      CompanionAssetPhase.downloading,
    );
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
    CompanionAssetStatusCallback? onStatus,
    void Function(int received, int? total)? onDownloadProgress,
    bool Function()? isCancelled,
  }) async {
    calls++;
    if (calls == 1) {
      onStatus?.call(
        'מוריד את התלמוד הבבלי',
        CompanionAssetPhase.downloading,
      );
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
  bool? sourceReachable,
  DateTime Function()? now,
  void Function()? onCheckSucceeded,
}) => LibraryUpdateBloc(
  repository: service,
  isOfflineMode: () => offline,
  areUpdatesEnabled: () => updatesEnabled,
  allowPrerelease: () => prerelease,
  companionAssets: companionAssets,
  hasInternet: () async => hasInternet,
  isSourceReachable: () async => sourceReachable ?? hasInternet,
  onCheckSucceeded: onCheckSucceeded,
  now: now,
);

int _checkSucceededCalls = 0;

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
  final deltaWithFallbackPlan = LibraryUpdatePlan.delta(
    localVersion: 1,
    targetVersion: 3,
    steps: const [],
    fullDbAsset: const ReleaseAsset(
      name: 'seforim.db.zst',
      downloadUrl: 'https://x',
      size: 1200000000,
    ),
    fullDbReleaseTag: 'v3',
  );
  final blockedPlan = LibraryUpdatePlan.blocked(
    localVersion: 1,
    targetVersion: 3,
    reason: 'schema לא תואם',
  );

  group('LibraryUpdateBloc', () {
    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'בדיקה שהצליחה (גם "אין עדכון") מדווחת ל-onCheckSucceeded',
      build: () => _bloc(
        _FakeService(nonePlan),
        onCheckSucceeded: () => _checkSucceededCalls++,
      ),
      setUp: () => _checkSucceededCalls = 0,
      act: (b) => b.add(const StartLibraryUpdate()),
      verify: (_) => expect(_checkSucceededCalls, 1),
    );

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'בדיקה שנכשלה אינה מדווחת ל-onCheckSucceeded - הניסיון הבא בעלייה הבאה',
      build: () => _bloc(
        _FakeService(nonePlan, throwOnCheck: true),
        onCheckSucceeded: () => _checkSucceededCalls++,
      ),
      setUp: () => _checkSucceededCalls = 0,
      act: (b) => b.add(const StartLibraryUpdate()),
      wait: const Duration(milliseconds: 20),
      verify: (_) => expect(_checkSucceededCalls, 0),
    );

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
            .having(
              (s) => s.message,
              'message',
              LibraryMessages.noInternetConnection,
            )
            .having((s) => s.errorMessage, 'errorMessage', isNull),
      ],
    );

    // רשת מסוננת: יש אינטרנט אך GitHub חסום — שגיאה בכל עלייה היא רעש
    // שאין למשתמש מה לעשות איתו (issue #1027).
    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'כשל בבדיקה כששרת העדכונים חסום → מנותק ולא שגיאה',
      build: () => _bloc(
        _FakeService(nonePlan, throwOnCheck: true),
        sourceReachable: false,
      ),
      act: (b) => b.add(const StartLibraryUpdate()),
      expect: () => [
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.checking,
        ),
        isA<LibraryUpdateState>()
            .having((s) => s.status, 'status', LibraryUpdateStatus.disconnected)
            .having(
              (s) => s.message,
              'message',
              LibraryMessages.updateSourceUnreachable,
            )
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
      'אימות DB מלא נשאר מצב עבודה גלוי',
      build: () => _bloc(_FullVerifyingService(fullPlan)),
      seed: () => LibraryUpdateState(
        status: LibraryUpdateStatus.needsFullConfirmation,
        plan: fullPlan,
      ),
      act: (b) => b.add(const ConfirmFullDownload()),
      wait: const Duration(milliseconds: 30),
      expect: () => [
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.downloading,
        ),
        isA<LibraryUpdateState>()
            .having((s) => s.status, 'status', LibraryUpdateStatus.applying)
            .having((s) => s.message, 'message', 'מאמת קובץ עדכון'),
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.completed,
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
        isSourceReachable: () async {
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
        isSourceReachable: () => probeGate.future,
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

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'כשל בהורדה מלאה אחרי דלתא חלקית שומר את השינויים לריענון',
      build: () => _bloc(_FakeService(fullPlan, throwOnApply: true)),
      seed: () => LibraryUpdateState(
        status: LibraryUpdateStatus.needsFullConfirmation,
        plan: fullPlan,
        hasUpdate: true,
        changedBookIds: const {7},
        requiresFullIndexRefresh: true,
      ),
      act: (b) => b.add(const ConfirmFullDownload()),
      expect: () => [
        isA<LibraryUpdateState>()
            .having(
              (s) => s.status,
              'status',
              LibraryUpdateStatus.downloading,
            )
            .having((s) => s.hasUpdate, 'hasUpdate', true),
        isA<LibraryUpdateState>()
            .having((s) => s.status, 'status', LibraryUpdateStatus.error)
            .having((s) => s.hasUpdate, 'hasUpdate', true)
            .having((s) => s.changedBookIds, 'changedBookIds', const {7})
            .having(
              (s) => s.requiresFullIndexRefresh,
              'requiresFullIndexRefresh',
              true,
            ),
      ],
    );

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'כשל refresh אחרי החלפת DB מלאה רגילה דורש ריענון ו-reconcile מלא',
      build: () => _bloc(_FullRefreshFailingService(fullPlan)),
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
          LibraryUpdateStatus.refreshing,
        ),
        isA<LibraryUpdateState>()
            .having((s) => s.status, 'status', LibraryUpdateStatus.error)
            .having((s) => s.hasUpdate, 'hasUpdate', true)
            .having(
              (s) => s.requiresFullIndexRefresh,
              'requiresFullIndexRefresh',
              true,
            )
            .having(
              (s) => s.plan?.kind,
              'plan.kind',
              LibraryUpdatePlanKind.fullDownload,
            ),
      ],
    );

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'כשל refresh אחרי fallback חלקי משדרג ל-reconcile מלא של ה-DB שהוחלף',
      build: () => _bloc(_FullRefreshFailingService(fullPlan)),
      seed: () => LibraryUpdateState(
        status: LibraryUpdateStatus.needsFullConfirmation,
        plan: fullPlan,
        hasUpdate: true,
        changedBookIds: const {7},
      ),
      act: (b) => b.add(const ConfirmFullDownload()),
      expect: () => [
        isA<LibraryUpdateState>()
            .having(
              (s) => s.status,
              'status',
              LibraryUpdateStatus.downloading,
            )
            .having((s) => s.hasUpdate, 'hasUpdate', true),
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.refreshing,
        ),
        isA<LibraryUpdateState>()
            .having((s) => s.status, 'status', LibraryUpdateStatus.error)
            .having((s) => s.hasUpdate, 'hasUpdate', true)
            .having((s) => s.changedBookIds, 'changedBookIds', const {7})
            .having(
              (s) => s.requiresFullIndexRefresh,
              'requiresFullIndexRefresh',
              true,
            )
            .having(
              (s) => s.plan?.kind,
              'plan.kind',
              LibraryUpdatePlanKind.fullDownload,
            ),
      ],
    );

    late Completer<void> fullReplacementGate;
    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'cancel ו-reset חסומים סינכרונית אחרי החלפת DB מלאה',
      setUp: () => fullReplacementGate = Completer<void>(),
      build: () => _bloc(
        _GatedAfterFullReplacementService(fullPlan, fullReplacementGate),
      ),
      seed: () => LibraryUpdateState(
        status: LibraryUpdateStatus.needsFullConfirmation,
        plan: fullPlan,
      ),
      act: (b) async {
        b.add(const ConfirmFullDownload());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        b.add(const ResetLibraryUpdate());
        b.add(const CancelLibraryUpdate());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        fullReplacementGate.complete();
      },
      wait: const Duration(milliseconds: 20),
      expect: () => [
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.downloading,
        ),
        isA<LibraryUpdateState>().having(
          (s) => s.status,
          'status',
          LibraryUpdateStatus.refreshing,
        ),
        isA<LibraryUpdateState>()
            .having((s) => s.status, 'status', LibraryUpdateStatus.completed)
            .having((s) => s.hasUpdate, 'hasUpdate', true),
      ],
    );

    late Completer<void> cancelFullGate;
    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'ביטול הורדה מלאה אחרי דלתא חלקית שומר את השינויים לריענון',
      setUp: () => cancelFullGate = Completer<void>(),
      build: () => _bloc(_CancellableFullService(fullPlan, cancelFullGate)),
      seed: () => LibraryUpdateState(
        status: LibraryUpdateStatus.needsFullConfirmation,
        plan: fullPlan,
        hasUpdate: true,
        changedBookIds: const {7},
        requiresFullIndexRefresh: true,
      ),
      act: (b) async {
        b.add(const ConfirmFullDownload());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        b.add(const CancelLibraryUpdate());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        cancelFullGate.complete();
      },
      wait: const Duration(milliseconds: 20),
      expect: () => [
        isA<LibraryUpdateState>()
            .having(
              (s) => s.status,
              'status',
              LibraryUpdateStatus.downloading,
            )
            .having((s) => s.hasUpdate, 'hasUpdate', true),
        isA<LibraryUpdateState>()
            .having((s) => s.status, 'status', LibraryUpdateStatus.completed)
            .having((s) => s.hasUpdate, 'hasUpdate', true)
            .having((s) => s.changedBookIds, 'changedBookIds', const {7})
            .having(
              (s) => s.requiresFullIndexRefresh,
              'requiresFullIndexRefresh',
              true,
            ),
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

    test(
      'ביטול נשאר חסום בהורדת צעד מאוחר אחרי שצעד ראשון כבר נכתב',
      () async {
        final gate = Completer<void>();
        final bloc = _bloc(
          _GatedAtApplyService(
            deltaPlan,
            gate,
            reportNextStepDownload: true,
          ),
        );

        bloc.add(const StartLibraryUpdate());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(bloc.state.status, LibraryUpdateStatus.downloading);
        expect(bloc.state.stepIndex, 1);

        bloc.add(const ResetLibraryUpdate());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          bloc.state.status,
          LibraryUpdateStatus.downloading,
          reason: 'אחרי כתיבת צעד ראשון גם reset אסור עד סוף המסלול',
        );

        bloc.add(const CancelLibraryUpdate());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          bloc.state.status,
          LibraryUpdateStatus.downloading,
          reason: 'אחרי כתיבת צעד ראשון אסור לבטל גם בזמן הורדת הצעד הבא',
        );

        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(bloc.state.status, LibraryUpdateStatus.completed);
        expect(bloc.state.hasUpdate, isTrue);
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

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'DeclineFullDownload שומר שינויי דלתא חלקיים לצורך ריענון',
      build: () => _bloc(_FakeService(fullPlan)),
      seed: () => LibraryUpdateState(
        status: LibraryUpdateStatus.needsFullConfirmation,
        plan: fullPlan,
        hasUpdate: true,
        changedBookIds: const {7},
        requiresFullIndexRefresh: true,
      ),
      act: (b) => b.add(const DeclineFullDownload()),
      expect: () => [
        isA<LibraryUpdateState>()
            .having((s) => s.status, 'status', LibraryUpdateStatus.completed)
            .having((s) => s.hasUpdate, 'hasUpdate', true)
            .having((s) => s.changedBookIds, 'changedBookIds', const {7})
            .having(
              (s) => s.requiresFullIndexRefresh,
              'requiresFullIndexRefresh',
              true,
            ),
      ],
    );
    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'סטיית תוכן ב-apply עם fallback → needsFullConfirmation עם תוכנית מלאה',
      build: () => _bloc(
        _FakeService(
          deltaWithFallbackPlan,
          applyError: const PatchApplyException(
            'hash לא תואם',
            hashMismatchStage: PatchHashMismatchStage.fromContentHash,
          ),
        ),
      ),
      act: (b) => b.add(const StartLibraryUpdate()),
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
            .having(
              (s) => s.plan?.kind,
              'plan.kind',
              LibraryUpdatePlanKind.fullDownload,
            )
            .having(
              (s) => s.message,
              'message',
              contains('תוכן הספרייה המקומית שונה'),
            ),
      ],
    );

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'כשל hash אחרי apply אינו מוצג בטעות כסטיית DB מקומי',
      build: () => _bloc(
        _FakeService(
          deltaWithFallbackPlan,
          applyError: const PatchApplyException(
            'hash תוצאה לא תואם',
            hashMismatchStage: PatchHashMismatchStage.toContentHash,
          ),
        ),
      ),
      act: (b) => b.add(const StartLibraryUpdate()),
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
            .having(
              (s) => s.message,
              'message',
              contains('תוצאת עדכון הדלתא אינה תואמת'),
            )
            .having(
              (s) => s.message,
              'message',
              isNot(contains('תוכן הספרייה המקומית')),
            ),
      ],
    );

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'כשל apply שאינו סטיית תוכן (למשל סכמה לא נתמכת) → fallback להורדה מלאה',
      build: () => _bloc(
        _FakeService(
          deltaWithFallbackPlan,
          applyError: const PatchApplyException(
            'גרסת סכמת ה-patch (5) חדשה מהנתמך (4) — נדרש עדכון תוכנה',
          ),
        ),
      ),
      act: (b) => b.add(const StartLibraryUpdate()),
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
            .having(
              (s) => s.plan?.kind,
              'plan.kind',
              LibraryUpdatePlanKind.fullDownload,
            )
            .having(
              (s) => s.message,
              'message',
              contains('החלת עדכון הדלתא נכשלה'),
            ),
      ],
    );

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'כשל בצעד מאוחר שומר את שינויי הצעדים שהושלמו במסך ה-fallback',
      build: () => _bloc(
        _FakeService(
          deltaWithFallbackPlan,
          applyError: const PartiallyAppliedLibraryDeltaException(
            cause: PatchApplyException('patch שני אינו נתמך'),
            appliedResult: LibraryDeltaApplyResult(
              changedBookIds: {7, 12},
              requiresFullIndexRefresh: true,
              appliedSteps: 1,
            ),
          ),
        ),
      ),
      act: (b) => b.add(const StartLibraryUpdate()),
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
            .having((s) => s.hasUpdate, 'hasUpdate', true)
            .having(
              (s) => s.changedBookIds,
              'changedBookIds',
              const {7, 12},
            )
            .having(
              (s) => s.requiresFullIndexRefresh,
              'requiresFullIndexRefresh',
              true,
            ),
      ],
    );

    blocTest<LibraryUpdateBloc, LibraryUpdateState>(
      'סטיית תוכן בלי DB מלא בתוכנית → error',
      build: () => _bloc(
        _FakeService(
          deltaPlan,
          applyError: const PatchApplyException(
            'hash לא תואם',
            isContentMismatch: true,
          ),
        ),
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

    group('ויסות דיווחי התקדמות', () {
      blocTest<LibraryUpdateBloc, LibraryUpdateState>(
        '100 chunks באותו רגע → נפלטים רק הראשון והאחרון',
        build: () => _bloc(
          _ChunkFloodService(deltaPlan),
          now: () => DateTime(2026, 1, 1),
        ),
        act: (b) => b.add(const StartLibraryUpdate()),
        wait: const Duration(milliseconds: 50),
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
                LibraryUpdateStatus.downloading,
              )
              .having((s) => s.bytesDownloaded, 'bytesDownloaded', 1000),
          isA<LibraryUpdateState>()
              .having(
                (s) => s.status,
                'status',
                LibraryUpdateStatus.downloading,
              )
              .having((s) => s.bytesDownloaded, 'bytesDownloaded', 100000),
          isA<LibraryUpdateState>().having(
            (s) => s.status,
            'status',
            LibraryUpdateStatus.completed,
          ),
        ],
      );

      blocTest<LibraryUpdateBloc, LibraryUpdateState>(
        'chunk שמגיע אחרי progressInterval עובר את הוויסות',
        build: () {
          var clock = DateTime(2026, 1, 1);
          return _bloc(
            _ChunkFloodService(
              deltaPlan,
              beforeChunk: (i) {
                if (i == 50) {
                  clock = clock.add(
                    LibraryUpdateBloc.progressInterval +
                        const Duration(milliseconds: 1),
                  );
                }
              },
            ),
            now: () => clock,
          );
        },
        act: (b) => b.add(const StartLibraryUpdate()),
        wait: const Duration(milliseconds: 50),
        expect: () => [
          isA<LibraryUpdateState>().having(
            (s) => s.status,
            'status',
            LibraryUpdateStatus.checking,
          ),
          isA<LibraryUpdateState>().having(
            (s) => s.bytesDownloaded,
            'bytesDownloaded',
            1000,
          ),
          isA<LibraryUpdateState>().having(
            (s) => s.bytesDownloaded,
            'bytesDownloaded',
            50000,
          ),
          isA<LibraryUpdateState>().having(
            (s) => s.bytesDownloaded,
            'bytesDownloaded',
            100000,
          ),
          isA<LibraryUpdateState>().having(
            (s) => s.status,
            'status',
            LibraryUpdateStatus.completed,
          ),
        ],
      );
    });
  });
}
