import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/text_book/view/text_correction_editor.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

void main() {
  const cases = <({String name, String raw, String shown, bool selection})>[
    (
      name: 'nested tags crossed by the displayed selection',
      raw: '<p><b>לפני <i>מילה</i> אחרי</b></p>',
      shown: 'לפני מילה אחרי',
      selection: false,
    ),
    (
      name: 'decoded entities including literal angle brackets',
      raw: 'א &amp; ב &lt;ג&gt; &#160; סוף',
      shown: 'א & ב <ג>   סוף',
      selection: false,
    ),
    (
      name: 'hidden Hebrew vowel marks',
      raw: '<b>שָׁלוֹם</b> עולם',
      shown: 'שלום',
      selection: false,
    ),
    (
      name: 'repeated words in different formatting',
      raw: 'מילה <b>מילה</b>',
      shown: 'מילה',
      selection: false,
    ),
    (
      name: 'HTML breaks and original CRLF',
      raw: 'ראשון<br>שני\r\nשלישי',
      shown: 'ראשון\nשני\nשלישי',
      selection: false,
    ),
    (
      name: 'HTML comments between visible characters',
      raw: 'א<!-- internal marker -->ב',
      shown: 'אב',
      selection: false,
    ),
    (
      name: 'inline note markup',
      raw:
          'אב<sup class="footnote-marker">1</sup>'
          '<i class="footnote"><b>הערה</b></i>',
      shown: 'אב1הערה',
      selection: false,
    ),
    (
      name: 'exact text inside nested tags',
      raw: '<p><b>לפני <i>מילה</i> אחרי</b></p>',
      shown: 'מילה',
      selection: true,
    ),
    (
      name: 'UTF-16 offsets following a supplementary character',
      raw: '😀 <b>מילה</b>\tסוף\u200f',
      shown: 'מילה',
      selection: true,
    ),
  ];

  for (final example in cases) {
    test('exact source survives storage and payload: ${example.name}', () {
      final template = buildCorrectionTemplate(example.raw, example.shown);
      expect(template.hasSelection, example.selection);
      // The display string must never replace the authoritative source.
      expect(template.originalLine, example.raw);
      final correction = template.withProposedText('${template.target} תיקון');
      final restored = TextCorrection.fromJson(
        jsonDecode(jsonEncode(correction.toJson())),
      )!;
      expect(restored, correction);
      expect(restored.toApiPayload(), correction.toApiPayload());
      expect(restored.originalLine, example.raw);
      expect(
        restored.contextBefore + restored.target + restored.contextAfter,
        example.raw,
      );
      if (restored.hasSelection) {
        expect(
          example.raw.substring(
            restored.selectionStart!,
            restored.selectionEnd!,
          ),
          example.shown,
        );
        expect(restored.toApiPayload()['selection_offset'], {
          'unit': 'utf16_code_units',
          'start': restored.selectionStart,
          'end': restored.selectionEnd,
        });
      }
    });
  }

  test('the same visible text does not identify the original HTML', () {
    const bold = '<b>מילה</b>';
    const italic = '<i>מילה</i>';
    expect(
      ErrorReportHelper.sanitizeReportText(bold),
      ErrorReportHelper.sanitizeReportText(italic),
    );
    expect(
      buildCorrectionTemplate(bold, 'מילה').originalLine,
      isNot(buildCorrectionTemplate(italic, 'מילה').originalLine),
    );
  });
}
