import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/navigation/view/startup_work_gate.dart';

class MockLibraryUpdateBloc
    extends MockBloc<LibraryUpdateEvent, LibraryUpdateState>
    implements LibraryUpdateBloc {}

void main() {
  setUpAll(() {
    registerFallbackValue(const StartLibraryUpdate());
  });

  late MockLibraryUpdateBloc libraryUpdateBloc;
  late int backgroundSyncCalls;

  setUp(() {
    libraryUpdateBloc = MockLibraryUpdateBloc();
    backgroundSyncCalls = 0;
    addTearDown(libraryUpdateBloc.close);
  });

  bool tryStart({
    required StartupWorkGate gate,
    bool autoSyncEnabled = true,
    bool updatesAllowed = true,
  }) {
    return tryStartDeferredStartupWork(
      gate: gate,
      startBackgroundSync: () => backgroundSyncCalls++,
      isAutoSyncEnabled: () => autoSyncEnabled,
      canUseSoftwareAndBookUpdates: () => updatesAllowed,
      libraryUpdateBloc: () => libraryUpdateBloc,
    );
  }

  test('שולח עדכון ספרייה פעם אחת כשהשער נפתח', () {
    final gate = StartupWorkGate();
    gate.markLibraryLoaded();
    gate.markIndexingDecisionResolved(expectIndexing: false);

    expect(tryStart(gate: gate), isTrue);
    expect(tryStart(gate: gate), isFalse);

    expect(backgroundSyncCalls, 1);
    verify(() => libraryUpdateBloc.add(const StartLibraryUpdate())).called(1);
  });

  test('לא מתחיל עבודות לפני שהשער נפתח', () {
    final gate = StartupWorkGate();

    expect(tryStart(gate: gate), isFalse);

    expect(backgroundSyncCalls, 0);
    verifyNever(() => libraryUpdateBloc.add(const StartLibraryUpdate()));
  });

  test('מתחיל סנכרון רקע אך לא עדכון ספרייה במצב מנותק', () {
    final gate = StartupWorkGate();
    gate.markLibraryLoaded();
    gate.markIndexingDecisionResolved(expectIndexing: false);

    expect(tryStart(gate: gate, updatesAllowed: false), isTrue);

    expect(backgroundSyncCalls, 1);
    verifyNever(() => libraryUpdateBloc.add(const StartLibraryUpdate()));
  });

  test('מתחיל סנכרון רקע אך לא עדכון ספרייה כשהסנכרון האוטומטי כבוי', () {
    final gate = StartupWorkGate();
    gate.markLibraryLoaded();
    gate.markIndexingDecisionResolved(expectIndexing: false);

    expect(tryStart(gate: gate, autoSyncEnabled: false), isTrue);

    expect(backgroundSyncCalls, 1);
    verifyNever(() => libraryUpdateBloc.add(const StartLibraryUpdate()));
  });
}
