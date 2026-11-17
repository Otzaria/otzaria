import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_tab_info.dart';

/// תו כיוון, נבנה בזמן ריצה כדי שהמעצב לא יהפוך אותו לתו בלתי נראה בקוד.
String bidi(int codePoint) => String.fromCharCode(codePoint);

void main() {
  group('normalizePluginTabText', () {
    test('מקצץ רווחים ומכווץ רצפי רווחים ושורות בכותרת', () {
      expect(
        normalizePluginTabText(
          '  שני \n טורים\t- בראשית  ',
          maxLength: kMaxPluginTabTitleLength,
          field: 'title',
        ),
        'שני טורים - בראשית',
      );
    });

    test('טקסט ריק או רווחים בלבד מתנקה ל-null (איפוס)', () {
      for (final raw in <Object?>[null, '', '   ', '\n\t']) {
        expect(
          normalizePluginTabText(
            raw,
            maxLength: kMaxPluginTabTitleLength,
            field: 'title',
          ),
          isNull,
          reason: 'raw=$raw',
        );
      }
    });

    test('מסיר תווי בקרה ותווי עקיפת כיוון', () {
      expect(
        normalizePluginTabText(
          'א\u0000ב${bidi(0x202E)}ג${bidi(0x2066)}ד${bidi(0x2069)}',
          maxLength: kMaxPluginTabTitleLength,
          field: 'title',
        ),
        'אבגד',
      );
    });

    test('משאיר LRM/RLM ושאר טקסט תקין', () {
      expect(
        normalizePluginTabText(
          'בראשית${bidi(0x200F)} (1)',
          maxLength: kMaxPluginTabTitleLength,
          field: 'title',
        ),
        'בראשית${bidi(0x200F)} (1)',
      );
    });

    test('חותך לאורך המרבי לפי תווים גרפיים, לא באמצע ניקוד או זוג חלופי', () {
      // "בְּ" = בית + דגש + שווא (3 קודים, תו גרפי אחד); האימוג'י הוא זוג חלופי.
      final cluster = 'בְּ';
      final text = '$cluster$cluster$cluster😀';
      final result = normalizePluginTabText(text, maxLength: 3, field: 'title');
      expect(result, '$cluster$cluster$cluster');
      final cut = normalizePluginTabText(text, maxLength: 4, field: 'title');
      expect(cut, text);
      final longer = normalizePluginTabText(
        'א' * (kMaxPluginTabTitleLength + 20),
        maxLength: kMaxPluginTabTitleLength,
        field: 'title',
      );
      expect(longer!.length, kMaxPluginTabTitleLength);
    });

    test('בטולטיפ שורות חדשות נשמרות, ורצפי שורות ריקות מכווצים', () {
      expect(
        normalizePluginTabText(
          'שורה א\r\nשורה ב\n\n\n\nשורה ג',
          maxLength: kMaxPluginTabTooltipLength,
          field: 'tooltip',
          allowNewlines: true,
        ),
        'שורה א\nשורה ב\n\nשורה ג',
      );
    });

    test('ערך שאינו מחרוזת נדחה כ-invalid_params', () {
      for (final raw in <Object>[
        1,
        true,
        <String>['א'],
        <String, Object>{},
      ]) {
        expect(
          () => normalizePluginTabText(
            raw,
            maxLength: kMaxPluginTabTitleLength,
            field: 'title',
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              allOf(contains('error.invalid_params'), contains('title')),
            ),
          ),
          reason: 'raw=$raw',
        );
      }
    });
  });

  group('PluginTabInfoUpdate.parse', () {
    test('שדה חסר = ללא שינוי, null או ריק = איפוס, מחרוזת = ערך חדש', () {
      final onlyTitle = PluginTabInfoUpdate.parse({'title': 'עריכה'});
      expect(onlyTitle.hasTitle, isTrue);
      expect(onlyTitle.title, 'עריכה');
      expect(onlyTitle.hasTooltip, isFalse);

      final resetTooltip = PluginTabInfoUpdate.parse({
        'title': 'א',
        'tooltip': null,
      });
      expect(resetTooltip.hasTooltip, isTrue);
      expect(resetTooltip.tooltip, isNull);

      final emptyTitle = PluginTabInfoUpdate.parse({'title': '  '});
      expect(emptyTitle.hasTitle, isTrue);
      expect(emptyTitle.title, isNull);
    });

    test('בלי title ובלי tooltip — invalid_params', () {
      expect(
        () => PluginTabInfoUpdate.parse(<String, dynamic>{}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.invalid_params'),
          ),
        ),
      );
    });
  });
}
