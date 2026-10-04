import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search_feedback/search_feedback_queue.dart';

void main() {
  late Directory dir;
  var tick = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sf_queue');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  SearchFeedbackQueue makeQueue({
    int maxEvents = 5000,
    int maxBytes = 5 * 1024 * 1024,
    int segmentEvents = 100,
  }) => SearchFeedbackQueue(
    () async => dir,
    clock: () => DateTime.utc(2026, 10, 2).add(Duration(seconds: tick++)),
    maxEvents: maxEvents,
    maxBytes: maxBytes,
    segmentEvents: segmentEvents,
  );

  Map<String, Object?> event(int i) => {'eventId': 'event_$i', 'n': i};
  const context = {'app': 'otzaria'};

  test(
    'appends JSONL lines with a context header and reads them back',
    () async {
      final queue = makeQueue();
      await queue.append(event(1), context);
      await queue.append(event(2), context);
      final names = await queue.sealAndList();
      expect(names, hasLength(1));

      final lines = await File('${dir.path}/${names.single}').readAsLines();
      expect(jsonDecode(lines.first), context);
      expect(lines, hasLength(3));

      final batch = (await queue.read(names.single))!;
      expect(batch.eventLines.map((l) => jsonDecode(l)['n']), [1, 2]);
    },
  );

  test('a new context or a full segment opens a new segment', () async {
    final queue = makeQueue(segmentEvents: 2);
    for (var i = 0; i < 5; i++) {
      await queue.append(event(i), context);
    }
    await queue.append(event(9), {'app': 'other'});
    expect(await queue.sealAndList(), hasLength(4));
    expect(queue.eventCount, 6);
  });

  test('event cap drops the oldest segments', () async {
    final queue = makeQueue(maxEvents: 10, segmentEvents: 4);
    for (var i = 0; i < 30; i++) {
      await queue.append(event(i), context);
    }
    expect(queue.eventCount, lessThanOrEqualTo(10));
    final names = await queue.sealAndList();
    final last = await queue.read(names.last);
    expect(jsonDecode(last!.eventLines.last)['n'], 29, reason: 'newest kept');
    final first = await queue.read(names.first);
    expect(jsonDecode(first!.eventLines.first)['n'], greaterThan(0));
  });

  test('byte cap drops the oldest segments', () async {
    final queue = makeQueue(maxBytes: 2000, segmentEvents: 3);
    for (var i = 0; i < 50; i++) {
      await queue.append({...event(i), 'pad': 'x' * 100}, context);
    }
    expect(queue.byteCount, lessThanOrEqualTo(2000));
  });

  test('state survives a reload from disk', () async {
    final first = makeQueue();
    await first.append(event(1), context);
    await first.append(event(2), context);
    final reloaded = makeQueue();
    await reloaded.load();
    expect(reloaded.eventCount, 2);
  });

  test('split keeps order; a single event is dropped', () async {
    final queue = makeQueue();
    for (var i = 0; i < 4; i++) {
      await queue.append(event(i), context);
    }
    final name = (await queue.sealAndList()).single;
    await queue.split(name);
    final parts = await queue.sealAndList();
    expect(parts, hasLength(2));
    final firstPart = await queue.read(parts.first);
    expect(firstPart!.eventLines.map((l) => jsonDecode(l)['n']), [0, 1]);

    final single = makeQueue();
    await single.purge();
    await single.append(event(7), context);
    final only = (await single.sealAndList()).single;
    await single.split(only);
    expect(single.isEmpty, isTrue);
  });

  test('purge removes every queue file', () async {
    final queue = makeQueue();
    await queue.append(event(1), context);
    await queue.purge();
    expect(queue.isEmpty, isTrue);
    expect(dir.listSync(), isEmpty);
  });
}
