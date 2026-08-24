import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
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

  group('revision — מונה המוטציות', () {
    test('מתחיל באפס ואינו זז בקריאות בלבד', () {
      expect(registry.revision, 0);
      registry.getAllHighlights(bookId: 'book', sectionIndex: 1);
      registry.getHighlights(ownerPluginId: 'plugin.a');
      expect(registry.revision, 0);
    });

    test('עולה בכל מוטציה', () {
      registry.setHighlight(
        ownerPluginId: 'plugin.a',
        payload: _payload(id: 'marker-1'),
      );
      final afterSet = registry.revision;
      expect(afterSet, greaterThan(0));

      registry.setLegacyHighlight(
        ownerPluginId: 'plugin.a',
        bookId: 'book',
        sectionIndex: 1,
      );
      expect(registry.revision, greaterThan(afterSet));
      final afterLegacy = registry.revision;

      registry.clearHighlight(
        ownerPluginId: 'plugin.a',
        highlightId: 'marker-1',
      );
      expect(registry.revision, greaterThan(afterLegacy));
      final afterClear = registry.revision;

      registry.removePlugin('plugin.a');
      expect(registry.revision, greaterThan(afterClear));
    });

    test('עולה כשעיגון מחדש משנה רשומה, ונעצר כשאין שינוי', () {
      registry.setHighlight(
        ownerPluginId: 'plugin.a',
        payload: _reanchorPayload(id: 'marker-1'),
      );
      final beforeReanchor = registry.revision;

      registry.reanchorSection(
        bookId: 'book',
        sectionIndex: 1,
        sourceText: 'prefix before target after',
      );
      final afterReanchor = registry.revision;
      expect(afterReanchor, greaterThan(beforeReanchor));

      // עיגון חוזר על אותו טקסט מתכנס: אין שינוי, אין notify, אין revision.
      registry.reanchorSection(
        bookId: 'book',
        sectionIndex: 1,
        sourceText: 'prefix before target after',
      );
      expect(registry.revision, afterReanchor);
    });

    test('כישלון מחיקה אינו מזיז את המונה', () {
      expect(
        registry.clearHighlight(
          ownerPluginId: 'plugin.a',
          highlightId: 'missing',
        ),
        isFalse,
      );
      expect(registry.revision, 0);
      expect(registry.clearAll(ownerPluginId: 'plugin.a'), 0);
      expect(registry.revision, 0);
    });
  });

  group('ריבוי מופעים של אותו תוסף', () {
    const i1 = 'instance-1';
    const i2 = 'instance-2';

    PluginInstanceKey key(String instanceId) => (
      pluginId: 'plugin.a',
      instanceId: instanceId,
    );

    test('אותה הדגשה משני מופעים מצוירת פעם אחת', () {
      registry.setHighlight(
        ownerPluginId: 'plugin.a',
        ownerInstanceId: i1,
        payload: _payload(id: 'shared'),
      );
      registry.setHighlight(
        ownerPluginId: 'plugin.a',
        ownerInstanceId: i2,
        payload: _payload(id: 'shared'),
      );

      expect(
        registry.getAllHighlights(bookId: 'book', sectionIndex: 1),
        hasLength(1),
      );
      expect(
        registry.getHighlights(ownerPluginId: 'plugin.a', ownerInstanceId: i1),
        hasLength(1),
      );
      expect(
        registry.getHighlights(ownerPluginId: 'plugin.a', ownerInstanceId: i2),
        hasLength(1),
      );
    });

    test('בציור מועדף העותק של המופע הגלוי', () {
      registry = PluginHighlightRegistry.forTesting(
        isInstanceVisible: (instanceKey) => instanceKey.instanceId == i2,
      );
      registry.setHighlight(
        ownerPluginId: 'plugin.a',
        ownerInstanceId: i1,
        payload: _payload(id: 'shared'),
      );
      registry.setHighlight(
        ownerPluginId: 'plugin.a',
        ownerInstanceId: i2,
        payload: {
          ..._payload(id: 'shared'),
          'style': {'backgroundColor': '#112233'},
        },
      );

      final rendered = registry
          .getAllHighlights(bookId: 'book', sectionIndex: 1)
          .single;
      expect(rendered.style.backgroundColor, '#112233');
    });

    test('removeInstance מסיר רק את המופע והציור חושף את העותק השני', () {
      registry.setHighlight(
        ownerPluginId: 'plugin.a',
        ownerInstanceId: i1,
        payload: _payload(id: 'shared'),
      );
      registry.setHighlight(
        ownerPluginId: 'plugin.a',
        ownerInstanceId: i2,
        payload: _payload(id: 'shared'),
      );

      registry.removeInstance(key(i1));

      expect(
        registry.getHighlights(ownerPluginId: 'plugin.a', ownerInstanceId: i1),
        isEmpty,
      );
      expect(
        registry.getHighlights(ownerPluginId: 'plugin.a', ownerInstanceId: i2),
        hasLength(1),
      );
      expect(
        registry.getAllHighlights(bookId: 'book', sectionIndex: 1),
        hasLength(1),
      );
    });

    test('מחיקה ממופע אחד אינה נוגעת בעותק של המופע השני', () {
      registry.setHighlight(
        ownerPluginId: 'plugin.a',
        ownerInstanceId: i1,
        payload: _payload(id: 'shared'),
      );
      registry.setHighlight(
        ownerPluginId: 'plugin.a',
        ownerInstanceId: i2,
        payload: _payload(id: 'shared'),
      );

      expect(
        registry.clearHighlight(
          ownerPluginId: 'plugin.a',
          ownerInstanceId: i1,
          highlightId: 'shared',
        ),
        isTrue,
      );

      expect(
        registry.getAllHighlights(bookId: 'book', sectionIndex: 1),
        hasLength(1),
      );
    });

    test('removePlugin מנקה את כל המופעים', () {
      registry.setHighlight(
        ownerPluginId: 'plugin.a',
        ownerInstanceId: i1,
        payload: _payload(id: 'shared'),
      );
      registry.setHighlight(
        ownerPluginId: 'plugin.a',
        ownerInstanceId: i2,
        payload: _payload(id: 'shared'),
      );

      registry.removePlugin('plugin.a');

      expect(
        registry.getAllHighlights(bookId: 'book', sectionIndex: 1),
        isEmpty,
      );
      expect(
        registry.getHighlights(ownerPluginId: 'plugin.a', ownerInstanceId: i1),
        isEmpty,
      );
      expect(
        registry.getHighlights(ownerPluginId: 'plugin.a', ownerInstanceId: i2),
        isEmpty,
      );
    });
  });

  group('bookUid — מפתח כפול ותאימות לאחור', () {
    test('reanchorSection אינו נוגע בהדגשה של ספר אחר בעל אותה כותרת', () {
      registry.setHighlight(
        ownerPluginId: 'plugin.a',
        payload: _reanchorPayload(id: 'other-book', bookUid: 'uid:10'),
        now: DateTime.utc(2026, 8, 24, 10),
      );
      registry.setHighlight(
        ownerPluginId: 'plugin.a',
        payload: _reanchorPayload(id: 'legacy'),
        now: DateTime.utc(2026, 8, 24, 10),
      );

      final changed = registry.reanchorSection(
        bookId: 'book',
        sectionIndex: 1,
        sourceText: 'prefix before target after',
        bookUid: 'id:10',
        now: DateTime.utc(2026, 8, 24, 11),
      );

      // ההדגשה הזרה הייתה מעוגנת מול טקסט של ספר אחר ומסומנת ככושלת;
      // ההדגשה הישנה (ללא uid) כן מעוגנת מחדש כמקודם.
      expect(changed.map((r) => r.highlightId), ['legacy']);
    });

    test('הדגשה חדשה עם bookUid נמצאת גם דרך הכותרת וגם דרך המזהה', () {
      registry.setHighlight(
        ownerPluginId: 'plugin.a',
        payload: _payload(id: 'h1', bookId: 'ברכות', bookUid: 'id:10'),
        now: DateTime.utc(2026, 8, 24),
      );

      // ציור קיים (כותרת בלבד) — עדיין מוצא אותה: אין רגרסיה.
      expect(
        registry
            .getAllHighlights(bookId: 'ברכות', sectionIndex: 1)
            .single
            .highlightId,
        'h1',
      );
      // ציור מחווט (כותרת + uid) — מוצא אותה גם כן.
      expect(
        registry
            .getAllHighlights(
              bookId: 'ברכות',
              sectionIndex: 1,
              bookUid: 'id:10',
            )
            .single
            .highlightId,
        'h1',
      );
    });

    test('migrate-on-read: הדגשה ישנה (כותרת בלבד) נמצאת גם בציור עם uid', () {
      // נשמרה לפני תמיכת bookUid — אין לה bookUid.
      registry.setHighlight(
        ownerPluginId: 'plugin.a',
        payload: _payload(id: 'old', bookId: 'ברכות'),
        now: DateTime.utc(2026, 8, 24),
      );

      final drawn = registry.getAllHighlights(
        bookId: 'ברכות',
        sectionIndex: 1,
        bookUid: 'id:10',
      );
      expect(drawn.single.highlightId, 'old');
      expect(drawn.single.bookUid, isNull);
    });

    test('שני ספרים באותו שם — bookUid מפריד ביניהם בציור', () {
      registry.setHighlight(
        ownerPluginId: 'plugin.a',
        payload: _payload(id: 'lib', bookId: 'גיטין', bookUid: 'id:10'),
        now: DateTime.utc(2026, 8, 24),
      );
      registry.setHighlight(
        ownerPluginId: 'plugin.a',
        payload: _payload(id: 'usr', bookId: 'גיטין', bookUid: 'uid:10'),
        now: DateTime.utc(2026, 8, 24),
      );

      // ציור הספר הרשמי — רק ההדגשה שלו, לא של הספר האישי בעל אותו שם.
      final libDrawn = registry.getAllHighlights(
        bookId: 'גיטין',
        sectionIndex: 1,
        bookUid: 'id:10',
      );
      expect(libDrawn.map((h) => h.highlightId), ['lib']);

      final usrDrawn = registry.getAllHighlights(
        bookId: 'גיטין',
        sectionIndex: 1,
        bookUid: 'uid:10',
      );
      expect(usrDrawn.map((h) => h.highlightId), ['usr']);
    });

    test('הדגשה עם bookUid מצוירת פעם אחת כשנשאלים שני המפתחות', () {
      registry.setHighlight(
        ownerPluginId: 'plugin.a',
        payload: _payload(id: 'once', bookId: 'ברכות', bookUid: 'id:10'),
        now: DateTime.utc(2026, 8, 24),
      );

      expect(
        registry.getAllHighlights(
          bookId: 'ברכות',
          sectionIndex: 1,
          bookUid: 'id:10',
        ),
        hasLength(1),
      );
    });

    test('הסרת הדגשה עם bookUid מנקה את שני המפתחות', () {
      registry.setHighlight(
        ownerPluginId: 'plugin.a',
        payload: _payload(id: 'rm', bookId: 'ברכות', bookUid: 'id:10'),
        now: DateTime.utc(2026, 8, 24),
      );
      registry.clearHighlight(ownerPluginId: 'plugin.a', highlightId: 'rm');

      expect(
        registry.getAllHighlights(bookId: 'ברכות', sectionIndex: 1),
        isEmpty,
      );
      expect(
        registry.getAllHighlights(
          bookId: 'ברכות',
          sectionIndex: 1,
          bookUid: 'id:10',
        ),
        isEmpty,
      );
    });
  });
}

Map<String, dynamic> _reanchorPayload({required String id, String? bookUid}) =>
    {
      'highlightId': id,
      'bookId': 'book',
      'bookUid': ?bookUid,
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
  String? bookUid,
  int sectionIndex = 1,
}) {
  return {
    'highlightId': ?id,
    'bookId': bookId,
    'bookUid': ?bookUid,
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
