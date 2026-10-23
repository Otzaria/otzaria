import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_book_correction_service.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

void main() {
  const metadata = PluginBookReportMetadata(
    bookId: 42,
    title: 'ספר',
    sourceFolder: 'Sefaria',
    filePath: 'ספרים/ספר.txt',
    libraryVersion: '2026.10',
    client: ReportClientInfo(appVersion: '0.9.99', platform: 'windows'),
  );
  late DirectErrorReport report;
  late List<int> loaded;
  late PluginBookCorrectionService service;
  setUp(() {
    loaded = [];
    service = PluginBookCorrectionService(
      senderEmail: () => 'reader@example.com',
      deliver: (value, {required bool allowQueue}) async {
        report = value;
        return DirectReportDeliveryResult.sent('נשלח');
      },
      now: () => DateTime.utc(2026, 10, 6),
    );
  });
  Future<Map<String, dynamic>> submit(
    List<String> raw,
    String original,
    String proposed, {
    int? start,
    int? end,
    Map<String, dynamic> extra = const {},
  }) => service.submit(
    pluginId: 'test.plugin',
    metadata: metadata,
    args: {
      'reportId': 'stable-id',
      'sectionIndex': 7,
      'endSectionIndex': 7 + raw.length - 1,
      'snapshots': [
        for (var i = 0; i < raw.length; i++)
          {'index': 7 + i, 'text': TextRendererService.stripHtml(raw[i])},
      ],
      'original': original,
      'proposed': proposed,
      'sourceStart': ?start,
      'sourceEnd': ?end,
      ...extra,
    },
    loadSource: (index) async {
      loaded.add(index);
      return PluginBookReportSource(raw[index - 7], heRef: 'סימן א');
    },
  );

  test('בונה תיקון v2 בטווח מקורי UTF-16 גם אחרי emoji', () async {
    await submit(['😀 אָב אָב'], 'אָב', 'אֵם', start: 7, end: 10);
    expect(report.correction?.originalLine, '😀 אָב אָב');
    expect(report.correction?.selectionStart, 7);
    expect(report.correction?.originalSelection, 'אָב');
    expect(report.location?.lineIndex, 7);
    expect(report.location?.bookId, 42);
    expect(report.lineNumber, 8);
    expect(report.id, 'test.plugin:stable-id');
    final payload = report.toApiPayload();
    expect(payload['schema_version'], 2);
    expect(payload['report_kind'], 'text_correction');
    expect(payload['content_digest'], matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('HTML נשמר במקור ורק טווח טקסט חד משמעי משויך אליו', () async {
    await submit(['<b>אָב</b> סוף'], 'אָב', 'אֵם', start: 0, end: 3);
    expect(report.correction?.originalLine, '<b>אָב</b> סוף');
    expect(report.correction?.selectionStart, 3);
    expect(report.correction?.contextAfter, '</b> סוף');
  });

  test('ישות ממופה במדויק וטווח שחוצה HTML אינו מקבל טווח כוזב', () async {
    await submit(['א&amp;ב'], '&', 'וגם', start: 1, end: 2);
    expect(report.correction?.originalSelection, '&amp;');
    expect(report.correction?.proposedText, 'וגם');
    expect(report.reportKind, DirectErrorReportKind.textCorrection);
    expect(report.contextText, 'א&amp;ב');
    await submit(['מי<b>לה</b>'], 'מילה', 'חדש', start: 0, end: 4);
    expect(report.correction, isNull);
  });

  test('מחיקה בין פסקאות מאמתת את כולן ושומרת fallback מדויק', () async {
    await submit(['אחד', '<b>שניים</b>', 'שלושה'], 'אחד\nשניים\nשלושה', '');
    expect(loaded, [7, 8, 9]);
    expect(report.correction, isNull);
    expect(report.contextText, 'אחד\n<b>שניים</b>\nשלושה');
    expect(report.errorDetails, contains('מוצע: (מחיקה)'));
  });

  test('מקור ששונה אינו מועבר לשירות השליחה', () async {
    var delivered = false;
    service = PluginBookCorrectionService(
      senderEmail: () => 'reader@example.com',
      deliver: (_, {required bool allowQueue}) async {
        delivered = true;
        return DirectReportDeliveryResult.sent('נשלח');
      },
    );
    await expectLater(
      submit(
        ['מקור'],
        'מקור',
        'חדש',
        extra: {
          'snapshots': [
            {'index': 7, 'text': 'ישן'},
          ],
        },
      ),
      throwsA(
        predicate((Object e) => e.toString().contains('error.source_changed')),
      ),
    );
    expect(delivered, isFalse);
  });

  test('בקשה בלי מייל שמור אינה טוענת מקור או שולחת', () async {
    service = PluginBookCorrectionService(
      senderEmail: () => '',
      deliver: (_, {required bool allowQueue}) async =>
          throw StateError('לא לשלוח'),
    );
    await expectLater(
      submit(['א'], 'א', 'ב'),
      throwsA(
        predicate(
          (Object e) => e.toString().contains('error.report_email_required'),
        ),
      ),
    );
    expect(loaded, isEmpty);
  });

  test('allowQueue false מועבר לשירות ושליחה כושלת אינה מאושרת', () async {
    service = PluginBookCorrectionService(
      senderEmail: () => 'reader@example.com',
      deliver: (_, {required bool allowQueue}) async {
        expect(allowQueue, isFalse);
        return DirectReportDeliveryResult.failed('אין רשת');
      },
    );
    await expectLater(
      submit(['א'], 'א', 'ב', extra: {'allowQueue': false}),
      throwsA(
        predicate((Object e) => e.toString().contains('error.report_failed')),
      ),
    );
  });

  test('מצב תור מחזיר בעלות מקומית בלי לטעון שהשרת תמך בתיקון', () async {
    service = PluginBookCorrectionService(
      senderEmail: () => 'reader@example.com',
      deliver: (_, {required bool allowQueue}) async {
        expect(allowQueue, isTrue);
        return DirectReportDeliveryResult.queued('נשמר');
      },
    );
    final result = await submit(['א'], 'א', 'ב');
    expect(result['status'], 'queued');
    expect(result['correctionSupported'], isNull);
  });

  test('התנגשות מזהה מובחנת מכשל רשת כדי לאפשר מזהה חדש', () async {
    service = PluginBookCorrectionService(
      senderEmail: () => 'reader@example.com',
      deliver: (_, {required bool allowQueue}) async =>
          DirectReportDeliveryResult.failed('התנגשות', isIdConflict: true),
    );
    await expectLater(
      submit(['א'], 'א', 'ב', extra: {'allowQueue': false}),
      throwsA(
        predicate(
          (Object e) => e.toString().contains('error.report_id_conflict'),
        ),
      ),
    );
  });

  test('תמונות מקור חסרות או טווח לא מתאים נדחים', () async {
    await expectLater(
      submit(['א', 'ב'], 'א\nב', 'ג', extra: {'snapshots': []}),
      throwsException,
    );
    await expectLater(
      submit(['א'], 'א', 'ב', start: 1, end: 2),
      throwsException,
    );
    await expectLater(submit(['א'], 'ג', 'ב'), throwsException);
  });

  test('הוספה ריקה מקבלת תיקון שורה שלמה ולא בחירה ריקה', () async {
    await submit(['אב'], '', 'ג', start: 1, end: 1);
    expect(report.correction?.hasSelection, isFalse);
    expect(report.correction?.proposedText, 'אגב');
  });

  test('פסקה ארוכה נשמרת כתמונת מקור מלאה ודיווח חופשי מוגבל בגודל', () async {
    final raw = '${'א' * 19999}😀${'ב' * 5000}';
    await submit([raw], 'א', 'ג', start: 0, end: 1);
    expect(report.correction, isNull);
    expect(report.contextText.length, lessThanOrEqualTo(20000));
    expect(report.exceedsApiBodyLimit, isFalse);
    expect(report.contextText, endsWith('…'));
  });

  test('היסטים שונים בהוספה חופשית נשמרים ומפיקים digest שונה', () async {
    await submit(
      ['אב'],
      '',
      'ג',
      start: 0,
      end: 0,
      extra: {'forceFreeText': true},
    );
    final firstDigest = report.contentDigest;
    expect(report.errorDetails, contains('UTF-16: [0, 0)'));
    await submit(
      ['אב'],
      '',
      'ג',
      start: 1,
      end: 1,
      extra: {'forceFreeText': true},
    );
    expect(report.errorDetails, contains('UTF-16: [1, 1)'));
    expect(report.contentDigest, isNot(firstDigest));
  });

  test('חלק של הוספה גדולה אינו הופך להצעת שורה שלמה חלופית', () async {
    await submit(
      ['אב'],
      '',
      'ג',
      start: 1,
      end: 1,
      extra: {'forceFreeText': true},
    );
    expect(report.correction, isNull);
    expect(report.reportKind, DirectErrorReportKind.freeText);
    expect(report.errorDetails, contains('מוצע: ג'));
  });

  group('reportKind ו-requireTextCorrection', () {
    late int deliveries;
    setUp(() {
      deliveries = 0;
      service = PluginBookCorrectionService(
        senderEmail: () => 'reader@example.com',
        deliver: (value, {required bool allowQueue}) async {
          deliveries++;
          report = value;
          return DirectReportDeliveryResult.sent('נשלח');
        },
      );
    });
    Matcher coded(String code) =>
        throwsA(predicate((Object e) => e.toString().contains(code)));

    test('reportKind מתאר תיקון מובנה ודיווח חופשי', () async {
      final structured = await submit(['אָב'], 'אָב', 'אֵם', start: 0, end: 3);
      expect(structured['reportKind'], 'text_correction');
      expect(structured['correctionSupported'], isTrue);
      final free = await submit(
        ['מי<b>לה</b>'],
        'מילה',
        'חדש',
        start: 0,
        end: 4,
      );
      expect(free['reportKind'], 'free_text');
      expect(free['correctionSupported'], isFalse);
    });

    test('בלי האפשרות נשמרים שדות התוצאה הקודמים', () async {
      final result = await submit(
        ['מי<b>לה</b>'],
        'מילה',
        'חדש',
        start: 0,
        end: 4,
      );
      expect(result, {
        'status': 'sent',
        'reportId': 'stable-id',
        'nativeReportId': 'test.plugin:stable-id',
        'message': 'נשלח',
        'duplicate': false,
        'reportKind': 'free_text',
        'correctionSupported': false,
      });
    });

    test('שינוי שחוצה HTML נדחה בלי לשלוח', () async {
      await expectLater(
        submit(
          ['מי<b>לה</b>'],
          'מילה',
          'חדש',
          start: 0,
          end: 4,
          extra: {'requireTextCorrection': true},
        ),
        coded('error.text_correction_unavailable'),
      );
      expect(deliveries, 0);
    });

    test('טווח רב-פסקאי נדחה בלי לשלוח', () async {
      await expectLater(
        submit(
          ['אחד', 'שניים'],
          'אחד\nשניים',
          '',
          extra: {'requireTextCorrection': true},
        ),
        coded('error.text_correction_unavailable'),
      );
      expect(deliveries, 0);
    });

    test('שילוב עם forceFreeText נדחה כפרמטר שגוי', () async {
      await expectLater(
        submit(
          ['אָב'],
          'אָב',
          'אֵם',
          start: 0,
          end: 3,
          extra: {'requireTextCorrection': true, 'forceFreeText': true},
        ),
        coded('error.invalid_params'),
      );
      expect(deliveries, 0);
      expect(loaded, isEmpty);
    });

    test('ערך שאינו bool נדחה', () async {
      await expectLater(
        submit(['אָב'], 'אָב', 'אֵם', extra: {'requireTextCorrection': 'yes'}),
        coded('error.invalid_params'),
      );
      expect(deliveries, 0);
    });

    test('שינוי שניתן למיפוי נשלח כתיקון מובנה', () async {
      final result = await submit(
        ['<b>אָב</b> סוף'],
        'אָב',
        'אֵם',
        start: 0,
        end: 3,
        extra: {'requireTextCorrection': true},
      );
      expect(deliveries, 1);
      expect(result['reportKind'], 'text_correction');
      expect(report.reportKind, DirectErrorReportKind.textCorrection);
    });
  });
}
