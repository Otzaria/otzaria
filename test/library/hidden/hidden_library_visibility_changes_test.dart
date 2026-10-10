import 'dart:async';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/settings_sync.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    SettingsSync.instance.applyLocally = (key, value) async {};
  });

  tearDown(() {
    SettingsSync.instance.applyLocally = null;
    SettingsSync.instance.clearLocally = null;
  });

  test('shares a broadcast stream between store instances', () async {
    final stream = const HiddenLibraryStore().visibilityChanges;
    expect(identical(stream, HiddenLibraryStore().visibilityChanges), isTrue);
    expect(stream.isBroadcast, isTrue);

    final first = stream.listen((_) {});
    final second = stream.listen((_) {});
    await first.cancel();
    await second.cancel();
  });

  test('fires for a change in this window', () async {
    var fired = 0;
    final subscription = const HiddenLibraryStore().visibilityChanges.listen(
      (_) => fired++,
    );
    addTearDown(subscription.cancel);

    await const HiddenLibraryStore().save(
      const HiddenLibrarySelection(bookKeys: {'ספר'}),
    );

    expect(fired, 1);
  });

  test('fires for the hidden library settings of another window', () async {
    var fired = 0;
    final subscription = const HiddenLibraryStore().visibilityChanges.listen(
      (_) => fired++,
    );
    addTearDown(subscription.cancel);

    await SettingsSync.instance.applyAuthoritativeValues({
      HiddenLibraryStore.bookKeysSetting: 'x',
      HiddenLibraryStore.categoryPathsSetting: 'y',
      'key-unrelated-setting': true,
    });
    expect(fired, 2);
  });

  test('fires synchronously when another window resets settings', () async {
    SettingsSync.instance.clearLocally = () async {};
    var fired = 0;
    final subscription = const HiddenLibraryStore().visibilityChanges.listen(
      (_) => fired++,
    );
    addTearDown(subscription.cancel);

    await SettingsSync.instance.handleRequest({
      'type': SettingsSync.requestReset,
    });

    expect(fired, 1);
  });

  test('pausing one listener does not pause another', () async {
    var firstFired = 0;
    var secondFired = 0;
    final first = const HiddenLibraryStore().visibilityChanges.listen(
      (_) => firstFired++,
    );
    final second = const HiddenLibraryStore().visibilityChanges.listen(
      (_) => secondFired++,
    );
    addTearDown(first.cancel);
    addTearDown(second.cancel);
    first.pause();

    await const HiddenLibraryStore().save(
      const HiddenLibrarySelection(bookKeys: {'ספר'}),
    );
    await SettingsSync.instance.applyAuthoritativeValues({
      HiddenLibraryStore.bookKeysSetting: 'x',
      HiddenLibraryStore.categoryPathsSetting: 'y',
    });

    expect(firstFired, 0);
    expect(secondFired, 3);
    first.resume();
    await Future<void>.delayed(Duration.zero);
    expect(firstFired, 3);

    await first.cancel();
    await const HiddenLibraryStore().save(
      const HiddenLibrarySelection(bookKeys: {'ספר אחר'}),
    );
    expect(firstFired, 3);
    expect(secondFired, 4);
  });

  test('shares source subscriptions only while listeners exist', () async {
    final local = _CountingSource<HiddenLibrarySelection>();
    final remote = _CountingSource<String>();
    final stream = HiddenLibraryStore.createVisibilityChanges(
      local.stream,
      remote.stream,
    );
    expect(local.listenCount, 0);
    expect(remote.listenCount, 0);

    var firstFired = 0;
    var secondFired = 0;
    final first = stream.listen((_) => firstFired++);
    final second = stream.listen((_) => secondFired++);
    expect(local.listenCount, 1);
    expect(remote.listenCount, 1);

    local.emit(const HiddenLibrarySelection());
    remote.emit('unrelated');
    remote.emit(HiddenLibraryStore.bookKeysSetting);
    remote.emit(HiddenLibraryStore.categoryPathsSetting);
    remote.emit('');
    expect(firstFired, 4);
    expect(secondFired, 4);

    await first.cancel();
    expect(local.activeListeners, 1);
    expect(remote.activeListeners, 1);
    await second.cancel();
    expect(local.activeListeners, 0);
    expect(remote.activeListeners, 0);

    local.emit(const HiddenLibrarySelection());
    remote.emit('');
    final third = stream.listen((_) => secondFired++);
    expect(local.listenCount, 2);
    expect(remote.listenCount, 2);
    expect(secondFired, 4);
    remote.emit('');
    expect(secondFired, 5);
    await third.cancel();
    expect(local.activeListeners, 0);
    expect(remote.activeListeners, 0);
  });

  test('can replace the last listener inside its callback', () async {
    final local = _CountingSource<HiddenLibrarySelection>();
    final remote = _CountingSource<String>();
    final stream = HiddenLibraryStore.createVisibilityChanges(
      local.stream,
      remote.stream,
    );
    var replacementFired = 0;
    late StreamSubscription<void> first;
    late StreamSubscription<void> replacement;
    first = stream.listen((_) {
      unawaited(first.cancel());
      replacement = stream.listen((_) => replacementFired++);
    });

    local.emit(const HiddenLibrarySelection());
    expect(replacementFired, 0);
    expect(local.activeListeners, 1);
    expect(remote.activeListeners, 1);
    remote.emit('');
    expect(replacementFired, 1);
    await replacement.cancel();
    expect(local.activeListeners, 0);
    expect(remote.activeListeners, 0);
  });

  test('stops after the subscription is cancelled', () async {
    var fired = 0;
    final subscription = const HiddenLibraryStore().visibilityChanges.listen(
      (_) => fired++,
    );
    await subscription.cancel();

    await const HiddenLibraryStore().save(
      const HiddenLibrarySelection(bookKeys: {'ספר אחר'}),
    );

    expect(fired, 0);
  });
}

class _CountingSource<T> {
  final _listeners = <MultiStreamController<T>>[];
  var listenCount = 0;

  late final stream = Stream<T>.multi((controller) {
    listenCount++;
    _listeners.add(controller);
    controller.onCancel = () => _listeners.remove(controller);
  }, isBroadcast: true);

  int get activeListeners => _listeners.length;

  void emit(T event) {
    for (final listener in _listeners.toList()) {
      listener.addSync(event);
    }
  }
}
