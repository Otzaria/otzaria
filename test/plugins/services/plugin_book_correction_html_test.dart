import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_book_correction_service.dart';
import 'package:otzaria/plugins/services/plugin_correction_text.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria/widgets/smart_text/inline_html_document.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

void main() {
  const metadata = PluginBookReportMetadata(
    bookId: 42,
    title: 'ספר',
    sourceFolder: 'Sefaria',
    filePath: 'אוצריא/ספר.txt',
    libraryVersion: '2026.10',
    client: ReportClientInfo(appVersion: '0.9.99', platform: 'windows'),
  );
  late PluginBookCorrectionService service;
  late List<DirectErrorReport> delivered;
  setUp(() {
    delivered = [];
    service = PluginBookCorrectionService(
      senderEmail: () => 'reader@example.com',
      deliver: (report, {required bool allowQueue}) async {
        delivered.add(report);
        return DirectReportDeliveryResult.sent('נשלח');
      },
    );
  });

  Future<Map<String, dynamic>> submit(
    String raw,
    String original,
    String proposed,
    int start,
    int end, {
    bool requireTextCorrection = true,
  }) => service.submit(
    pluginId: 'test.plugin',
    metadata: metadata,
    args: {
      'reportId': 'html-regression',
      'sectionIndex': 0,
      'original': original,
      'proposed': proposed,
      'sourceStart': start,
      'sourceEnd': end,
      'snapshots': [
        {'index': 0, 'text': TextRendererService.stripHtml(raw)},
      ],
      'requireTextCorrection': requireTextCorrection,
    },
    loadSource: (_) async => PluginBookReportSource(raw),
  );

  String resultingSource() {
    final correction = delivered.single.correction!;
    if (!correction.hasSelection) return correction.proposedText!;
    return correction.originalLine.substring(0, correction.selectionStart!) +
        correction.proposedText! +
        correction.originalLine.substring(correction.selectionEnd!);
  }

  Matcher unavailable() => throwsA(
    predicate<Object>(
      (error) => error.toString().contains('error.text_correction_unavailable'),
    ),
  );

  for (final raw in ['<!--אב', '<span title="אב']) {
    test('מקור HTML שלא נסגר אינו ממופה לתוך הערה או מאפיין: $raw', () async {
      final plain = TextRendererService.stripHtml(raw);
      final start = plain.indexOf('אב');
      await expectLater(
        submit(raw, 'אב', 'אם', start, start + 2),
        unavailable(),
      );
      expect(delivered, isEmpty);
    });
  }

  test('מילה חוזרת ממופה למופע השני לפי היסטים גם כשמופיעה במאפיין', () async {
    const raw = '<span title="אב">אב אב</span>';
    await submit(raw, 'אב', 'אם', 3, 5);
    expect(resultingSource(), '<span title="אב">אב אם</span>');
    expect(delivered.single.correction!.originalLine, raw);
    expect(delivered.single.id, 'test.plugin:html-regression');
  });

  test('היסטי UTF-16 נשמרים אחרי emoji ובין צמתי HTML', () async {
    await submit('<b>😀 אב</b> אב', 'אב', 'אם', 6, 8);
    expect(resultingSource(), '<b>😀 אב</b> אם');
  });

  for (final entity in ['&quot;', '&#34;', '&#x22;']) {
    test('ישות $entity ממופה למקור בלי לפגוע בתגיות', () async {
      await submit('<b>א$entityב</b>', '"', '״', 1, 2);
      expect(resultingSource(), '<b>א״ב</b>');
    });
  }

  test('רווח קשיח וישות amp נשמרים מחוץ לטווח המוחלף', () async {
    const raw = '<b>אב&nbsp;אב&amp;סוף</b>';
    final plain = TextRendererService.stripHtml(raw);
    final start = plain.lastIndexOf('אב');
    await submit(raw, 'אב', 'אם', start, start + 2);
    expect(resultingSource(), '<b>אב&nbsp;אם&amp;סוף</b>');
  });

  group('שינוי בתוך כל השורה שומר את ההקשר כפי שהקורא מציג אותו', () {
    String displayed(String html) => InlineHtmlDocument.parseLine(
      html,
      const TextStyle(),
    )!.document.plainText;

    Future<void> submitWhole(
      String raw,
      String proposed, {
      bool requireTextCorrection = true,
    }) {
      final plain = TextRendererService.stripHtml(raw);
      return submit(
        raw,
        plain,
        proposed,
        0,
        plain.length,
        requireTextCorrection: requireTextCorrection,
      );
    }

    group('גבול עריכה בתוך ישות בלי נקודה-פסיק', () {
      const raw = '<b>אב&copy גד</b>';
      final plain = TextRendererService.stripHtml(raw);
      final p = plain.indexOf('p');

      test('המיפוי נדחה כשהטווח חותך ישות שמוצגת כתו אחד', () {
        expect(plain, 'אב&copy גד');
        expect(displayed(raw), 'אב© גד');
        expect(PluginCorrectionText(raw).replacement(p, p + 1, 'q'), isNull);
      });

      test('עם requireTextCorrection נדחה ללא שליחה', () async {
        await expectLater(submit(raw, 'p', 'q', p, p + 1), unavailable());
        expect(delivered, isEmpty);
      });

      test('בלי requireTextCorrection נשלח כטקסט חופשי', () async {
        await submit(raw, 'p', 'q', p, p + 1, requireTextCorrection: false);
        expect(delivered.single.reportKind, DirectErrorReportKind.freeText);
        expect(delivered.single.correction, isNull);
      });

      test('עריכה מחוץ לישות שומרת אותה גולמית ומוצגת', () async {
        final at = plain.indexOf('ג');
        await submit(raw, 'ג', 'ק', at, at + 1);
        expect(resultingSource(), '<b>אב&copy קד</b>');
        expect(displayed(resultingSource()), 'אב© קד');
      });

      test('טקסט מוקלד ליד הישות אינו הופך ל-markup', () async {
        final at = plain.indexOf('ג');
        await submit(raw, 'ג', '<i>', at, at + 1);
        expect(displayed(resultingSource()), 'אב© <i>ד');
        expect(resultingSource(), contains('&copy '));
      });
    });

    test('ישות HTML5 בלי נקודה-פסיק נשמרת גולמית', () async {
      const raw = 'אב &copy גד';
      expect(displayed(raw), 'אב © גד');
      await submitWhole(raw, 'אם &copy גד');
      expect(resultingSource(), 'אם &copy גד');
      expect(displayed(resultingSource()), 'אם © גד');
    });

    test('הקשר בלי ישויות', () async {
      await submitWhole('אב גד', 'אם גד');
      expect(resultingSource(), 'אם גד');
      expect(displayed(resultingSource()), 'אם גד');
    });

    test('ישויות נתמכות עם נקודה-פסיק נשמרות', () async {
      const raw = 'אב &amp; &nbsp;&#1488; גד';
      await submitWhole(
        raw,
        TextRendererService.stripHtml(raw).replaceFirst('ב', 'ם'),
      );
      expect(resultingSource(), 'אם &amp; &nbsp;&#1488; גד');
      expect(
        displayed(resultingSource()),
        displayed(raw).replaceFirst('ב', 'ם'),
      );
    });

    for (final typed in ['<b>', '&copy']) {
      test('הקלדת $typed אינה יוצרת markup פעיל', () async {
        await submitWhole('אב גד', 'א$typedב גד');
        expect(displayed(resultingSource()), 'א$typedב גד');
        expect(resultingSource(), isNot(contains(typed)));
      });
    }

    test('שינוי שמשלים ישות בהקשר נדחה ממיפוי מובנה', () async {
      const raw = 'אב &cop גד';
      await expectLater(submitWhole(raw, 'אב &copy גד'), unavailable());
      expect(delivered, isEmpty);
      await submitWhole(raw, 'אב &copy גד', requireTextCorrection: false);
      expect(delivered.single.reportKind, DirectErrorReportKind.freeText);
      expect(delivered.single.correction, isNull);
    });
  });

  group('ישות שהפענוח הקנוני מוחק (&copy;)', () {
    const raw = '<b>אב&copy;גד</b>';

    test('תיקון לפני הישות שומר אותה', () async {
      await submit(raw, 'א', 'ק', 0, 1);
      expect(resultingSource(), '<b>קב&copy;גד</b>');
    });

    test('תיקון אחרי הישות שומר אותה', () async {
      await submit(raw, 'ד', 'ק', 3, 4);
      expect(resultingSource(), '<b>אב&copy;גק</b>');
    });

    for (final (original, start, end) in [
      ('ב', 1, 2),
      ('ג', 2, 3),
      ('בג', 1, 3),
    ]) {
      test('טווח $original שנוגע בישות נדחה ממיפוי מובנה', () async {
        await expectLater(
          submit(raw, original, 'ם', start, end),
          unavailable(),
        );
        expect(delivered, isEmpty);
      });
    }

    test('בלי requireTextCorrection נשלח כטקסט חופשי בלי לגעת במקור', () async {
      await submit(raw, 'ב', 'ם', 1, 2, requireTextCorrection: false);
      final report = delivered.single;
      expect(report.reportKind, DirectErrorReportKind.freeText);
      expect(report.correction, isNull);
    });
  });

  test('החלפת ישות amp בוחרת את כל הישות הגולמית', () async {
    await submit('<b>א&amp;ב</b>', '&', 'וגם', 1, 2);
    expect(resultingSource(), '<b>אוגםב</b>');
  });

  test('החלפה עם הקשר באותו צומת שומרת nbsp שלא השתנה', () async {
    await submit('<b>אב&nbsp;גד</b>', 'אב גד', 'אם גד', 0, 5);
    expect(resultingSource(), '<b>אם&nbsp;גד</b>');
    expect(delivered.single.correction!.originalSelection, 'אב&nbsp;גד');
  });

  test('יצירת ישות משילוב הצעה עם תו מחוץ לטווח נדחית', () async {
    await expectLater(submit('<b>&foo</b>', 'foo', 'lt;', 1, 4), unavailable());
    expect(delivered, isEmpty);
  });

  test('החלפה עם הקשר באותו צומת שומרת quot שלא השתנה', () async {
    await submit('<b>אב&quot;גד</b>', 'אב"גד', 'אם"גד', 0, 5);
    expect(resultingSource(), '<b>אם&quot;גד</b>');
    expect(delivered.single.correction!.originalSelection, 'אב&quot;גד');
  });

  test('הוספה עם הקשר נבחר באותו צומת שומרת ישויות מקוריות', () async {
    await submit('<b>אב&nbsp;גד</b>', 'אב גד', 'אבג גד', 0, 5);
    expect(resultingSource(), '<b>אבג&nbsp;גד</b>');
    expect(delivered.single.correction!.originalSelection, 'אב&nbsp;גד');
  });

  for (final position in [0, 2]) {
    test('הוספה בגבול צומת טקסט במיקום $position שומרת HTML', () async {
      await submit('<b>אב</b>', '', 'ג', position, position);
      expect(resultingSource(), position == 0 ? '<b>גאב</b>' : '<b>אבג</b>');
      final correction = delivered.single.correction!;
      expect(
        !correction.hasSelection ||
            correction.selectionStart! < correction.selectionEnd!,
        isTrue,
      );
    });
  }

  test('טווח הקשר מורחב חוצה תגיות רק בחלק שאינו משתנה', () async {
    await submit('<b>אב</b> סוף', 'אב סוף', 'אם סוף', 0, 6);
    expect(resultingSource(), '<b>אם</b> סוף');
  });

  test('הוספה בגבול משותף לשני צמתים נדחית בלי לנחש סגנון', () async {
    await expectLater(
      submit('<b>אב</b> סוף', 'אב סוף', 'אבג סוף', 0, 6),
      unavailable(),
    );
    expect(delivered, isEmpty);
  });

  test('סוגר תג בתוך מאפיין אינו הופך את שאר המאפיין לצומת טקסט', () async {
    await expectLater(
      submit('<span title=">אב">אב</span>', 'אב', 'אם', 0, 2),
      unavailable(),
    );
    expect(delivered, isEmpty);
  });

  test('סוגר תג בתוך הערת HTML אינו מאפשר לשנות את תוכן ההערה', () async {
    await expectLater(
      submit('<!-- >אב -->אב', 'אב', 'אם', 0, 2),
      unavailable(),
    );
    expect(delivered, isEmpty);
  });

  test('שינוי ממשי חוצה תגית נדחה ללא שליחה', () async {
    await expectLater(submit('א<b>ב</b>ג', 'אבג', 'חדש', 0, 3), unavailable());
    expect(delivered, isEmpty);
  });

  test('הצעה עם תווי HTML נשמרת כטקסט ולא כתגיות', () async {
    await submit('<b>אב</b>', 'אב', '<i>&חדש</i>', 0, 2);
    expect(resultingSource(), '<b>&lt;i&gt;&amp;חדש&lt;/i&gt;</b>');
    expect(TextRendererService.stripHtml(resultingSource()), '<i>&חדש</i>');
  });

  test('הוספה נבדקת לפי אורך המקור המלא לאחר escape', () async {
    final raw = '<b>${'א' * (TextCorrection.maxTextLength - 7)}</b>';
    await expectLater(submit(raw, '', '&', 0, 0), unavailable());
    expect(delivered, isEmpty);
  });

  test('החלפה אינה עוקפת את מגבלת אורך התוצאה המלאה', () async {
    final raw = '<b>${'א' * (TextCorrection.maxTextLength - 7)}</b>';
    await expectLater(submit(raw, 'א', 'אב', 0, 1), unavailable());
    expect(delivered, isEmpty);
  });
}
