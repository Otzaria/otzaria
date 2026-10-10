import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_search_field_action.dart';
import 'package:otzaria/plugins/services/plugin_search_field_session_service.dart';

typedef _Sent = ({
  String pluginId,
  String topic,
  Map<String, dynamic> payload,
  bool preferBackground,
  String? instanceId,
});

/// שדה מדומה: controller אמיתי, ומאזין שמדווח לשירות כמו הווידג'ט.
class _FakeField implements PluginSearchFieldBinding {
  _FakeField(this.service, {String text = '', TextSelection? selection})
    : controller = TextEditingController.fromValue(
        TextEditingValue(
          text: text,
          selection: selection ?? TextSelection.collapsed(offset: text.length),
        ),
      ) {
    controller.addListener(
      () => service.onFieldTextChanged(this, controller.text),
    );
  }

  final PluginSearchFieldSessionService service;
  final TextEditingController controller;
  final List<String> changes = [];
  int submits = 0;

  @override
  PluginSearchField get field => PluginSearchField.library;

  @override
  TextEditingValue get currentValue => controller.value;

  @override
  void applyPluginText(TextEditingValue value) {
    controller.value = value;
    changes.add(value.text);
  }

  @override
  void submit() => submits++;
}

void main() {
  late List<_Sent> sent;
  late PluginSearchFieldSessionService service;

  setUp(() {
    sent = [];
    service = PluginSearchFieldSessionService.forTesting((
      pluginId,
      topic,
      payload, {
      preferBackground = false,
      instanceId,
    }) async {
      sent.add((
        pluginId: pluginId,
        topic: topic,
        payload: payload,
        preferBackground: preferBackground,
        instanceId: instanceId,
      ));
    });
  });

  Future<String> invoke(
    _FakeField field, {
    String pluginId = 'voice',
    String actionId = 'dictate',
  }) async {
    await field.service.press(
      binding: field,
      pluginId: pluginId,
      actionId: actionId,
    );
    return sent.last.payload['sessionId'] as String;
  }

  List<_Sent> ended() =>
      sent.where((e) => e.topic == 'search.fieldAction.ended').toList();

  test('לחיצה שולחת invoked עם מצב השדה ומעירה את הרקע', () async {
    final field = _FakeField(
      service,
      text: 'ברכות שבת',
      selection: const TextSelection(baseOffset: 6, extentOffset: 9),
    );
    await invoke(field);

    expect(sent.single.topic, 'search.fieldAction.invoked');
    expect(sent.single.preferBackground, isTrue);
    expect(sent.single.payload, {
      'actionId': 'dictate',
      'sessionId': sent.single.payload['sessionId'],
      'field': 'library',
      'text': 'ברכות שבת',
      'selectionStart': 6,
      'selectionEnd': 9,
    });
    expect(sent.single.payload['sessionId'], startsWith('s_'));
  });

  test(
    'setFieldText מרכיב before + text + after עם רווח מפריד, בלי לסגור',
    () async {
      final field = _FakeField(
        service,
        text: 'ברכות שבת',
        selection: const TextSelection(baseOffset: 6, extentOffset: 9),
      );
      final id = await invoke(field);

      service.setFieldText('voice', id, 'פסחים');
      expect(field.controller.text, 'ברכות פסחים');
      service.setFieldText('voice', id, 'פסחים דף ב');
      expect(field.controller.text, 'ברכות פסחים דף ב');
      expect(field.controller.selection.baseOffset, 'ברכות פסחים דף ב'.length);
      expect(ended(), isEmpty);
    },
  );

  test('טקסט באמצע השדה מקבל רווח משני הצדדים', () {
    final value = PluginSearchFieldSessionService.compose('אב', 'גד', 'הו');
    expect(value.text, 'אב גד הו');
    expect(value.selection.baseOffset, 'אב גד'.length);
  });

  test('בחירה לא תקינה = הוספה בסוף השדה', () async {
    final field = _FakeField(
      service,
      text: 'ברכות',
      selection: const TextSelection.collapsed(offset: -1),
    );
    final id = await invoke(field);
    service.setFieldText('voice', id, 'דף ב');
    expect(field.controller.text, 'ברכות דף ב');
  });

  test('עריכת משתמש מסיימת את הסשן (edited) והקריאה הבאה נדחית', () async {
    final field = _FakeField(service, text: '');
    final id = await invoke(field);
    service.setFieldText('voice', id, 'שבת');

    field.controller.text = 'שבתות';

    expect(ended().single.payload['reason'], 'edited');
    expect(
      () => service.setFieldText('voice', id, 'אחר'),
      throwsA(
        isA<PluginSearchFieldSessionException>().having(
          (e) => e.code,
          'code',
          'error.not_found',
        ),
      ),
    );
    expect(field.controller.text, 'שבתות');
  });

  test('שינוי בחירה בלבד אינו נחשב עריכה', () async {
    final field = _FakeField(service, text: 'שבת');
    await invoke(field);
    field.controller.selection = const TextSelection.collapsed(offset: 0);
    expect(ended(), isEmpty);
  });

  test('תוסף אחר לא יכול להשתמש בסשן, וסשן מומצא לא קיים', () async {
    final field = _FakeField(service);
    final id = await invoke(field);

    for (final call in [
      () => service.setFieldText('other.plugin', id, 'x'),
      () => service.setFieldText('voice', 's_unknown', 'x'),
      () => service.setActionState('other.plugin', id, 'active'),
      () => service.endSession('other.plugin', id),
    ]) {
      expect(
        call,
        throwsA(
          isA<PluginSearchFieldSessionException>().having(
            (e) => e.code,
            'code',
            'error.not_found',
          ),
        ),
      );
    }
    expect(field.changes, isEmpty);
  });

  test('המופע הראשון שקורא נועל את הסשן', () async {
    final field = _FakeField(service);
    final id = await invoke(field);
    service.setFieldText('voice', id, 'א', instanceId: 'background');
    expect(
      () => service.setFieldText('voice', id, 'ב', instanceId: 'tab-1'),
      throwsA(isA<PluginSearchFieldSessionException>()),
    );
    service.endSession('voice', id, instanceId: 'background');
    expect(ended().single.instanceId, 'background');
  });

  test('טקסט ארוך מדי וקישורים נדחים; תווי בקרה הופכים לרווח', () async {
    final field = _FakeField(service);
    final id = await invoke(field);
    for (final text in ['א' * 1001, 'otzaria://open/plugin/x']) {
      expect(
        () => service.setFieldText('voice', id, text),
        throwsA(
          isA<PluginSearchFieldSessionException>().having(
            (e) => e.code,
            'code',
            'error.invalid_params',
          ),
        ),
      );
    }
    expect(field.changes, isEmpty);
    service.setFieldText('voice', id, 'שורה\nשנייה');
    expect(field.controller.text, 'שורה שנייה');
  });

  test('לחיצה שנייה שולחת stopRequested ואינה סוגרת', () async {
    final field = _FakeField(service);
    final id = await invoke(field);
    await service.press(binding: field, pluginId: 'voice', actionId: 'dictate');

    expect(sent.last.topic, 'search.fieldAction.stopRequested');
    expect(sent.last.payload, {'actionId': 'dictate', 'sessionId': id});
    expect(service.sessionFor(field, 'voice', 'dictate')?.id, id);
  });

  test('endSession עם submit מסיים (plugin) ומריץ חיפוש', () async {
    final field = _FakeField(service);
    final id = await invoke(field);
    service.endSession('voice', id, submit: true);

    expect(ended().single.payload['reason'], 'plugin');
    expect(field.submits, 1);
    expect(service.hasSessionsFor(field), isFalse);
  });

  test('סשן חדש של אותו תוסף בשדה אחר מחליף את הקודם', () async {
    final first = _FakeField(service);
    final second = _FakeField(service);
    final firstId = await invoke(first);
    await invoke(second);

    expect(ended().single.payload, {
      'actionId': 'dictate',
      'sessionId': firstId,
      'reason': 'replaced',
    });
    expect(service.hasSessionsFor(first), isFalse);
    expect(service.hasSessionsFor(second), isTrue);
  });

  test('סגירת השדה מסיימת את הסשן (closed)', () async {
    final field = _FakeField(service);
    final id = await invoke(field);
    service.onBindingDisposed(field);

    expect(ended().single.payload['reason'], 'closed');
    expect(
      () => service.setFieldText('voice', id, 'x'),
      throwsA(isA<PluginSearchFieldSessionException>()),
    );
  });

  test('השבתת התוסף או סגירת המופע המחובר מסיימות את הסשן', () async {
    final field = _FakeField(service);
    final id = await invoke(field);
    service.setFieldText('voice', id, 'x', instanceId: 'background');

    service.onInstanceUnregistered('voice', 'tab-1', pluginHasEngine: true);
    expect(ended(), isEmpty);
    service.onInstanceUnregistered(
      'voice',
      'background',
      pluginHasEngine: true,
    );
    expect(ended().single.payload['reason'], 'closed');

    final id2 = await invoke(field);
    service.removePlugin('voice');
    expect(ended().last.payload['sessionId'], id2);
  });

  test('setFieldActionState מאמת את הערכים ושומר אותם', () async {
    final field = _FakeField(service);
    final id = await invoke(field);
    expect(
      () => service.setActionState('voice', id, 'recording'),
      throwsA(isA<PluginSearchFieldSessionException>()),
    );
    service.setActionState('voice', id, 'active', tooltip: 'מקשיב');
    final session = service.sessionFor(field, 'voice', 'dictate')!;
    expect(session.state, PluginSearchFieldActionState.active);
    expect(session.tooltip, 'מקשיב');
  });
}
