import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

void main() {
  test('בדיקת קיום ספק אינה פותחת מנוע', () {
    expect(TantivyDataProvider.instanceIfCreated, isNull);
    expect(TantivyDataProvider.instanceIfCreated, isNull);
  });

  test('פינוי אינו ממתין לאתחול שטרם הושלם', () async {
    final opening = Completer<SearchEngine>();
    final provider = TantivyDataProvider.forTesting(opening.future);
    await provider.releaseMemoryIfInitialized();
    final engine = _MemoryEngine();
    opening.complete(engine);
    await provider.engine;
    expect(engine.releases, 0);
  });

  test('פינוי מופעל רק על המנוע הפתוח', () async {
    final engine = _MemoryEngine();
    final provider = TantivyDataProvider.forTesting(Future.value(engine));
    await provider.engine;
    provider.isInitialized.value = true;
    await provider.releaseMemoryIfInitialized();
    expect(engine.releases, 1);
    engine.dispose();
    await provider.releaseMemoryIfInitialized();
    expect(engine.releases, 1);
  });

  test('מנוע שהוחלף בזמן ההמתנה אינו מפונה', () async {
    final first = Completer<SearchEngine>();
    final provider = TantivyDataProvider.forTesting(first.future);
    provider.isInitialized.value = true;
    final releasing = provider.releaseMemoryIfInitialized();
    final replacement = _MemoryEngine();
    provider.engine = Future.value(replacement);
    final stale = _MemoryEngine();
    first.complete(stale);
    await releasing;
    expect(stale.releases, 0);
    expect(replacement.releases, 0);
    await provider.releaseMemoryIfInitialized();
    expect(replacement.releases, 1);
  });
}

class _MemoryEngine implements SearchEngine {
  int releases = 0;
  bool _disposed = false;

  @override
  bool get isDisposed => _disposed;

  @override
  Future<void> releaseMemory() async => releases++;

  @override
  void dispose() => _disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}
