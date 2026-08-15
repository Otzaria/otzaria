import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/anki_native/bloc/anki_native_bloc.dart';
import 'package:otzaria/anki_native/bloc/anki_native_event.dart';
import 'package:otzaria/anki_native/bloc/anki_native_state.dart';
import 'package:otzaria/anki_native/models/anki_native_window.dart';
import 'package:otzaria/anki_native/repository/anki_native_repository.dart';

const mainWindow = AnkiNativeWindow(
  targetId: 'main',
  hwnd: '0000000000000001',
  title: 'Anki',
  kind: 'mainWindow',
  active: true,
  modal: false,
  closable: false,
);

const browserWindow = AnkiNativeWindow(
  targetId: 'browser',
  hwnd: '0000000000000002',
  title: 'דפדוף',
  kind: 'window',
  active: false,
  modal: false,
  closable: true,
);

class FakeAnkiNativeRepository implements AnkiNativeRepository {
  final List<AnkiNativeSnapshot> snapshots;
  Object? startupError;
  Object? attachError;
  final attached = <String>[];
  final visibility = <bool>[];
  final closed = <String>[];
  int detachCount = 0;

  FakeAnkiNativeRepository({
    this.snapshots = const [
      AnkiNativeSnapshot(
        processId: 42,
        generation: 'generation',
        windows: [mainWindow, browserWindow],
      ),
    ],
  });

  int _snapshotIndex = 0;

  @override
  Future<void> ensureAnkiRunning() async {
    if (startupError != null) throw startupError!;
  }

  @override
  Future<AnkiNativeSnapshot> fetchWindows() async {
    final index = _snapshotIndex.clamp(0, snapshots.length - 1);
    _snapshotIndex++;
    return snapshots[index];
  }

  @override
  Future<bool> attach(
    AnkiNativeWindow window,
    int processId,
    String generation,
  ) async {
    if (attachError != null) throw attachError!;
    attached.add(window.targetId);
    return true;
  }

  @override
  Future<void> setBounds(AnkiNativeBounds bounds) async {}

  @override
  Future<void> setVisible(bool visible) async {
    visibility.add(visible);
  }

  @override
  Future<void> closeWindow(String targetId) async {
    closed.add(targetId);
  }

  @override
  Future<void> detach() async {
    detachCount++;
  }

  @override
  void dispose() {}
}

void main() {
  blocTest<AnkiNativeBloc, AnkiNativeState>(
    'מפעיל את Anki ובוחר את החלון הפעיל',
    build: () => AnkiNativeBloc(repository: FakeAnkiNativeRepository()),
    act: (bloc) => bloc.add(const StartAnkiNative()),
    expect: () => [
      const AnkiNativeLoading(),
      const AnkiNativeReady(
        processId: 42,
        generation: 'generation',
        windows: [mainWindow, browserWindow],
        selectedTargetId: 'main',
      ),
    ],
    verify: (bloc) {
      final repository = bloc.repository as FakeAnkiNativeRepository;
      expect(repository.attached, ['main']);
      expect(repository.visibility, [true]);
    },
  );

  blocTest<AnkiNativeBloc, AnkiNativeState>(
    'שומר מצב מוסתר גם כאשר הטאב הוסתר בזמן ההפעלה',
    build: () => AnkiNativeBloc(repository: FakeAnkiNativeRepository()),
    act: (bloc) {
      bloc
        ..add(const SetAnkiNativeVisibility(false))
        ..add(const StartAnkiNative());
    },
    expect: () => [
      const AnkiNativeLoading(),
      const AnkiNativeReady(
        processId: 42,
        generation: 'generation',
        windows: [mainWindow, browserWindow],
        selectedTargetId: 'main',
        visible: false,
      ),
    ],
    verify: (bloc) {
      final repository = bloc.repository as FakeAnkiNativeRepository;
      expect(repository.visibility, [false, false]);
    },
  );

  blocTest<AnkiNativeBloc, AnkiNativeState>(
    'מנתק ומסתיר את החלון כאשר ההפעלה נכשלת',
    build: () {
      final repository = FakeAnkiNativeRepository()
        ..startupError = StateError('כשל בדיקה');
      return AnkiNativeBloc(repository: repository);
    },
    act: (bloc) => bloc.add(const StartAnkiNative()),
    expect: () => [
      const AnkiNativeLoading(),
      const AnkiNativeFailure('כשל בדיקה'),
    ],
    verify: (bloc) {
      final repository = bloc.repository as FakeAnkiNativeRepository;
      expect(repository.visibility, [false]);
      expect(repository.detachCount, greaterThanOrEqualTo(1));
    },
  );

  blocTest<AnkiNativeBloc, AnkiNativeState>(
    'מסמן כשל Native כזמין למסלול השיקוף',
    build: () {
      final repository = FakeAnkiNativeRepository()
        ..attachError = PlatformException(code: 'native_attach_failed');
      return AnkiNativeBloc(repository: repository);
    },
    act: (bloc) => bloc.add(const StartAnkiNative()),
    expect: () => [
      const AnkiNativeLoading(),
      isA<AnkiNativeFailure>().having(
        (state) => state.canUseFallback,
        'canUseFallback',
        isTrue,
      ),
    ],
  );

  test('מאמת HWND וממיר אותו לאותיות גדולות', () {
    final window = AnkiNativeWindow.fromJson({
      'targetId': 'window',
      'hwnd': 'aBc12',
      'title': 'Anki',
    });

    expect(window.hwnd, 'ABC12');
    expect(
      () => AnkiNativeWindow.fromJson({
        'targetId': 'window',
        'hwnd': 'not-a-window',
      }),
      throwsFormatException,
    );
  });
}
