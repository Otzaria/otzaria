import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/generated_links/rules/gemara_reference_rule.dart';
import 'package:otzaria/generated_links/rules/gemara_sham_reference_rule.dart';
import 'package:otzaria/generated_links/rules/generated_link_rule.dart';

final _ctx = const GeneratedLinkRuleContext(
  sourceBookId: 1,
  sourceBookTitle: 'test',
);

Future<List<DetectedReference>> _detect(String line) async {
  final rule = GemaraReferenceRule();
  return rule.detect(_ctx, [line], const LineRange(0, 0));
}

Future<List<DetectedReference>> _detectSham(
  String line,
  DetectedReference previous,
) async {
  final ctx = GeneratedLinkRuleContext(
    sourceBookId: 1,
    sourceBookTitle: 'test',
    previousReferences: [previous],
  );
  return GemaraShamReferenceRule().detect(
    ctx,
    ['קידושין כ.', line],
    const LineRange(1, 1),
  );
}

DetectedReference _previousGemaraRef({
  String tractate = 'קידושין',
  String refText = 'כ א',
}) {
  return DetectedReference(
    sourceLineIndex: 0,
    start: 0,
    end: 9,
    matchedText: '$tractate כ.',
    targetBookTitle: tractate,
    targetRefText: refText,
    ruleId: 'gemara.reference.v1',
    confidence: 0.9,
  );
}

void main() {
  group('GemaraReferenceRule — מספרי דף עם גרשיים', () {
    test('דשבת כ"ג ע"ב — מספר דף עם גרשיים רגיל', () async {
      final refs = await _detect('דשבת כ"ג ע"ב');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('שבת'));
      expect(refs.first.matchedText, equals('דשבת כ"ג ע"ב'));
      expect(refs.first.targetRefText, equals('כג ב'));
    });

    test('דשבת כ״ג ע״ב — גרשיים עברי', () async {
      final refs = await _detect('דשבת כ״ג ע״ב');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('שבת'));
      expect(refs.first.targetRefText, equals('כג ב'));
    });

    test('ברכות י"ג. — מספר דף עם גרשיים', () async {
      final refs = await _detect('ברכות י"ג.');
      expect(refs, hasLength(1));
      expect(refs.first.targetRefText, equals('יג א'));
    });

    test('ברכות ט"ו: — טו עם גרשיים', () async {
      final refs = await _detect('ברכות ט"ו:');
      expect(refs, hasLength(1));
      expect(refs.first.targetRefText, equals('טו ב'));
    });

    test('בבא קמא קט"ז. — טז suffix אחרי מאה', () async {
      final refs = await _detect('בבא קמא קט"ז.');
      expect(refs, hasLength(1));
      expect(refs.first.targetRefText, equals('קטז א'));
    });

    test('בבא קמא ק"יט. — מספר גדול עם גרשיים', () async {
      final refs = await _detect('בבא קמא ק"יט.');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('בבא קמא'));
      expect(refs.first.targetRefText, equals('קיט א'));
    });

    test('סנהדרין צ"ב ב — צדי עם גרשיים', () async {
      final refs = await _detect('סנהדרין צ"ב ב');
      expect(refs, hasLength(1));
      expect(refs.first.targetRefText, equals('צב ב'));
    });

    test('שבת קנ"ח. — מעל המקסימום לא מזוהה', () async {
      final refs = await _detect('שבת קנ"ח.');
      expect(refs, isEmpty);
    });

    test('שבת קנ"ז. — בדיוק המקסימום מזוהה', () async {
      final refs = await _detect('שבת קנ"ז.');
      expect(refs, hasLength(1));
      expect(refs.first.targetRefText, equals('קנז א'));
    });
  });

  group('GemaraReferenceRule — סוגריים ופסיקים', () {
    test('(ברכות כב, ב) מזוהה כעמוד ב', () async {
      final refs = await _detect('ראה (ברכות כב, ב)');
      expect(refs, hasLength(1));
      expect(refs.first.matchedText, equals('(ברכות כב, ב)'));
      expect(refs.first.targetRefText, equals('כב ב'));
    });

    test('[ברכות כב:] מזוהה עם סוגריים מרובעים', () async {
      final refs = await _detect('ראה [ברכות כב:]');
      expect(refs, hasLength(1));
      expect(refs.first.matchedText, equals('[ברכות כב:]'));
      expect(refs.first.targetRefText, equals('כב ב'));
    });
  });

  group('GemaraReferenceRule — hebrewToInt עם גרשיים ואימות', () {
    test('כ"ג = 23', () {
      expect(GemaraReferenceRule.hebrewToInt('כ"ג'), 23);
    });

    test('קנ"ז = 157', () {
      expect(GemaraReferenceRule.hebrewToInt('קנ"ז'), 157);
    });

    test('קט"ז = 116', () {
      expect(GemaraReferenceRule.hebrewToInt('קט"ז'), 116);
    });

    test('בהב נדחה', () {
      expect(GemaraReferenceRule.hebrewToInt('בהב'), isNull);
    });

    test('גכ נדחה', () {
      expect(GemaraReferenceRule.hebrewToInt('גכ'), isNull);
    });
  });

  group('GemaraReferenceRule — false positives עם מילים לא מספריות', () {
    test('תענית בהב לא מזוהה כהפניה', () async {
      final refs = await _detect('תענית בהב הוא יום תענית');
      expect(refs, isEmpty);
    });

    test('שבת ויוט לא מזוהה כהפניה', () async {
      final refs = await _detect('שבת ויוט הוא שם של משהו');
      expect(refs, isEmpty);
    });

    test('ברכות גכ לא מזוהה', () async {
      final refs = await _detect('ברכות גכ משהו');
      expect(refs, isEmpty);
    });
  });

  group('GemaraShamReferenceRule — גרשיים', () {
    test('(שם כ"ב ב) מזוהה ומנקה גרשיים', () async {
      final refs = await _detectSham(
        '(שם כ"ב ב)',
        _previousGemaraRef(),
      );
      expect(refs, hasLength(1));
      expect(refs.first.targetRefText, equals('כב ב'));
    });

    test('(שם כ"ב:) מזוהה כעמוד ב', () async {
      final refs = await _detectSham(
        '(שם כ"ב:)',
        _previousGemaraRef(),
      );
      expect(refs, hasLength(1));
      expect(refs.first.targetRefText, equals('כב ב'));
    });
  });
}
