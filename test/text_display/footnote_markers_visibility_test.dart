import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart';
import 'package:otzaria/text_book/utils/numbered_note_markers.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

void main() {
  group('hide footnote markers separately (issue #4389)', () {
    const hidden = TextDisplayProfile(footnoteMarkers: MarkVisibility.hide);

    String shown(String line, TextDisplayProfile profile) =>
        TextRendererService.processText(
          line,
          RenderSettings.fromProfile(profile, formatParentheses: false),
        );

    test('ברירת המחדל: מוצגים', () {
      expect(TextDisplayProfile.defaults.hideFootnoteMarkers, isFalse);
      final line = addNumberedNoteMarkerLinks('טקסט (9) המשך', lineIndex: 0);
      expect(shown(line, TextDisplayProfile.defaults), contains('(9)'));
    });

    test('סמן מודפס (9) מוסתר בתצוגה, ושאר השורה נשאר', () {
      final line = addNumberedNoteMarkerLinks('טקסט (9) המשך', lineIndex: 0);
      final html = shown(line, hidden);
      expect(html, isNot(contains('(9)')));
      expect(html, contains('טקסט המשך'));
    });

    test('הסתרת ציוני המפרשים לבדה משאירה את (9)', () {
      final line = addNumberedNoteMarkerLinks('טקסט (9) המשך', lineIndex: 0);
      const anchorsOnly = TextDisplayProfile(
        anchorMarkers: MarkVisibility.hide,
      );
      expect(shown(line, anchorsOnly), contains('(9)'));
    });

    test('אות בתוך <sup> ו-<sup class="footnote-marker"> מוסתרות', () {
      final sup = addNumberedNoteMarkerLinks(
        'טקסט<sup>(א)</sup> המשך',
        lineIndex: 0,
      );
      expect(shown(sup, hidden), isNot(contains('(א)')));
      final inline = addInlineNotePreviewLinks(
        'טקסט<sup class="footnote-marker">12</sup><i class="footnote">גוף</i>',
        lineIndex: 0,
      );
      expect(shown(inline, hidden), isNot(contains('12')));
    });

    test('העתקה וייצוא: הסמן המקודד אינו נכלל', () {
      const line =
          'טקסט<sup class="footnote-marker">12</sup><i class="footnote">גוף</i>';
      expect(applyTextDisplayProfile(line, hidden), isNot(contains('12')));
      expect(
        applyTextDisplayProfile(line, TextDisplayProfile.defaults),
        contains('12'),
      );
    });

    test('הסרת הסמן אינה מחברת מילים, בשני כיווני הריווח', () {
      String strip(String line) => removeFootnoteMarkers(line);
      expect(strip('אב <sup class="footnote-marker">א</sup>גד'), 'אב גד');
      expect(strip('אב<sup class="footnote-marker">א</sup> גד'), 'אב גד');
      expect(strip('אב <sup class="footnote-marker">א</sup> גד'), 'אב גד');
      expect(strip('אב <sup class="footnote-marker">א</sup>'), 'אב');
    });

    test('טלאי: JSON, מיזוג, ירושה וקיצור דינמי', () {
      const patch = TextDisplayPatch(footnoteMarkers: MarkVisibility.hide);
      expect(patch.isEmpty, isFalse);
      expect(TextDisplayPatch.fromJson(patch.toJson()), patch);
      expect(patch.applyTo(TextDisplayProfile.defaults), hidden);
      expect(patch.pruneAgainst(hidden).isEmpty, isTrue);
      expect(
        hidden.toPatch().copyWith(clearFootnoteMarkers: true).footnoteMarkers,
        isNull,
      );
      final resolved = TextDisplayResolver.resolve(
        slot: TextDisplaySlot.root,
        layers: [
          TextDisplayLayer({TextDisplaySlot.root: patch}),
        ],
      );
      expect(resolved.hideFootnoteMarkers, isTrue);
      const toggle = DynamicDisplayChange(
        footnoteMarkers: DynamicMarkChange.toggle,
      );
      expect(DynamicDisplayChange.fromJson(toggle.toJson()), toggle);
      expect(toggle.patchFor(hidden).footnoteMarkers, MarkVisibility.show);
    });
  });
}
