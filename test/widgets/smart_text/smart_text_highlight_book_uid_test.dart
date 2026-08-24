import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';
import 'package:otzaria/plugins/view/plugin_highlight_frame_overlay.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

const _text = 'ראש טקסט סוף';
const _bookTitle = 'גיטין';
const _pluginId = 'plugin.uid.test';

Map<String, dynamic> _payload({required String id, String? bookUid}) => {
  'highlightId': id,
  'bookId': _bookTitle,
  'bookUid': ?bookUid,
  'sectionIndex': 0,
  'range': {
    'type': 'text-range-v1',
    'schemaVersion': 1,
    'sourceTextHash':
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'layer': 'source',
    'start': {'grapheme': 4, 'codePoint': 4, 'utf16': 4},
    'end': {'grapheme': 8, 'codePoint': 8, 'utf16': 8},
    'exactText': 'טקסט',
    'beforeText': {
      'raw': 'ראש ',
      'normalized': 'ראש ',
      'maxGraphemes': 30,
      'actualGraphemes': 4,
      'truncatedAtBoundary': true,
    },
    'afterText': {
      'raw': ' סוף',
      'normalized': ' סוף',
      'maxGraphemes': 30,
      'actualGraphemes': 4,
      'truncatedAtBoundary': true,
    },
    'occurrenceIndexInSection': 0,
    'occurrenceCountInSection': 1,
  },
  'style': {'backgroundColor': '#FFE066'},
};

Widget _wrap(String? bookUid) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      body: SmartTextWidget(
        text: _text,
        settings: const RenderSettings(fontSize: 20),
        highlightBookId: _bookTitle,
        highlightBookUid: bookUid,
        highlightSectionIndex: 0,
      ),
    ),
  ),
);

/// מזהי ההדגשות שצוירו בפועל — נקראים משכבת הציור, לא מהמאגר.
Set<String> _drawnIds(WidgetTester tester) => tester
    .widgetList<PluginHighlightFrameOverlay>(
      find.byType(PluginHighlightFrameOverlay),
    )
    .expand((overlay) => overlay.ranges)
    .map((range) => range.highlight.highlightId)
    .toSet();

void main() {
  setUp(() => PluginHighlightRegistry.instance.removePlugin(_pluginId));
  tearDown(() => PluginHighlightRegistry.instance.removePlugin(_pluginId));

  testWidgets('שני ספרים באותו שם — מצוירת רק ההדגשה של ה-uid שנמסר', (
    tester,
  ) async {
    PluginHighlightRegistry.instance.setHighlight(
      ownerPluginId: _pluginId,
      payload: _payload(id: 'official', bookUid: 'id:10'),
    );
    PluginHighlightRegistry.instance.setHighlight(
      ownerPluginId: _pluginId,
      payload: _payload(id: 'personal', bookUid: 'uid:10'),
    );

    await tester.pumpWidget(_wrap('id:10'));
    await tester.pumpAndSettle();

    expect(_drawnIds(tester), {'official'});
  });

  testWidgets('הדגשה ישנה ללא bookUid ממשיכה להיות מצוירת', (tester) async {
    PluginHighlightRegistry.instance.setHighlight(
      ownerPluginId: _pluginId,
      payload: _payload(id: 'legacy'),
    );

    await tester.pumpWidget(_wrap('id:10'));
    await tester.pumpAndSettle();

    expect(_drawnIds(tester), {'legacy'});
  });

  testWidgets('הדגשה ישנה מצוירת לצד הדגשה חדשה של אותו ספר', (tester) async {
    PluginHighlightRegistry.instance.setHighlight(
      ownerPluginId: _pluginId,
      payload: _payload(id: 'legacy'),
    );
    PluginHighlightRegistry.instance.setHighlight(
      ownerPluginId: _pluginId,
      payload: _payload(id: 'official', bookUid: 'id:10'),
    );
    PluginHighlightRegistry.instance.setHighlight(
      ownerPluginId: _pluginId,
      payload: _payload(id: 'personal', bookUid: 'uid:10'),
    );

    await tester.pumpWidget(_wrap('id:10'));
    await tester.pumpAndSettle();

    expect(_drawnIds(tester), {'legacy', 'official'});
  });

  testWidgets('בלי uid באתר הציור — כל ההדגשות של הכותרת מצוירות', (
    tester,
  ) async {
    PluginHighlightRegistry.instance.setHighlight(
      ownerPluginId: _pluginId,
      payload: _payload(id: 'official', bookUid: 'id:10'),
    );
    PluginHighlightRegistry.instance.setHighlight(
      ownerPluginId: _pluginId,
      payload: _payload(id: 'personal', bookUid: 'uid:10'),
    );

    await tester.pumpWidget(_wrap(null));
    await tester.pumpAndSettle();

    expect(_drawnIds(tester), {'official', 'personal'});
  });
}
