import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';

void main() {
  late PluginHighlightRegistry registry;

  setUp(() => registry = PluginHighlightRegistry.forTesting());

  test('ה-Host קובע בעלות ומבודד רשומות בין תוספים', () {
    final first = registry.setHighlight(
      ownerPluginId: 'plugin.a',
      payload: _payload(id: 'same-id'),
      now: DateTime.utc(2026, 7, 14),
    );
    registry.setHighlight(
      ownerPluginId: 'plugin.b',
      payload: _payload(id: 'same-id'),
      now: DateTime.utc(2026, 7, 14),
    );

    expect(first.ownerPluginId, 'plugin.a');
    expect(registry.getHighlights(ownerPluginId: 'plugin.a'), hasLength(1));
    expect(registry.getHighlights(ownerPluginId: 'plugin.b'), hasLength(1));
    expect(
      registry.clearHighlight(
        ownerPluginId: 'plugin.a',
        highlightId: 'same-id',
      ),
      isTrue,
    );
    expect(registry.getHighlights(ownerPluginId: 'plugin.a'), isEmpty);
    expect(registry.getHighlights(ownerPluginId: 'plugin.b'), hasLength(1));
    expect(
      registry
          .getAllHighlights(bookId: 'book', sectionIndex: 1)
          .single
          .ownerPluginId,
      'plugin.b',
    );
  });

  test('setHighlight מחליף מזהה קיים ומגדיל גרסה', () {
    final createdAt = DateTime.utc(2026, 7, 14, 10);
    final updatedAt = DateTime.utc(2026, 7, 14, 11);
    final first = registry.setHighlight(
      ownerPluginId: 'plugin.a',
      payload: _payload(id: 'marker-1'),
      now: createdAt,
    );
    final second = registry.setHighlight(
      ownerPluginId: 'plugin.a',
      payload: _payload(id: 'marker-1', sectionIndex: 2),
      now: updatedAt,
    );

    expect(registry.getHighlights(ownerPluginId: 'plugin.a'), hasLength(1));
    expect(second.version, first.version + 1);
    expect(second.createdAt, createdAt);
    expect(second.updatedAt, updatedAt);
    expect(second.sectionIndex, 2);
    expect(
      registry.getAllHighlights(bookId: 'book', sectionIndex: 1),
      isEmpty,
    );
    expect(
      registry.getAllHighlights(bookId: 'book', sectionIndex: 2),
      [second],
    );
  });

  test('דוחה ניסיון לזייף pluginId', () {
    expect(
      () => registry.setHighlight(
        ownerPluginId: 'plugin.a',
        payload: {..._payload(), 'ownerPluginId': 'plugin.b'},
      ),
      throwsA(
        isA<PluginHighlightException>().having(
          (error) => error.code,
          'code',
          'error.invalid_params',
        ),
      ),
    );
  });

  test('מסנן לפי ספר ומקטע ומנקה רק את הטווח המבוקש', () {
    registry.setHighlight(
      ownerPluginId: 'plugin.a',
      payload: _payload(id: 'one'),
    );
    registry.setHighlight(
      ownerPluginId: 'plugin.a',
      payload: _payload(id: 'two', sectionIndex: 2),
    );
    registry.setHighlight(
      ownerPluginId: 'plugin.a',
      payload: _payload(id: 'three', bookId: 'other'),
    );

    expect(
      registry.getHighlights(
        ownerPluginId: 'plugin.a',
        bookId: 'book',
      ),
      hasLength(2),
    );
    expect(
      registry.clearAll(
        ownerPluginId: 'plugin.a',
        bookId: 'book',
        sectionIndex: 2,
      ),
      1,
    );
    expect(
      registry.getAllHighlights(bookId: 'book', sectionIndex: 2),
      isEmpty,
    );
    expect(registry.getHighlights(ownerPluginId: 'plugin.a'), hasLength(2));
  });

  test('דוחה צבע CSS שאינו בפורמט בטוח', () {
    final payload = _payload();
    payload['style'] = {'backgroundColor': 'url(javascript:alert(1))'};

    expect(
      () => registry.setHighlight(
        ownerPluginId: 'plugin.a',
        payload: payload,
      ),
      throwsA(isA<PluginHighlightException>()),
    );
  });

  test('API ישן נשמר כרשומת line-marker', () {
    final record = registry.setLegacyHighlight(
      ownerPluginId: 'plugin.a',
      bookId: 'book',
      sectionIndex: 7,
      color: '#AABBCC',
      label: 'ישן',
    );

    final json = record.toJson();
    expect(json['index'], 7);
    expect(json['color'], '#AABBCC');
    expect(json['label'], 'ישן');
    expect(record.style.markerMode, 'line-marker');
  });

  test('legacy setHighlight overwrites the same book and section', () {
    final first = registry.setLegacyHighlight(
      ownerPluginId: 'plugin.a',
      bookId: 'book',
      sectionIndex: 7,
      color: '#AABBCC',
    );
    final second = registry.setLegacyHighlight(
      ownerPluginId: 'plugin.a',
      bookId: 'book',
      sectionIndex: 7,
      color: '#112233',
    );

    final records = registry.getHighlights(ownerPluginId: 'plugin.a');
    expect(records, hasLength(1));
    expect(second.highlightId, first.highlightId);
    expect(second.version, first.version + 1);
    expect(records.single.style.backgroundColor, '#112233');
  });

  test('invalid anchor fields are reported as invalid params', () {
    final base = _payload();
    final range = Map<String, dynamic>.from(base['range']! as Map);
    final invalidRanges = <Map<String, dynamic>>[
      {...range, 'exactText': ''},
      {
        ...range,
        'end': {'grapheme': 99, 'codePoint': 99, 'utf16': 99},
      },
      {...range, 'occurrenceIndexInSection': -1},
      {...range, 'occurrenceCountInSection': 0},
      {...range, 'sourceTextHash': 42},
    ];

    for (final invalidRange in invalidRanges) {
      expect(
        () => registry.setHighlight(
          ownerPluginId: 'plugin.a',
          payload: {..._payload(), 'range': invalidRange},
        ),
        throwsA(
          isA<PluginHighlightException>().having(
            (error) => error.code,
            'code',
            'error.invalid_params',
          ),
        ),
      );
    }
  });

  test('updateHighlight partially updates and preserves immutable fields', () {
    final createdAt = DateTime.utc(2026, 7, 14, 10);
    final updatedAt = DateTime.utc(2026, 7, 14, 11);
    final original = registry.setHighlight(
      ownerPluginId: 'plugin.a',
      payload: _payload(id: 'marker-1'),
      now: createdAt,
    );
    var notifications = 0;
    registry.addListener(() => notifications++);

    final updated = registry.updateHighlight(
      ownerPluginId: 'plugin.a',
      payload: {
        'highlightId': 'marker-1',
        'expectedVersion': 1,
        'style': {'opacity': 0.4},
        'metadata': {'note': 'updated'},
      },
      now: updatedAt,
    );

    expect(updated.highlightId, original.highlightId);
    expect(updated.range, same(original.range));
    expect(updated.createdAt, createdAt);
    expect(updated.updatedAt, updatedAt);
    expect(updated.version, 2);
    expect(updated.style.opacity, 0.4);
    expect(updated.style.backgroundColor, '#FFE066');
    expect(updated.style.priority, 3);
    expect(updated.metadata.note, 'updated');
    expect(updated.metadata.tags, original.metadata.tags);
    expect(updated.metadata.source, 'manual');
    expect(notifications, 1);
  });

  test('updateHighlight rejects stale version without changing the record', () {
    registry.setHighlight(
      ownerPluginId: 'plugin.a',
      payload: _payload(id: 'marker-1'),
    );

    expect(
      () => registry.updateHighlight(
        ownerPluginId: 'plugin.a',
        payload: {
          'highlightId': 'marker-1',
          'expectedVersion': 2,
          'style': {'opacity': 0.4},
        },
      ),
      throwsA(
        isA<PluginHighlightException>().having(
          (error) => error.code,
          'code',
          'error.conflict',
        ),
      ),
    );
    expect(
      registry.getHighlights(ownerPluginId: 'plugin.a').single.style.opacity,
      0.7,
    );
  });

  test('updateHighlight accepts current etag and rejects a stale etag', () {
    final original = registry.setHighlight(
      ownerPluginId: 'plugin.a',
      payload: _payload(id: 'marker-1'),
    );
    final updated = registry.updateHighlight(
      ownerPluginId: 'plugin.a',
      payload: {
        'highlightId': 'marker-1',
        'expectedEtag': original.etag,
        'style': {'opacity': 0.4},
      },
    );

    expect(updated.etag, isNot(original.etag));
    expect(
      () => registry.updateHighlight(
        ownerPluginId: 'plugin.a',
        payload: {
          'highlightId': 'marker-1',
          'expectedEtag': original.etag,
          'style': {'opacity': 0.2},
        },
      ),
      throwsA(
        isA<PluginHighlightException>().having(
          (error) => error.code,
          'code',
          'error.conflict',
        ),
      ),
    );
  });

  test('clearHighlight enforces optimistic concurrency', () {
    final original = registry.setHighlight(
      ownerPluginId: 'plugin.a',
      payload: _payload(id: 'marker-1'),
    );

    expect(
      () => registry.clearHighlight(
        ownerPluginId: 'plugin.a',
        highlightId: 'marker-1',
        expectedVersion: 2,
      ),
      throwsA(
        isA<PluginHighlightException>().having(
          (error) => error.code,
          'code',
          'error.conflict',
        ),
      ),
    );
    expect(
      registry.clearHighlight(
        ownerPluginId: 'plugin.a',
        highlightId: 'marker-1',
        expectedEtag: original.etag,
      ),
      isTrue,
    );
  });

  test('updateHighlight cannot access another plugin record', () {
    registry.setHighlight(
      ownerPluginId: 'plugin.a',
      payload: _payload(id: 'marker-1'),
    );

    expect(
      () => registry.updateHighlight(
        ownerPluginId: 'plugin.b',
        payload: {
          'highlightId': 'marker-1',
          'style': {'opacity': 0.4},
        },
      ),
      throwsA(
        isA<PluginHighlightException>().having(
          (error) => error.code,
          'code',
          'error.highlight_not_found',
        ),
      ),
    );
  });

  test('updateHighlight validates patch fields and values', () {
    registry.setHighlight(
      ownerPluginId: 'plugin.a',
      payload: _payload(id: 'marker-1'),
    );

    for (final patch in [
      {
        'highlightId': 'marker-1',
        'style': {'backgroundColor': 'red'},
      },
      {
        'highlightId': 'marker-1',
        'style': {'unknown': true},
      },
      {
        'highlightId': 'marker-1',
        'metadata': {'tags': List.filled(21, 'tag')},
      },
    ]) {
      expect(
        () => registry.updateHighlight(
          ownerPluginId: 'plugin.a',
          payload: patch,
        ),
        throwsA(
          isA<PluginHighlightException>().having(
            (error) => error.code,
            'code',
            'error.invalid_params',
          ),
        ),
      );
    }
  });

  test('reanchorSection moves a shifted highlight and increments version', () {
    registry.setHighlight(
      ownerPluginId: 'plugin.a',
      payload: _reanchorPayload(id: 'marker-1'),
      now: DateTime.utc(2026, 7, 14, 10),
    );

    final changed = registry.reanchorSection(
      bookId: 'book',
      sectionIndex: 1,
      sourceText: 'prefix before target after',
      now: DateTime.utc(2026, 7, 14, 11),
    );

    expect(changed, hasLength(1));
    expect(changed.single.status, 'active');
    expect(changed.single.version, 2);
    expect(changed.single.range.exactText, 'target');
    expect(changed.single.range.start.grapheme, 14);
  });

  test(
    'reanchorSection marks missing text failed and filters it by default',
    () {
      registry.setHighlight(
        ownerPluginId: 'plugin.a',
        payload: _reanchorPayload(id: 'marker-1'),
      );

      final changed = registry.reanchorSection(
        bookId: 'book',
        sectionIndex: 1,
        sourceText: 'completely different',
      );

      expect(changed.single.status, 'failed_to_anchor');
      expect(registry.getHighlights(ownerPluginId: 'plugin.a'), isEmpty);
      expect(
        registry.getAllHighlights(bookId: 'book', sectionIndex: 1),
        isEmpty,
      );
      expect(
        registry.getHighlights(
          ownerPluginId: 'plugin.a',
          includeStale: true,
        ),
        hasLength(1),
      );
    },
  );

  test('reanchorSection does not mutate legacy line markers', () {
    final legacy = registry.setLegacyHighlight(
      ownerPluginId: 'plugin.a',
      bookId: 'book',
      sectionIndex: 1,
    );

    final changed = registry.reanchorSection(
      bookId: 'book',
      sectionIndex: 1,
      sourceText: 'new source',
    );

    expect(changed, isEmpty);
    expect(
      registry.getHighlights(ownerPluginId: 'plugin.a').single.version,
      legacy.version,
    );
  });
}

Map<String, dynamic> _reanchorPayload({required String id}) => {
  'highlightId': id,
  'bookId': 'book',
  'sectionIndex': 1,
  'range': {
    'type': 'text-range-v1',
    'schemaVersion': 1,
    'layer': 'source',
    'sourceTextHash':
        '0000000000000000000000000000000000000000000000000000000000000000',
    'start': {'grapheme': 7, 'codePoint': 7, 'utf16': 7},
    'end': {'grapheme': 13, 'codePoint': 13, 'utf16': 13},
    'exactText': 'target',
    'beforeText': {
      'raw': 'before ',
      'normalized': 'before ',
      'maxGraphemes': 30,
      'actualGraphemes': 7,
      'truncatedAtBoundary': true,
    },
    'afterText': {
      'raw': ' after',
      'normalized': ' after',
      'maxGraphemes': 30,
      'actualGraphemes': 6,
      'truncatedAtBoundary': true,
    },
    'occurrenceIndexInSection': 0,
    'occurrenceCountInSection': 1,
    'normalizationProfile': 'strict',
  },
  'style': {'backgroundColor': '#FFE066'},
};

Map<String, dynamic> _payload({
  String? id,
  String bookId = 'book',
  int sectionIndex = 1,
}) {
  return {
    'highlightId': ?id,
    'bookId': bookId,
    'sectionIndex': sectionIndex,
    'range': {
      'type': 'text-range-v1',
      'schemaVersion': 1,
      'layer': 'source',
      'sourceTextHash':
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'start': {'grapheme': 2, 'codePoint': 2, 'utf16': 2},
      'end': {'grapheme': 6, 'codePoint': 6, 'utf16': 6},
      'exactText': 'טקסט',
      'beforeText': {
        'raw': 'לפני',
        'normalized': 'לפני',
        'maxGraphemes': 30,
        'actualGraphemes': 4,
        'truncatedAtBoundary': true,
      },
      'afterText': {
        'raw': 'אחרי',
        'normalized': 'אחרי',
        'maxGraphemes': 30,
        'actualGraphemes': 4,
        'truncatedAtBoundary': true,
      },
      'occurrenceIndexInSection': 0,
      'occurrenceCountInSection': 1,
    },
    'style': {
      'backgroundColor': '#FFE066',
      'opacity': 0.7,
      'priority': 3,
    },
    'metadata': {
      'note': 'הערה',
      'tags': ['חשוב'],
      'source': 'manual',
    },
  };
}
