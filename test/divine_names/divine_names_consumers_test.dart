import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/plugins/models/text_source_map.dart';
import 'package:otzaria/plugins/services/text_source_map_service.dart';
import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut.dart';
import 'package:otzaria/text_book/view/selection/selected_text_copy.dart';
import 'package:otzaria/text_display/models/text_display_layer.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/text_display/models/text_display_slot.dart';
import 'package:otzaria/text_display/text_display_resolver.dart';
import 'package:otzaria/utils/text/html_slice.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

/// מי שקורא את הטקסט המוצג אחרי ההחלפה: העתקת בחירה (חיתוך HTML), מפת
/// המקור של התוספים, ושמירת ההגדרה בפרופיל ובקיצור דינמי. האדנות היא הצורה
/// היחידה שמאריכה את הטקסט (מקף), ולכן נבדקת בכל אחד מהם.
void main() {
  const adnutNikud = 'אֲדֹנָי';
  const adnutShown = 'אֲדֹ-נָי';
  const line = '<b>ויאמר</b> $adnutNikud אלהים';
  final spans =
      (DivineNameSpansBuilder()
            ..add(0, 6, 6 + adnutNikud.length, DivineNameKind.adnut)
            ..add(0, 7 + adnutNikud.length, 12 + adnutNikud.length, 5))
          .build();
  const substitute = RenderSettings(
    substituteDivineNames: true,
    formatParentheses: false,
  );

  String shown() => TextRendererService.processText(
    injectDivineNameMarkers(line, spans, 0),
    substitute,
  );

  test('הקלט של הבדיקות — השורה מוצגת בכינויים', () {
    expect(shown(), '<b>ויאמר</b> $adnutShown אלקים');
  });

  group('חיתוך HTML לבחירה', () {
    test('אדנות עם מקף וניקוד — הבחירה נמצאת במקור', () {
      expect(
        sliceHtmlBySelection(
          html: '<b>אמר</b> אדני',
          selectedText: 'אמר אד-ני',
        ),
        '<b>אמר</b> אד-ני',
      );
      expect(
        sliceHtmlBySelection(
          html: '<b>אמר</b> $adnutNikud',
          selectedText: 'אמר $adnutShown',
        ),
        '<b>אמר</b> $adnutShown',
      );
    });

    test('בחירה מהמסך עם כינוי — HTML מעוצב כשהמופעים ידועים', () {
      const selection = 'ויאמר $adnutShown אלקים';
      expect(
        resolveHtmlTextForSelection(
          plainText: selection,
          selectedIndex: 0,
          sourceContent: const [line],
          divineNames: spans,
        ),
        '<b>ויאמר</b> $adnutShown אלקים',
      );
      // בלי המופעים — הבחירה אינה נמצאת בשורה, ומועתק הטקסט שעל המסך.
      expect(
        resolveHtmlTextForSelection(
          plainText: selection,
          selectedIndex: 0,
          sourceContent: const [line],
        ),
        selection,
      );
    });

    test('סמני השמות בשורה אינם שוברים את החיתוך', () {
      final marked = injectDivineNameMarkers(line, spans, 0);
      expect(
        sliceHtmlBySelection(html: marked, selectedText: 'ויאמר'),
        '<b>ויאמר</b>',
      );
    });
  });

  test('מפת המקור של התוספים — המקף ממופה כהוספה, השאר בלי היסט', () {
    const service = TextSourceMapService();
    final map = service.buildFromProcessedHtml(
      bookId: 'book',
      sectionIndex: 0,
      rawText: line,
      processedHtml: shown(),
    );
    expect(map.sourceText, 'ויאמר $adnutNikud אלהים');
    expect(map.renderedText, 'ויאמר $adnutShown אלקים');
    expect(
      map.mappings.map((m) => m.kind),
      contains(PluginTextSourceMapKind.inserted),
    );
    // "ויאמר" בתחילה ו-"ים" בסוף ממופים לעצמם.
    expect(service.sourceBoundaryToRendered(map, 5), 5);
    expect(
      service.renderedBoundaryToSource(map, map.renderedGraphemeLength),
      map.sourceGraphemeLength,
    );
    expect(map.renderedGraphemeLength, map.sourceGraphemeLength + 1);
  });

  group('הגדרת התצוגה', () {
    test('ברירת המחדל כבויה, ונשמרת ב-JSON של הטלאי', () {
      expect(TextDisplayProfile.defaults.substituteDivineNames, isFalse);
      const patch = TextDisplayPatch(
        divineNames: DivineNamesDisplay.substitute,
      );
      expect(TextDisplayPatch.fromJson(patch.toJson()), patch);
      expect(
        TextDisplayPatch.fromJson({'divineNames': 'bogus'}).divineNames,
        isNull,
      );
      expect(
        patch.pruneAgainst(
          const TextDisplayProfile(divineNames: DivineNamesDisplay.substitute),
        ),
        TextDisplayPatch.empty,
      );
    });

    test('המפרשים יורשים את ההגדרה מהשורש', () {
      final profile = TextDisplayResolver.resolve(
        slot: TextDisplaySlot.commentaryDisplay,
        layers: [
          TextDisplayLayer({
            TextDisplaySlot.root: const TextDisplayPatch(
              divineNames: DivineNamesDisplay.substitute,
            ),
          }),
        ],
      );
      expect(profile.substituteDivineNames, isTrue);
    });

    test('קיצור דינמי — השינוי נשמר ומוחל', () {
      const change = DynamicDisplayChange(
        divineNames: DivineNamesDisplay.substitute,
      );
      expect(DynamicDisplayChange.fromJson(change.toJson()), change);
      expect(change.isEmpty, isFalse);
      expect(
        change.patchFor(TextDisplayProfile.defaults).divineNames,
        DivineNamesDisplay.substitute,
      );
    });
  });
}
