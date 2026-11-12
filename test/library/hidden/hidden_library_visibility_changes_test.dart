import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
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

  test('fires for a saved selection', () async {
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

    expect(firstFired, 0);
    expect(secondFired, 1);
    first.resume();
    await Future<void>.delayed(Duration.zero);
    expect(firstFired, 1);

    await first.cancel();
    await const HiddenLibraryStore().save(
      const HiddenLibrarySelection(bookKeys: {'ספר אחר'}),
    );
    expect(firstFired, 1);
    expect(secondFired, 2);
  });
}
