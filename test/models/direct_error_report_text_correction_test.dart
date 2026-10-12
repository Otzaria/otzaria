import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

/// שורה גולמית עם כל מה שאסור לנרמל: HTML, ניקוד, טעמים, רווחים בקצוות,
/// טאב, NBSP, RLM, CRLF בתוך השדה, מירכאות ולוכסן.
const String trickyLine =
    '  (א) <big>בְּ</big>רֵאשִׁ֖ית\tבָּרָ֣א אֱלֹהִ֑ים‏ "ציטוט" \\ \r\nסוף ';

DirectErrorReport buildCorrectionReport({
  String id = 'r-1',
  String? proposed = 'אֱלֹקִ֑ים',
  int start = 38,
  int end = 47,
  String errorDetails = 'שם ה\' נכתב במלואו',
}) {
  return DirectErrorReport(
    id: id,
    senderEmail: 'user@example.com',
    subject: 'דיווח על טעות: בראשית',
    bookTitle: 'בראשית',
    currentRef: 'בראשית א',
    lineNumber: 3,
    selectedText: 'אלהים',
    errorDetails: errorDetails,
    contextText: 'בראשית ברא אלהים',
    filePath: 'אוצריא/תנך/תורה/בראשית.txt',
    sourceFolder: 'ToratEmetToOtzaria',
    libraryVersion: '27',
    createdAt: DateTime.parse('2026-09-15T10:00:00.000Z'),
    schemaVersion: 2,
    reportKind: DirectErrorReportKind.textCorrection,
    location: const ReportLocation(
      lineIndex: 2,
      bookId: 1,
      libraryBuildId: '27',
      heRef: 'בראשית א',
    ),
    client: const ReportClientInfo(appVersion: '0.9.98', platform: 'windows'),
    correction: TextCorrection.selection(
      originalLine: trickyLine,
      start: start,
      end: end,
      proposedText: proposed,
    ),
  );
}

/// מסלול מלא: תור Hive (toJson→fromJson) → payload → רשת (jsonEncode→jsonDecode).
Map<String, dynamic> throughQueueAndWire(DirectErrorReport report) {
  final restored = DirectErrorReport.fromJson(
    jsonDecode(jsonEncode(report.toJson())) as Map<String, dynamic>,
  );
  expect(restored, equals(report));
  return jsonDecode(jsonEncode(restored.toApiPayload()))
      as Map<String, dynamic>;
}

void main() {
  test('offsets של הבדיקה מצביעים על "אֱלֹהִ֑ים" בשורה', () {
    expect(trickyLine.substring(38, 47), 'אֱלֹהִ֑ים');
  });

  group('[T4] round-trip מדויק של השדות המדויקים', () {
    test('[T4] עברית, ניקוד, טעמים, HTML, רווחים, \\t, NBSP, RLM, \\r\\n', () {
      final report = buildCorrectionReport();
      final payload = throughQueueAndWire(report);
      final correction = payload['correction'] as Map<String, dynamic>;

      expect(correction['original_line'], trickyLine);
      expect(correction['original_selection'], 'אֱלֹהִ֑ים');
      expect(correction['proposed_text'], 'אֱלֹקִ֑ים');
      expect(correction['selection_offset'], {
        'unit': 'utf16_code_units',
        'start': 38,
        'end': 47,
      });
      expect(correction['context_before'], trickyLine.substring(0, 38));
      expect(correction['context_after'], trickyLine.substring(47));
      // כללי הוולידציה של השרת (חוזה §2.2)
      final line = correction['original_line'] as String;
      expect(line.substring(38, 47), correction['original_selection']);
      expect(
        '${correction['context_before']}${correction['original_selection']}${correction['context_after']}',
        line,
      );
    });

    test('[T4] בחירה של רווח מוביל ו-CRLF נשמרת כלשונה', () {
      final report = buildCorrectionReport(
        start: 0,
        end: 2,
        proposed: ' \r\n',
      );
      final correction =
          throughQueueAndWire(report)['correction'] as Map<String, dynamic>;
      expect(correction['original_selection'], '  ');
      expect(correction['proposed_text'], ' \r\n');
    });

    test('[T4] ה-digest שהשרת יחשב מה-payload זהה לזה שנשלח', () {
      final payload = throughQueueAndWire(buildCorrectionReport());
      final correction = payload['correction'] as Map<String, dynamic>;
      final serverSide = canonicalJsonSha256({
        'v': 1,
        'report_kind': payload['report_kind'],
        'book_title': payload['book_title'],
        'current_ref': payload['current_ref'],
        'line_index': (payload['location'] as Map)['line_index'],
        'selected_text': payload['selected_text'],
        'error_details': payload['error_details'],
        'context_text': payload['context_text'],
        'source_folder': payload['source_folder'],
        'file_path': payload['file_path'],
        'library_version': payload['library_version'],
        'correction': {
          'original_line': correction['original_line'],
          'original_selection': correction['original_selection'],
          'proposed_text': correction['proposed_text'],
          'selection_offset': correction['selection_offset'],
        },
      });
      expect(payload['content_digest'], serverSide);
    });
  });

  group('[T3] null מול מחרוזת ריקה', () {
    test('[T3] "" = מחיקה, null = ללא הצעה — נשמרים ונשלחים שונים', () {
      final deletion = throughQueueAndWire(buildCorrectionReport(proposed: ''));
      final none = throughQueueAndWire(buildCorrectionReport(proposed: null));

      final deletionCorrection = deletion['correction'] as Map;
      final noneCorrection = none['correction'] as Map;
      expect(deletionCorrection.containsKey('proposed_text'), isTrue);
      expect(deletionCorrection['proposed_text'], '');
      expect(noneCorrection.containsKey('proposed_text'), isTrue);
      expect(noneCorrection['proposed_text'], isNull);
      expect(deletion['content_digest'], isNot(none['content_digest']));
      expect(deletion['error_details'], endsWith('מוצע: (מחיקה)'));
      expect(none['error_details'], endsWith('מוצע: (ללא הצעה)'));
    });

    test('[T3] בחירה null = השורה כולה, בלי offset', () {
      final report = DirectErrorReport(
        id: 'whole',
        senderEmail: '',
        subject: 's',
        bookTitle: 'b',
        currentRef: 'r',
        lineNumber: 1,
        createdAt: DateTime.utc(2026),
        schemaVersion: 2,
        reportKind: DirectErrorReportKind.textCorrection,
        correction: const TextCorrection.wholeLine(
          originalLine: 'שורה שלמה',
          proposedText: 'שורה מתוקנת',
        ),
      );
      final correction =
          throughQueueAndWire(report)['correction'] as Map<String, dynamic>;
      expect(correction['original_selection'], isNull);
      expect(correction['selection_offset'], isNull);
      expect(correction['context_before'], '');
      expect(correction['context_after'], '');
    });
  });

  group('[T1] לקוח ישן / JSON ישן בתור', () {
    final legacyJson = <String, dynamic>{
      'id': 'legacy-1',
      'senderEmail': 'user@example.com',
      'subject': 'דיווח על טעות: ספר',
      'bookTitle': 'ספר',
      'currentRef': 'פרק א',
      'lineNumber': 4,
      'selectedText': 'טקסט',
      'errorDetails': 'פירוט',
      'contextText': 'הקשר',
      'filePath': 'אוצריא/ספר.txt',
      'sourceFolder': 'MoreBooks',
      'libraryVersion': '26',
      'queueType': 'automaticRetry',
      'createdAt': '2026-03-16T10:15:00.000Z',
    };

    test('[T1] נטען כ-free_text בלי להמציא שדות', () {
      final report = DirectErrorReport.fromJson(legacyJson);
      expect(report.schemaVersion, 1);
      expect(report.reportKind, DirectErrorReportKind.freeText);
      expect(report.location, isNull);
      expect(report.client, isNull);
      expect(report.correction, isNull);
      expect(report.serverAcceptedCorrection, isNull);
    });

    test('[T1] נשלח בדיוק ב-payload הישן', () {
      final payload = DirectErrorReport.fromJson(legacyJson).toApiPayload();
      expect(payload.keys.toSet(), {
        'report_id',
        'sender_email',
        'subject',
        'book_title',
        'current_ref',
        'line_number',
        'selected_text',
        'error_details',
        'context_text',
        'file_path',
        'source_folder',
        'library_version',
        'created_at',
      });
      expect(payload['error_details'], 'פירוט');
    });

    test('created_at שמור (גם בלי אזור זמן) נשלח כלשונו אחרי שמירה בתור', () {
      for (final stored in [
        '2026-03-16T10:15:00.000',
        '2026-03-16T10:15:00.123456Z',
      ]) {
        final json = {...legacyJson, 'createdAt': stored};
        final resaved = DirectErrorReport.fromJson(
          DirectErrorReport.fromJson(json).toJson(),
        );
        expect(resaved.toJson()['createdAt'], stored);
        expect(resaved.toApiPayload()['created_at'], stored);
      }
    });

    test('[T1] שמירה חוזרת בתור ואז טעינה — עדיין payload ישן', () {
      final resaved = DirectErrorReport.fromJson(
        DirectErrorReport.fromJson(legacyJson).toJson(),
      );
      expect(resaved.toApiPayload().containsKey('schema_version'), isFalse);
    });
  });

  group('[T2] לקוח חדש — שדות חוזה A', () {
    test('[T2] payload מכיל את כל השדות הישנים והחדשים', () {
      final payload = throughQueueAndWire(buildCorrectionReport());
      expect(payload['schema_version'], 2);
      expect(payload['report_kind'], 'text_correction');
      expect(payload['report_id'], 'r-1');
      expect(payload['line_number'], 3);
      expect(payload['location'], {
        'line_index': 2,
        'book_id': 1,
        'library_build_id': '27',
        'he_ref': 'בראשית א',
      });
      expect(payload['source_hint'], {
        'source_folder': 'ToratEmetToOtzaria',
        'library_relative_path': 'אוצריא/תנך/תורה/בראשית.txt',
        'repo_path': null,
      });
      expect(payload['client'], {
        'app_version': '0.9.98',
        'platform': 'windows',
      });
      expect(payload['content_digest'], matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('[T2] בלוק ה-fallback בסוף error_details (חוזה §2.5)', () {
      final payload = buildCorrectionReport().toApiPayload();
      expect(
        payload['error_details'],
        'שם ה\' נכתב במלואו\n\n--- הצעת תיקון ---\n'
        'מקור: אֱלֹהִ֑ים\nמוצע: אֱלֹקִ֑ים',
      );
    });

    test('[T2] דיווח חופשי חדש: schema 2 בלי correction ובלי בלוק', () {
      final report = DirectErrorReport(
        id: 'free',
        senderEmail: '',
        subject: 's',
        bookTitle: 'b',
        currentRef: 'r',
        lineNumber: 1,
        errorDetails: 'הסבר',
        createdAt: DateTime.utc(2026),
        schemaVersion: 2,
      );
      final payload = throughQueueAndWire(report);
      expect(payload['report_kind'], 'free_text');
      expect(payload.containsKey('correction'), isFalse);
      expect(payload['error_details'], 'הסבר');
      expect(payload['location'], {
        'line_index': null,
        'book_id': null,
        'library_build_id': null,
        'he_ref': null,
      });
    });

    test('ה-digest של דיווח חופשי תואם לחישוב לפי §4.2', () {
      final report = DirectErrorReport(
        id: 'free',
        senderEmail: 'x@y.z',
        subject: 'דיווח על טעות: בראשית',
        bookTitle: 'בראשית',
        currentRef: 'בראשית א',
        lineNumber: 3,
        selectedText: 'בראשית ברא',
        errorDetails: 'חסר ניקוד',
        contextText: '(א) בראשית ברא אלהים',
        filePath: 'אוצריא/תנך/תורה/בראשית.txt',
        sourceFolder: 'ToratEmetToOtzaria',
        libraryVersion: '27',
        createdAt: DateTime.utc(2026),
        schemaVersion: 2,
        location: const ReportLocation(lineIndex: 2),
      );
      // זהה לקלט של ה-fixture "report-free-text".
      expect(
        report.contentDigest,
        '139b1100852541c25d512a7e4081315d2b11d1e93cbb0c880101ed478222465c',
      );
    });
  });

  group('TextCorrection — עקביות', () {
    test('בחירה ריקה או מחוץ לטווח נדחית', () {
      expect(
        () => TextCorrection.selection(originalLine: 'אב', start: 1, end: 1),
        throwsArgumentError,
      );
      expect(
        () => TextCorrection.selection(originalLine: 'אב', start: 0, end: 5),
        throwsRangeError,
      );
    });

    test('JSON פגום בתור (offset שלא תואם לבחירה) נטען כדיווח חופשי', () {
      final json = buildCorrectionReport().toJson();
      (json['correction'] as Map)['originalSelection'] = 'אחר';
      final report = DirectErrorReport.fromJson(json);
      expect(report.reportKind, DirectErrorReportKind.freeText);
      expect(report.correction, isNull);
      expect(report.errorDetails, startsWith('שם ה\' נכתב במלואו'));
      expect(report.errorDetails, contains('מוצע: אֱלֹקִ֑ים'));
    });

    test('בחירה בלי offsets אינה נטענת כהצעה על השורה כולה', () {
      final json = buildCorrectionReport().toJson();
      (json['correction'] as Map)
        ..remove('selectionStart')
        ..remove('selectionEnd');
      final report = DirectErrorReport.fromJson(json);

      expect(TextCorrection.fromJson(json['correction']), isNull);
      expect(report.reportKind, DirectErrorReportKind.freeText);
      expect(report.correction, isNull);
      expect(report.toApiPayload().containsKey('correction'), isFalse);
      expect(
        report.errorDetails,
        'שם ה\' נכתב במלואו\n\n--- הצעת תיקון ---\n'
        'מקור: אֱלֹהִ֑ים\nמוצע: אֱלֹקִ֑ים',
        reason: 'ההצעה נשמרת כטקסט חופשי, ולא מוחלת על השורה כולה',
      );
    });

    test('offset בודד בלי השני, או הצעה שאינה מחרוזת — נפסל', () {
      final correction = buildCorrectionReport().toJson()['correction'] as Map;
      expect(
        TextCorrection.fromJson({...correction, 'selectionEnd': null}),
        isNull,
      );
      expect(
        TextCorrection.fromJson({...correction, 'proposedText': 5}),
        isNull,
      );
    });
  });
}
