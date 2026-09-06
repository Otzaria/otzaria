import 'dart:isolate';
import 'dart:ui' as ui show IsolateNameServer;

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/settings_sync.dart';
import 'package:otzaria/core/windowing/window_bus.dart';

/// ⚠️ קידומת ייחודית לסוויטה — [ui.IsolateNameServer] גלובלי לתהליך.
const String _namespace = 'otzaria.test.settingssync';

void main() {
  late _FakePeer peer;
  late Map<String, Object?> applied;

  setUp(() {
    WindowBus.namespace = _namespace;
    applied = {};
    SettingsSync.instance.applyLocally = (key, value) async {
      applied[key] = value;
    };
    peer = _FakePeer(2)..register();
    WindowBus.instance.register();
  });

  tearDown(() {
    SettingsSync.instance.dispose();
    SettingsSync.instance.applyLocally = null;
    peer.dispose();
    WindowBus.instance.unregister();
    for (var i = 1; i <= WindowBus.slotCount; i++) {
      ui.IsolateNameServer.removePortNameMapping('$_namespace.$i');
    }
    WindowBus.namespace = 'otzaria.window';
  });

  test('שינוי הגדרה משודר לחלונות האחרים', () async {
    SettingsSync.instance.broadcastChange('key-dark-mode', true);

    await peer.nextMessage;
    expect(peer.received, [
      {'key': 'key-dark-mode', 'value': true},
    ]);
  });

  test('כתיבות רצופות מקובצות — רק האחרונה משודרת', () async {
    // ⚠️ גרירת מחוון גודל גופן כותבת עשרות פעמים בשנייה, וכל כתיבה הייתה
    // שידור לשלושה חלונות.
    for (final size in [16.0, 17.0, 18.0, 19.0]) {
      SettingsSync.instance.broadcastChange('key-font-size', size);
    }

    await peer.nextMessage;
    expect(peer.received, [
      {'key': 'key-font-size', 'value': 19.0},
    ]);
  });

  test('הודעה נכנסת מוחלת מקומית ואינה משודרת בחזרה', () async {
    // ⚠️ בלי הגידור הזה החלת שינוי מרוחק הייתה עוברת דרך ה-setters,
    // משודרת בחזרה, מוחלת שוב — לופ.
    final handled = await SettingsSync.instance.handleRequest({
      'type': SettingsSync.requestChanged,
      'key': 'key-dark-mode',
      'value': true,
    });

    expect(handled, isTrue);
    expect(applied['key-dark-mode'], isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(peer.received, isEmpty);
  });

  test('שינוי מרוחק מדווח על המפתח למי שמאזין', () async {
    final seen = <String>[];
    final sub = SettingsSync.instance.changes.listen(seen.add);
    addTearDown(sub.cancel);

    await SettingsSync.instance.handleRequest({
      'type': SettingsSync.requestChanged,
      'key': 'key-seed-color',
      'value': 4283215696,
    });

    expect(seen, ['key-seed-color']);
  });

  test('ערך null מוחל כמחיקה', () async {
    await SettingsSync.instance.handleRequest({
      'type': SettingsSync.requestChanged,
      'key': 'key-removed',
      'value': null,
    });
    expect(applied.containsKey('key-removed'), isTrue);
    expect(applied['key-removed'], isNull);
  });

  test('ערך שאינו עובר את גבול ה-isolate אינו משודר', () async {
    // עדיף מפתח שאינו מסונכרן על ערך שנכתב שבור בצד השני.
    SettingsSync.instance.broadcastChange('key-weird', DateTime(2026));

    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(peer.received, isEmpty);
  });

  test('גבולות חלון ומצב מיקסום אינם משודרים', () async {
    // ⚠️ אלה מצב של חלון ולא הגדרה של התוכנה. שידורם היה מזיז חלון אחד
    // בכל פעם שהמשתמש מזיז את השני.
    SettingsSync.instance.broadcastChange('window_bounds_left', 120.0);
    SettingsSync.instance.broadcastChange('window_bounds_width', 900.0);
    SettingsSync.instance.broadcastChange('window_is_maximized', true);

    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(peer.received, isEmpty);
  });

  test('מצב מסך מלא אינו משודר', () async {
    // ⚠️ המפתח אינו נושא את התחילית `window_is_`. שידורו הפשיט את סרגל
    // הכותרת בחלונות האחרים בלי ששום מעבר נייטיב קרה.
    SettingsSync.instance.broadcastChange('key-is-fullscreen', true);

    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(peer.received, isEmpty);
  });

  test('בקשה שאינה שלנו מוחזרת כ-null', () async {
    expect(
      await SettingsSync.instance.handleRequest({'type': 'somethingElse'}),
      isNull,
    );
  });
}

/// חלון מדומה שקולט שידורים.
class _FakePeer {
  _FakePeer(this.slot);

  final int slot;
  final List<Map<String, Object?>> received = [];
  late final ReceivePort _port;

  Future<void> get nextMessage async {
    for (var i = 0; i < 40; i++) {
      if (received.isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  void register() {
    _port = ReceivePort();
    ui.IsolateNameServer.registerPortWithName(
      _port.sendPort,
      '$_namespace.$slot',
    );
    _port.listen((message) {
      final map = message as Map;
      final body = Map<String, dynamic>.from(map['body'] as Map);
      if (body['type'] == SettingsSync.requestChanged) {
        received.add({'key': body['key'], 'value': body['value']});
      }
      (map['reply'] as SendPort).send({'ok': true, 'result': true});
    });
  }

  void dispose() {
    ui.IsolateNameServer.removePortNameMapping('$_namespace.$slot');
    _port.close();
  }
}
