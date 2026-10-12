import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:test/test.dart';

// digest_fixtures.json = test/fixtures/text_corrections של אוצריא (וזה של האתר).
// שני קובצי ה-payload הופקו מהקוד של אוצריא ב-commit שב-`source` שלהם.
Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

bool _isSendable(DirectErrorReport report) {
  if (report.schemaVersion > DirectErrorReport.currentSchemaVersion) {
    return false;
  }
  try {
    report.contentDigest;
  } on ArgumentError {
    return false;
  }
  return !report.exceedsApiBodyLimit;
}

void main() {
  group('OCJ-1', () {
    final cases = (_fixture('digest_fixtures.json')['cases'] as List)
        .cast<Map<String, dynamic>>();

    test('יש מה לבדוק', () => expect(cases, isNotEmpty));

    for (final c in cases) {
      test('${c['name']}', () {
        expect(canonicalJsonEncode(c['input']), c['canonical']);
        expect(canonicalJsonSha256(c['input']), c['sha256']);
      });
    }

    test('surrogate בודד נדחה, זוג תקין נשמר', () {
      expect(canonicalJsonEncode('😀'), '"😀"');
      expect(() => canonicalJsonEncode('\uD83D'), throwsArgumentError);
      expect(hasLoneSurrogate('a\uD83D'), isTrue);
      expect(replaceLoneSurrogates('a\uDE00b😀'), 'a\uFFFDb😀');
    });
  });

  group('DirectErrorReport: גוף הבקשה וה-digest', () {
    final golden = _fixture('direct_report_payload_golden.json');
    final cases = (golden['cases'] as List).cast<Map<String, dynamic>>();

    test('יש מה לבדוק', () => expect(cases.length, greaterThanOrEqualTo(7)));

    for (final c in cases) {
      test('${c['name']}', () {
        final stored = jsonDecode(jsonEncode(c['stored']));
        final report = DirectErrorReport.fromJson(
          stored as Map<String, dynamic>,
        );
        expect(_isSendable(report), c['sendable']);
        if (c['payload'] != null) {
          expect(jsonDecode(report.apiBody), c['payload']);
        }
        expect(DirectErrorReport.fromJson(report.toJson()), report);
      });
    }
  });

  group('AppReport ו-PluginReportRecord: גוף הבקשה', () {
    final golden = _fixture('app_plugin_payload_golden.json');
    for (final c in (golden['cases'] as List).cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        final stored = Map<String, dynamic>.from(c['stored'] as Map);
        if (c['expandLargeFields'] == true) {
          stored.addAll({
            'title': '${'a' * 199}😀truncated',
            'diagnostics': {'huge': 'א' * 160000},
            'errorLog': 'א😀' * 50000,
            'images': [],
          });
        }
        final Map<String, dynamic> body;
        if (c['kind'] == 'app') {
          final report = AppReport.fromJson(stored);
          expect(report.validate() == null, c['valid']);
          body = report.toApiPayload();
        } else {
          body = PluginReportRecord.fromJson(stored).toApiPayload();
        }
        if (c['payloadSha256'] != null) {
          expect(
            sha256.convert(utf8.encode(jsonEncode(body))).toString(),
            c['payloadSha256'],
          );
        } else {
          expect(jsonDecode(jsonEncode(body)), c['payload']);
        }
      });
    }
  });

  group('CrashSignature', () {
    test('hash כפי שהשרת מחשב', () {
      const signature = CrashSignature(
        exceptionType: 'StateError',
        frames: ['main (package:otzaria/main.dart)', 'run'],
      );
      expect(
        signature.hash,
        sha256
            .convert(
              utf8.encode('StateError\nmain (package:otzaria/main.dart)\nrun'),
            )
            .toString(),
      );
    });

    test('פריים מנורמל בלי מספור, שורה ונתיב', () {
      expect(
        CrashSignature.normalizeFrame(
          '#3      Foo.bar (file:///C:/src/otzaria/lib/a/b.dart:12:7)',
        ),
        'Foo.bar (b.dart)',
      );
      expect(
        CrashSignature.selectFrames(
          '#0 x (dart:core)\n#1 y (package:otzaria/y.dart:1:2)',
        ),
        ['y (package:otzaria/y.dart)'],
      );
    });
  });

  group('AppReportRedactor', () {
    final redactor = AppReportRedactor(
      environment: const {
        'USERPROFILE': r'C:\Users\Moshe',
        'USERNAME': 'Moshe',
      },
    );

    test('מייל, נתיב פרופיל ושם משתמש', () {
      expect(
        redactor.redactText(
          r'a.b+c@mail.example.co.il at C:\Users\Moshe\x.txt by moshe',
        ),
        r'<email> at %USERPROFILE%\x.txt by <user>',
      );
      expect(redactor.redactText('C:/Users/Moshe/x'), '%USERPROFILE%/x');
      expect(redactor.redactText('Moshe2 user@x'), 'Moshe2 user@x');
    });

    test('ב-JSON גם המפתחות מוסתרים', () {
      expect(
        redactor.redactJson({
          'Moshe': ['a@b.co'],
        }),
        {
          '<user>': ['<email>'],
        },
      );
    });

    test('טוקן ארוך בלי @ חוזר כמות שהוא', () {
      final token = 'a.' * 50000;
      expect(redactor.redactText(token), token);
    });
  });

  group('ReportServerResponse', () {
    ReportResponseKind kind(int status, [Map<String, dynamic>? body]) =>
        ReportServerResponse(status, body).kind;

    test('2xx נקלט; duplicate מהגוף', () {
      expect(kind(200), ReportResponseKind.accepted);
      expect(kind(201), ReportResponseKind.accepted);
      expect(ReportServerResponse(200, {'duplicate': true}).duplicate, isTrue);
      expect(ReportServerResponse(200, null).duplicate, isFalse);
    });

    test('409 = מזהה חדש; 400/413/422 = דחייה', () {
      expect(kind(409), ReportResponseKind.idConflict);
      for (final status in [400, 413, 422]) {
        expect(kind(status), ReportResponseKind.rejected);
      }
      expect(
        ReportServerResponse(422, {'field': 'title'}).rejectedField,
        'title',
      );
    });

    test('503 shabbat נפרד מ-503 אחר', () {
      expect(
        kind(503, {'error': 'shabbat'}),
        ReportResponseKind.closedForShabbat,
      );
      expect(
        kind(503, {'error': 'intake_disabled'}),
        ReportResponseKind.transient,
      );
      for (final status in [408, 429, 500, 404]) {
        expect(kind(status), ReportResponseKind.transient);
      }
    });

    test('decodeBody: אובייקט JSON בלבד', () {
      expect(ReportServerResponse.decodeBody(utf8.encode('{"a":1}')), {
        'a': 1,
      });
      expect(ReportServerResponse.decodeBody(utf8.encode('[1]')), isNull);
      expect(ReportServerResponse.decodeBody(utf8.encode('<html>')), isNull);
    });
  });

  test('kReportsQueueFormat', () => expect(kReportsQueueFormat, 1));

  test('generateReportUuid הוא UUID v4', () {
    expect(
      generateReportUuid(),
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });
}
