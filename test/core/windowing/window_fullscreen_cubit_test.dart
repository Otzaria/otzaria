import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/window_fullscreen_cubit.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../../helpers/memory_settings_cache.dart';

void main() {
  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  test('ערך התחלתי נקרא מהמפתח השמור, וברירת המחדל היא false', () async {
    final fresh = WindowFullscreenCubit(persist: (_) async {});
    addTearDown(fresh.close);
    expect(fresh.state, isFalse);

    await Settings.setValue<bool>(SettingsRepository.keyIsFullscreen, true);
    final restored = WindowFullscreenCubit(persist: (_) async {});
    addTearDown(restored.close);
    expect(restored.state, isTrue);
  });

  test('set ללא persist מוזרק כותב לאותו מפתח הגדרות', () async {
    final cubit = WindowFullscreenCubit(initial: false);
    addTearDown(cubit.close);

    await cubit.set(true);

    expect(cubit.state, isTrue);
    expect(
      Settings.getValue<bool>(SettingsRepository.keyIsFullscreen),
      isTrue,
    );
  });

  test('ערך זהה אינו פולט ואינו נשמר שוב', () async {
    final persisted = <bool>[];
    final cubit = WindowFullscreenCubit(
      initial: false,
      persist: (value) async => persisted.add(value),
    );
    addTearDown(cubit.close);
    final emitted = <bool>[];
    final subscription = cubit.stream.listen(emitted.add);
    addTearDown(subscription.cancel);

    await cubit.set(false);
    await cubit.set(true);
    await cubit.set(true);
    await cubit.set(false);
    await Future<void>.delayed(Duration.zero);

    expect(emitted, [true, false]);
    expect(persisted, [true, false]);
  });

  test('סנכרון מהחלון מעדכן UI בלבד, ופקודה עדיין שומרת שינוי', () async {
    final persisted = <bool>[];
    final cubit = WindowFullscreenCubit(
      initial: false,
      persist: (value) async => persisted.add(value),
    );
    addTearDown(cubit.close);
    final emitted = <bool>[];
    final subscription = cubit.stream.listen(emitted.add);
    addTearDown(subscription.cancel);

    cubit.syncFromWindow(true);
    cubit.syncFromWindow(true);
    cubit.syncFromWindow(false);
    expect(persisted, isEmpty);
    await cubit.set(true);
    await Future<void>.delayed(Duration.zero);

    expect(emitted, [true, false, true]);
    expect(persisted, [true]);
  });
}
