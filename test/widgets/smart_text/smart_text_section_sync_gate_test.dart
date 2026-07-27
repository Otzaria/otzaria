import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';
import 'package:otzaria/plugins/services/reader_section_content_tracker.dart';
import 'package:otzaria/plugins/services/reader_section_sync_gate.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

const _text = 'prefix before target after';
const _settings = RenderSettings(fontSize: 20);

/// סופר כל סנכרון בפועל — זו התופעה שהשער אמור למנוע, ולכן זה מה שנמדד.
class _CountingTracker extends ReaderSectionContentTracker {
  _CountingTracker() : super.forTesting(dispatchEvent: _ignore);

  static Future<void> _ignore(
    String topic,
    Map<String, dynamic> payload,
  ) async {}

  int snapshots = 0;

  @override
  Future<PluginSectionContentChange?> recordSnapshot({
    required String bookId,
    required int sectionIndex,
    required String sourceText,
    String? renderedText,
    Object? renderingSignature,
    String? reason,
  }) {
    snapshots++;
    return super.recordSnapshot(
      bookId: bookId,
      sectionIndex: sectionIndex,
      sourceText: sourceText,
      renderedText: renderedText,
      renderingSignature: renderingSignature,
      reason: reason,
    );
  }
}

Widget _wrap(Widget child) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(body: child),
  ),
);

Widget _section({
  String text = _text,
  String? sourceText,
  RenderSettings settings = _settings,
  String? bookId = 'book',
  int? sectionIndex = 1,
}) {
  return SmartTextWidget(
    text: text,
    settings: settings,
    highlightBookId: bookId,
    highlightSectionIndex: sectionIndex,
    highlightSourceText: sourceText,
  );
}

void main() {
  late _CountingTracker tracker;
  late ReaderSectionContentTracker original;

  setUp(() {
    original = ReaderSectionContentTracker.instance;
    tracker = _CountingTracker();
    ReaderSectionContentTracker.instance = tracker;
    ReaderSectionSyncGate.instance.clear();
    PluginHighlightRegistry.instance.removePlugin('plugin.test');
  });

  tearDown(() {
    PluginHighlightRegistry.instance.removePlugin('plugin.test');
    ReaderSectionSyncGate.instance.clear();
    ReaderSectionContentTracker.instance = original;
  });

  group('השער נאכף בפועל', () {
    testWidgets('בנייה חוזרת מסנכרנת פעם אחת בלבד', (tester) async {
      await tester.pumpWidget(_wrap(_section()));
      await tester.pumpAndSettle();
      expect(tracker.snapshots, 1);

      for (var i = 0; i < 20; i++) {
        await tester.pumpWidget(_wrap(_section()));
        await tester.pump();
      }

      expect(
        tracker.snapshots,
        1,
        reason: '20 בניות חוזרות עם קלט זהה חייבות להיחסם',
      );
    });

    testWidgets('בלי bookId/sectionIndex אין סנכרון כלל', (tester) async {
      await tester.pumpWidget(
        _wrap(_section(bookId: null, sectionIndex: null)),
      );
      await tester.pumpAndSettle();

      expect(tracker.snapshots, 0);
      expect(ReaderSectionSyncGate.instance.trackedSections, 0);
    });

    testWidgets('כל קטע מסתנכרן בנפרד, פעם אחת', (tester) async {
      Widget twoSections() => _wrap(
        Column(
          children: [
            _section(sectionIndex: 1),
            _section(text: 'שורה שנייה', sectionIndex: 2),
          ],
        ),
      );

      await tester.pumpWidget(twoSections());
      await tester.pumpAndSettle();
      expect(tracker.snapshots, 2);

      await tester.pumpWidget(twoSections());
      await tester.pumpAndSettle();
      expect(tracker.snapshots, 2);
    });
  });

  group('מה מחייב סנכרון מחדש', () {
    testWidgets('שינוי הטקסט', (tester) async {
      await tester.pumpWidget(_wrap(_section()));
      await tester.pumpAndSettle();
      expect(tracker.snapshots, 1);

      await tester.pumpWidget(_wrap(_section(text: 'טקסט אחר לגמרי')));
      await tester.pumpAndSettle();

      expect(tracker.snapshots, 2);
    });

    testWidgets('שינוי גודל גופן — לא נוגע בטקסט אך כן ברינדור', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(_section()));
      await tester.pumpAndSettle();
      expect(tracker.snapshots, 1);

      await tester.pumpWidget(
        _wrap(_section(settings: const RenderSettings(fontSize: 40))),
      );
      await tester.pumpAndSettle();

      expect(tracker.snapshots, 2);
    });

    testWidgets('הסרת ניקוד משנה את התוצר', (tester) async {
      const withNikud = 'בְּרֵאשִׁית בָּרָא';
      await tester.pumpWidget(_wrap(_section(text: withNikud)));
      await tester.pumpAndSettle();
      expect(tracker.snapshots, 1);

      await tester.pumpWidget(
        _wrap(
          _section(
            text: withNikud,
            settings: const RenderSettings(fontSize: 20, removeNikud: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tracker.snapshots, 2);
    });

    // התצוגה המשולבת מעבירה text עם סימוני הערות/קישורים מול מקור גולמי נפרד.
    testWidgets('סימון נוסף לשורה כשהמקור הגולמי לא זז', (tester) async {
      await tester.pumpWidget(
        _wrap(_section(text: 'טקסט', sourceText: 'טקסט')),
      );
      await tester.pumpAndSettle();
      expect(tracker.snapshots, 1);

      await tester.pumpWidget(
        _wrap(_section(text: 'טקסט <b>סימון</b>', sourceText: 'טקסט')),
      );
      await tester.pumpAndSettle();

      expect(tracker.snapshots, 2, reason: 'התוצר השתנה — חייב סנכרון');
    });

    testWidgets('מקור גולמי זהה ו-text זהה נחסמים', (tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.pumpWidget(
          _wrap(_section(text: 'טקסט <b>סימון</b>', sourceText: 'טקסט')),
        );
        await tester.pumpAndSettle();
      }

      expect(tracker.snapshots, 1);
    });
  });

  group('התנהגות התוספים נשמרת', () {
    testWidgets('highlight שנוסף אחרי הרינדור הראשון עדיין מקבל עיגון', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(_section()));
      await tester.pumpAndSettle();
      expect(tracker.snapshots, 1);

      final created = PluginHighlightRegistry.instance.setHighlight(
        ownerPluginId: 'plugin.test',
        payload: _anchorPayload(),
      );
      expect(created.range.start.grapheme, 7, reason: 'מיקום מקורי שגוי');

      await tester.pumpAndSettle();

      final anchored = PluginHighlightRegistry.instance
          .getHighlights(ownerPluginId: 'plugin.test')
          .single;
      expect(anchored.status, 'active');
      expect(anchored.range.exactText, 'target');
      // 'target' יושב בפועל ב-14, לא ב-7 שנרשם בעוגן.
      expect(anchored.range.start.grapheme, 14);
      expect(anchored.version, greaterThan(created.version));
    });

    testWidgets('הסרת highlight פותחת את השער מחדש', (tester) async {
      PluginHighlightRegistry.instance.setHighlight(
        ownerPluginId: 'plugin.test',
        payload: _anchorPayload(),
      );
      await tester.pumpWidget(_wrap(_section()));
      await tester.pumpAndSettle();
      final afterFirst = tracker.snapshots;

      PluginHighlightRegistry.instance.clearHighlight(
        ownerPluginId: 'plugin.test',
        highlightId: 'marker-1',
      );
      await tester.pumpAndSettle();

      expect(tracker.snapshots, greaterThan(afterFirst));
    });

    testWidgets('העיגון מתכנס ולא רץ בלולאה אינסופית', (tester) async {
      PluginHighlightRegistry.instance.setHighlight(
        ownerPluginId: 'plugin.test',
        payload: _anchorPayload(),
      );

      await tester.pumpWidget(_wrap(_section()));
      await tester.pumpAndSettle();

      final settledRevision = PluginHighlightRegistry.instance.revision;
      final settledSnapshots = tracker.snapshots;
      for (var i = 0; i < 10; i++) {
        await tester.pumpWidget(_wrap(_section()));
        await tester.pump();
      }

      expect(PluginHighlightRegistry.instance.revision, settledRevision);
      expect(tracker.snapshots, settledSnapshots);
    });
  });
}

Map<String, dynamic> _anchorPayload() => {
  'highlightId': 'marker-1',
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
  'style': {'backgroundColor': '#FFFF00'},
};
