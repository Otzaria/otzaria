import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/services/plugin_restore_state_store.dart';

void main() {
  const key = (pluginId: 'p', instanceId: 'i1');
  final store = PluginRestoreStateStore.instance;

  tearDown(() => store.remove(key));

  test('שומר ומחזיר ערך JSON', () {
    store.set(key, {'screen': 'list', 'top': 120});
    expect(store.has(key), isTrue);
    expect(store.stateOf(key), {'screen': 'list', 'top': 120});
    expect(store.jsonOf(key), '{"screen":"list","top":120}');
  });

  test('null מוחק', () {
    store.set(key, 1);
    store.set(key, null);
    expect(store.has(key), isFalse);
    expect(store.stateOf(key), isNull);
  });

  test('ערך גדול מ-64KB נדחה ואינו מחליף את הקיים', () {
    store.set(key, 'small');
    expect(
      () => store.set(key, 'x' * PluginRestoreStateStore.maxStateBytes),
      throwsArgumentError,
    );
    expect(store.stateOf(key), 'small');
    expect(store.canDiscard(key), isFalse);
    store.set(key, 'current');
    expect(store.canDiscard(key), isTrue);
  });

  test('ערך שאינו JSON נדחה', () {
    store.set(key, {'version': 1});
    expect(() => store.set(key, Object()), throwsArgumentError);
    expect(store.stateOf(key), {'version': 1});
    expect(store.canDiscard(key), isFalse);
  });

  test('זריעה מסשן מתעלמת מ-JSON פגום', () {
    store.seed(key, '{not json');
    expect(store.has(key), isFalse);
    store.seed(key, '[1,2]');
    expect(store.stateOf(key), [1, 2]);
  });

  test('null מקודד אינו הופך דף ללא מצב למועמד לפינוי', () {
    store.seed(key, 'null');
    expect(store.has(key), isFalse);
    expect(store.canDiscard(key), isFalse);
  });

  test('removeInstanceId מוחק לפי מזהה המופע בלבד', () {
    const other = (pluginId: 'q', instanceId: 'reader-1');
    store.set(other, true);
    store.removeInstanceId('reader-1');
    expect(store.has(other), isFalse);
  });

  test('המפתח הוא PluginInstanceKey', () {
    const PluginInstanceKey typed = key;
    store.set(typed, 'v');
    expect(store.stateOf(key), 'v');
  });

  group('גבול כולל', () {
    PluginInstanceKey k(int i) => (pluginId: 'bound', instanceId: 'i$i');
    tearDown(() {
      for (var i = 0; i < 200; i++) {
        store.remove(k(i));
      }
      store.remove(k(999));
    });

    test('מעבר למספר הרשומות — הוותיק נמחק', () {
      for (var i = 0; i <= PluginRestoreStateStore.maxEntries; i++) {
        store.set(k(i), i);
      }
      expect(store.length, PluginRestoreStateStore.maxEntries);
      expect(store.has(k(0)), isFalse);
      expect(store.has(k(PluginRestoreStateStore.maxEntries)), isTrue);
    });

    test('עדכון מחזיר רשומה לסוף התור', () {
      for (var i = 0; i < PluginRestoreStateStore.maxEntries; i++) {
        store.set(k(i), i);
      }
      store.set(k(0), 'again');
      store.set(k(999), 'new');
      expect(store.has(k(0)), isTrue);
      expect(store.has(k(1)), isFalse);
    });

    test('מעבר לגודל הכולל — נמחקים ותיקים עד שחוזרים לגבול', () {
      final big = 'x' * (PluginRestoreStateStore.maxStateBytes - 10);
      for (var i = 0; i < 40; i++) {
        store.seed(k(i), '"$big"');
      }
      expect(
        store.totalBytes,
        lessThanOrEqualTo(PluginRestoreStateStore.maxTotalBytes),
      );
      expect(store.has(k(39)), isTrue);
      expect(store.has(k(0)), isFalse);
      store.remove(k(39));
      expect(store.has(k(39)), isFalse);
    });
  });

  group('מצב של דף שפונה', () {
    PluginInstanceKey k(int i) => (pluginId: 'retained', instanceId: 'i$i');

    tearDown(() {
      for (var i = 0; i <= PluginRestoreStateStore.maxEntries + 2; i++) {
        store.remove(k(i));
      }
    });

    void fillCache() {
      for (var i = 0; i < PluginRestoreStateStore.maxEntries; i++) {
        store.set(k(i), i);
      }
    }

    test('מצב שמור וגרסתו שורדים לחץ LRU עד השלמת השחזור', () {
      store.set(key, {
        'schemaVersion': 2,
        'documentId': 'draft-1',
        'selection': {'start': 8, 'end': 12},
      });
      final encoded = store.jsonOf(key);
      final token = store.retain(key);
      expect(token, isNotNull);
      fillCache();
      expect(store.jsonOf(key), encoded);
      expect(store.stateOf(key), {
        'schemaVersion': 2,
        'documentId': 'draft-1',
        'selection': {'start': 8, 'end': 12},
      });
      expect(
        store.length,
        lessThanOrEqualTo(PluginRestoreStateStore.maxEntries),
      );
      expect(
        store.totalBytes,
        lessThanOrEqualTo(PluginRestoreStateStore.maxTotalBytes),
      );
      store.releaseRetention(key, token!);
      store.set(k(PluginRestoreStateStore.maxEntries), 'new');
      expect(store.has(key), isFalse);
    });

    test('תשובת boot ישנה אינה משחררת את השמירה החדשה', () {
      store.set(key, {'version': 1});
      final oldToken = store.retain(key)!;
      final currentToken = store.retain(key)!;
      store.releaseRetention(key, oldToken);
      fillCache();
      expect(store.has(key), isTrue);
      store.releaseRetention(key, currentToken);
      store.set(k(PluginRestoreStateStore.maxEntries), 'new');
      expect(store.has(key), isFalse);
    });

    test('עדכון מצב שומר על השמירה ומוסר את הגרסה החדשה', () {
      store.set(key, {'schemaVersion': 1, 'revision': 1});
      final token = store.retain(key)!;
      store.set(key, {'schemaVersion': 2, 'revision': 2});
      fillCache();
      expect(store.stateOf(key), {'schemaVersion': 2, 'revision': 2});
      store.releaseRetention(key, token);
    });

    test('כשכל הרשומות שמורות הכתיבה נדחית בלי למחוק שום מצב', () {
      for (var i = 0; i < PluginRestoreStateStore.maxEntries; i++) {
        store.set(k(i), {'version': i});
        store.retain(k(i));
      }
      final bytes = store.totalBytes;
      expect(() => store.set(key, {'version': 99}), throwsArgumentError);
      expect(store.has(key), isFalse);
      expect(store.length, PluginRestoreStateStore.maxEntries);
      expect(store.totalBytes, bytes);
      for (var i = 0; i < PluginRestoreStateStore.maxEntries; i++) {
        expect(store.stateOf(k(i)), {'version': i});
      }
      store.seed(key, '{"version":99}');
      expect(store.has(key), isFalse);
      expect(store.totalBytes, bytes);
    });

    test('עדכון שנדחה אינו מוחק קורבנות חלקיים ואוסר פינוי עם מצב ישן', () {
      store.set(key, 'previous');
      store.retain(key);
      store.set(k(0), 'spare');
      final big = 'x' * (PluginRestoreStateStore.maxStateBytes - 10);
      for (var i = 1; i <= 32; i++) {
        store.set(k(i), big);
        store.retain(k(i));
      }
      final bytes = store.totalBytes;
      final count = store.length;
      expect(() => store.set(key, big), throwsArgumentError);
      expect(store.stateOf(key), 'previous');
      expect(store.canDiscard(key), isFalse);
      expect(store.stateOf(k(0)), 'spare');
      expect(store.totalBytes, bytes);
      expect(store.length, count);
      store.set(key, 'current');
      expect(store.canDiscard(key), isTrue);
    });

    test('סגירה מנקה שמירה וה-token הישן אינו פוגע במופע החדש', () {
      store.set(key, 'old');
      final oldToken = store.retain(key)!;
      store.remove(key);
      expect(store.retain(key), isNull);
      store.set(key, 'replacement');
      final currentToken = store.retain(key)!;
      store.releaseRetention(key, oldToken);
      fillCache();
      expect(store.stateOf(key), 'replacement');
      store.releaseRetention(key, currentToken);
    });
  });
}
