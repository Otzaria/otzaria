import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/generated_links/rules/generated_link_rule.dart';
import 'package:otzaria/generated_links/rules/tanach_reference_rule.dart';
import 'package:otzaria/generated_links/rules/tanach_sham_reference_rule.dart';

final _ctx = const GeneratedLinkRuleContext(
  sourceBookId: 1,
  sourceBookTitle: 'test',
);

Future<List<DetectedReference>> _detectTanach(String line) async =>
    TanachReferenceRule().detect(_ctx, [line], const LineRange(0, 0));

void main() {
  group('TanachReferenceRule — תבנית סוגריים עגולות', () {
    test('(בראשית א, א)', () async {
      final refs = await _detectTanach('כתוב (בראשית א, א) בתורה');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('בראשית'));
      expect(refs.first.targetRefText, contains('בראשית'));
      expect(refs.first.targetRefText, contains('א'));
    });

    test('(בראשית א א) — ללא פסיק', () async {
      final refs = await _detectTanach('(בראשית א א)');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('בראשית'));
    });

    test('(שמות כ, ב)', () async {
      final refs = await _detectTanach('(שמות כ, ב)');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('שמות'));
    });
  });

  group('TanachReferenceRule — תבנית סוגריים מרובעות', () {
    test('[בראשית א, א]', () async {
      final refs = await _detectTanach('[בראשית א, א]');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('בראשית'));
    });

    test('סוגריים לא תואמות ([ ]) לא מזוהות', () async {
      final refs = await _detectTanach('[בראשית א, א)');
      expect(refs, isEmpty);
    });
  });

  group('TanachReferenceRule — תבנית מפורשת פרק/פסוק', () {
    test('בראשית פרק א פסוק א', () async {
      final refs = await _detectTanach('בראשית פרק א פסוק א');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('בראשית'));
      expect(refs.first.confidence, greaterThan(0.9));
    });

    test('תהלים פרק קיט פסוק א → תהילים לפי שם הקטלוג', () async {
      final refs = await _detectTanach('תהלים פרק קיט פסוק א');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('תהילים'));
    });

    test('ספרים שמספרי פרקיהם ערביים', () async {
      final refs = await _detectTanach('בראשית פרק 1 פסוק 1');
      expect(refs, hasLength(1));
      expect(refs.first.targetRefText, equals('בראשית א א'));
    });

    test('תהלים פרק קי"ט פסוק א → מנורמל לפי line.heRef ב-DB', () async {
      final refs = await _detectTanach('תהלים פרק קי"ט פסוק א');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('תהילים'));
      expect(refs.first.targetRefText, equals('תהילים קיט א'));
    });
  });

  group('TanachReferenceRule — ראשי תיבות', () {
    test('שמ"א ח, א', () async {
      final refs = await _detectTanach('(שמ"א ח, א)');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('שמואל א'));
    });

    test('מל"ב ב, א', () async {
      final refs = await _detectTanach('(מל"ב ב, א)');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('מלכים ב'));
    });

    test('דה"א כח, ד', () async {
      final refs = await _detectTanach('(דה"א כח, ד)');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('דברי הימים א'));
    });

    test('דה״ב לו, כג — גרשיים עברי', () async {
      final refs = await _detectTanach('(דה״ב לו, כג)');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('דברי הימים ב'));
    });

    test('(תהלים קי״ט, א) — גרשיים במספר הפרק', () async {
      final refs = await _detectTanach('(תהלים קי״ט, א)');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('תהילים'));
      expect(refs.first.targetRefText, equals('תהילים קיט א'));
    });
  });

  group('TanachReferenceRule — אימות גבולות', () {
    test('פרק מעל המקסימום לא מזוהה', () async {
      // בראשית יש 50 פרקים; נא = 51
      final refs = await _detectTanach('(בראשית נא, א)');
      expect(refs, isEmpty);
    });

    test('פרק א תקין', () async {
      final refs = await _detectTanach('(בראשית א, א)');
      expect(refs, hasLength(1));
    });

    test('ספר לא קיים לא מזוהה', () async {
      final refs = await _detectTanach('(חנוך א, א)');
      expect(refs, isEmpty);
    });
  });

  group('TanachReferenceRule — start/end מדויקים', () {
    test('שני מראי מקום באותה שורה', () async {
      const line = 'ראה (בראשית א, א) וגם (שמות א, א)';
      final refs = await _detectTanach(line);
      expect(refs, hasLength(2));
      expect(refs.first.start, isNot(equals(refs.last.start)));
      expect(line.substring(refs.first.start, refs.first.end),
          equals('(בראשית א, א)'));
      expect(line.substring(refs.last.start, refs.last.end),
          equals('(שמות א, א)'));
    });
  });

  group('TanachReferenceRule — ספרים מורכבים', () {
    test('שיר השירים א, א', () async {
      final refs = await _detectTanach('(שיר השירים א, א)');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('שיר השירים'));
    });

    test('דברי הימים א כח, א', () async {
      final refs = await _detectTanach('(דברי הימים א כח, א)');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('דברי הימים א'));
    });
  });

  group('TanachShamReferenceRule — (שם) בסיסי', () {
    DetectedReference makeTanachRef({
      int lineIndex = 0,
      String book = 'בראשית',
      String refText = 'בראשית א א',
    }) =>
        DetectedReference(
          sourceLineIndex: lineIndex,
          start: 0,
          end: 12,
          matchedText: '($book א, א)',
          targetBookTitle: book,
          targetRefText: refText,
          ruleId: 'tanach.reference.v1',
          confidence: 0.92,
        );

    test('(שם) מתייחס לספר ולמקום האחרון', () async {
      final prev = [makeTanachRef(refText: 'בראשית א א')];
      final ctx = GeneratedLinkRuleContext(
        sourceBookId: 1,
        sourceBookTitle: 'test',
        previousReferences: prev,
      );
      final refs = await TanachShamReferenceRule()
          .detect(ctx, ['ראה (שם)'], const LineRange(0, 0));
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('בראשית'));
      expect(refs.first.targetRefText, equals('בראשית א א'));
    });

    test('(שם) ללא הפניה קודמת — לא מייצר קישור', () async {
      final refs = await TanachShamReferenceRule()
          .detect(_ctx, ['(שם)'], const LineRange(0, 0));
      expect(refs, isEmpty);
    });

    test('(שם ב, א) — אותו ספר, פרק אחר', () async {
      // ref בשורה 0, שם בשורה 1 — כדי שהref יבוא לפני השם
      final prev = [
        DetectedReference(
          sourceLineIndex: 0,
          start: 0,
          end: 13,
          matchedText: '(בראשית א, א)',
          targetBookTitle: 'בראשית',
          targetRefText: 'בראשית א א',
          ruleId: 'tanach.reference.v1',
          confidence: 0.92,
        ),
      ];
      final ctx = GeneratedLinkRuleContext(
        sourceBookId: 1,
        sourceBookTitle: 'test',
        previousReferences: prev,
      );
      final refs = await TanachShamReferenceRule().detect(
        ctx,
        ['(בראשית א, א)', '(שם ב, א)'],
        const LineRange(1, 1),
      );
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('בראשית'));
      expect(refs.first.targetRefText, contains('ב'));
    });

    test('(שם קי״ט, א) — מנרמל גרשיים במספר הפרק', () async {
      final prev = [
        DetectedReference(
          sourceLineIndex: 0,
          start: 0,
          end: 13,
          matchedText: '(תהילים א, א)',
          targetBookTitle: 'תהילים',
          targetRefText: 'תהילים א א',
          ruleId: 'tanach.reference.v1',
          confidence: 0.92,
        ),
      ];
      final ctx = GeneratedLinkRuleContext(
        sourceBookId: 1,
        sourceBookTitle: 'test',
        previousReferences: prev,
      );
      final refs = await TanachShamReferenceRule().detect(
        ctx,
        ['(תהילים א, א)', '(שם קי״ט, א)'],
        const LineRange(1, 1),
      );
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('תהילים'));
      expect(refs.first.targetRefText, equals('תהילים קיט א'));
    });
  });
}
