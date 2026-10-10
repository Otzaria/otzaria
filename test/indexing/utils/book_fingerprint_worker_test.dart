import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/utils/book_fingerprint_worker.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../../support/search_engine_test_init.dart';

void main() {
  test('כשל אתחול וסגירת עובד משמרים מנוע ראשי ואינדקס קיימים', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fingerprint_engine',
    );
    final engine = await SearchEngine.newInstance(path: directory.path);
    addTearDown(() async {
      engine.dispose();
      await directory.delete(recursive: true);
    });
    await engine.addTextBook(
      text: 'טקסט',
      title: 'ספר',
      topics: '/a',
      filePath: 'id:1',
      catalogueOrder: 1,
      generationOrder: 2,
      textStorage: TextStorage.inIndex,
    );
    await engine.commit();
    await expectLater(
      BookFingerprintWorker.start(nativeLibraryPath: '/missing/search_engine'),
      throwsA(isA<RemoteError>()),
    );
    final worker = await BookFingerprintWorker.start(
      nativeLibraryPath: searchEngineLoadedLibraryPath!,
    );
    final expected = computeBookFingerprint(
      text: 'טקסט',
      title: 'ספר',
      topics: '/a',
      catalogueOrder: 1,
      generationOrder: 2,
    );
    expect(
      await worker.compute(
        text: 'טקסט',
        title: 'ספר',
        topics: '/a',
        catalogueOrder: 1,
        generationOrder: 2,
      ),
      expected,
    );
    await worker.close();
    await worker.close();
    expect(await engine.getBookFingerprints(), {'id:1': expected});
    await expectLater(
      worker.compute(
        text: 'טקסט',
        title: 'ספר',
        topics: '/a',
        catalogueOrder: 1,
        generationOrder: 2,
      ),
      throwsStateError,
    );
    expect(
      computeBookFingerprint(
        text: 'טקסט',
        title: 'ספר',
        topics: '/a',
        catalogueOrder: 1,
        generationOrder: 2,
      ),
      expected,
    );
  });

  test('עובד חם מחשב אותה חתימה קנונית ומשאיר את הטיימרים פעילים', () async {
    final worker = await BookFingerprintWorker.start(
      nativeLibraryPath: searchEngineLoadedLibraryPath!,
    );
    addTearDown(worker.close);
    final values = [
      (
        text: '',
        title: 'ספר ריק',
        topics: '/מקורות',
        order: 0,
        generation: 0,
        facets: <String>[],
      ),
      (
        text: 'אָב😀\n<b>אחד</b>\r\nשתיים',
        title: 'ספר',
        topics: '/מקורות/אב',
        order: 1,
        generation: 2,
        facets: ['b', 'a', 'b'],
      ),
      (
        text: 'אָב😀\n<b>אחד</b>\r\nשתיים',
        title: 'ספר',
        topics: '/מקורות/אב',
        order: 2,
        generation: 3,
        facets: ['a', 'b'],
      ),
      (
        text: 'טקסט גדול\n' * 300000,
        title: 'גדול',
        topics: '/מקורות',
        order: 3,
        generation: 0,
        facets: <String>[],
      ),
    ];
    for (final value in values) {
      final expected = computeBookFingerprint(
        text: value.text,
        title: value.title,
        topics: value.topics,
        catalogueOrder: value.order,
        generationOrder: value.generation,
        extraFacets: value.facets,
      );
      var timerFired = false;
      final timer = Timer(Duration.zero, () => timerFired = true);
      final actual = await worker.compute(
        text: value.text,
        title: value.title,
        topics: value.topics,
        catalogueOrder: value.order,
        generationOrder: value.generation,
        extraFacets: value.facets,
      );
      timer.cancel();
      expect(actual, expected);
      expect(
        timerFired,
        isTrue,
        reason: 'חישוב החתימה חייב לפנות את ה־UI isolate גם בעובד חם',
      );
    }
  });
}
