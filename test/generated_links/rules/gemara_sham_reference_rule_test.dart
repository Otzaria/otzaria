import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/generated_links/rules/gemara_reference_rule.dart';
import 'package:otzaria/generated_links/rules/gemara_sham_reference_rule.dart';
import 'package:otzaria/generated_links/rules/generated_link_rule.dart';

DetectedReference _makeGemaraRef({
  int lineIndex = 0,
  int start = 0,
  int end = 8,
  String tractate = 'ברכות',
  String refText = 'ב א',
}) =>
    DetectedReference(
      sourceLineIndex: lineIndex,
      start: start,
      end: end,
      matchedText: '$tractate ב.',
      targetBookTitle: tractate,
      targetRefText: refText,
      ruleId: 'gemara.reference.v1',
      confidence: 0.9,
    );

Future<List<DetectedReference>> _detect(
  List<String> lines,
  List<DetectedReference> previous, {
  int startLine = 0,
  int endLine = 0,
}) async {
  final ctx = GeneratedLinkRuleContext(
    sourceBookId: 1,
    sourceBookTitle: 'test',
    previousReferences: previous,
  );
  return GemaraShamReferenceRule().detect(
    ctx,
    lines,
    LineRange(startLine, endLine),
  );
}

void main() {
  group('GemaraShamReferenceRule — (שם) בסיסי', () {
    test('(שם) מתייחס למסכת ולדף האחרון שזוהה', () async {
      final prev = [_makeGemaraRef(refText: 'ב א')];
      final refs = await _detect(['ראה ברכות ב. וכן (שם)'], prev);

      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('ברכות'));
      expect(refs.first.targetRefText, equals('ב א'));
    });

    test('(שם) ללא הפניה קודמת — לא מייצר קישור', () async {
      final refs = await _detect(['(שם) חשוב'], []);
      expect(refs, isEmpty);
    });

    test('(שם) בשורה שונה מההפניה הקודמת', () async {
      final prev = [_makeGemaraRef(lineIndex: 0, refText: 'כ א')];
      final refs = await _detect(
        ['ברכות כ.', '(שם) גם כן'],
        prev,
        endLine: 1,
      );
      expect(refs, hasLength(1));
      expect(refs.first.targetRefText, equals('כ א'));
    });
  });

  group('GemaraShamReferenceRule — (שם X Y)', () {
    test('(שם כב ב) — אותה מסכת, דף אחר', () async {
      // ref בשורה 0, שם בשורה 1; קידושין max=82, כב=22 תקין
      final prev = [_makeGemaraRef(lineIndex: 0, tractate: 'קידושין', refText: 'כ א')];
      final refs = await _detect(
        ['קידושין כ.', '(שם כב ב) כתוב'],
        prev,
        startLine: 1,
        endLine: 1,
      );
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('קידושין'));
      expect(refs.first.targetRefText, equals('כב ב'));
    });

    test('(שם צב ב) — דף מעל המקסימום לא מזוהה', () async {
      // קידושין max=82, צב=92 — אמור להידחות
      final prev = [_makeGemaraRef(lineIndex: 0, tractate: 'קידושין', refText: 'כ א')];
      final refs = await _detect(
        ['קידושין כ.', '(שם צב ב) כתוב'],
        prev,
        startLine: 1,
        endLine: 1,
      );
      expect(refs, isEmpty);
    });

    test('(שם ה) — אותה מסכת, דף בלבד', () async {
      // ref בשורה 0, שם בשורה 1 — כך שהref בא לפני השם
      final prev = [_makeGemaraRef(lineIndex: 0, tractate: 'שבת', refText: 'ב א')];
      final refs = await _detect(
        ['שבת ב.', '(שם ה)'],
        prev,
        startLine: 1,
        endLine: 1,
      );
      expect(refs, hasLength(1));
      expect(refs.first.targetRefText, equals('ה'));
    });
  });

  group('GemaraShamReferenceRule — פילטר סוגריים מפרידים', () {
    test('(שם) לאחר סוגריים אחרים — מדולג', () async {
      final prev = [_makeGemaraRef(start: 0, end: 8, refText: 'ב א')];
      // יש (טקסט אחר) בין ברכות ב. לבין (שם)
      final refs =
          await _detect(['ברכות ב. (עניין אחר) (שם)'], prev);
      expect(refs, isEmpty);
    });

    test('(שם) ללא סוגריים מפרידים — תקין', () async {
      final prev = [_makeGemaraRef(start: 0, end: 8, refText: 'ב א')];
      final refs = await _detect(['ברכות ב. (שם)'], prev);
      expect(refs, hasLength(1));
    });
  });

  group('GemaraShamReferenceRule — look-behind גבול', () {
    test('הפניה קודמת מעל 20 שורות — לא מזוהה', () async {
      final lines = List.generate(25, (i) => i == 0 ? 'ברכות ב.' : 'שורה $i');
      lines.add('(שם)');

      final prev = [_makeGemaraRef(lineIndex: 0, refText: 'ב א')];
      final refs = await _detect(
        lines,
        prev,
        startLine: 25,
        endLine: 25,
      );
      expect(refs, isEmpty);
    });

    test('הפניה קודמת בדיוק 20 שורות — מזוהה', () async {
      // ref בשורה 0, (שם) בשורה 20, מרחק = 20 = _lookBehindLines → צריך להיכלל
      final lines = [
        'ברכות ב.',
        ...List.generate(19, (i) => 'שורה ${i + 1}'),
        '(שם)',  // שורה 20
      ];

      final prev = [_makeGemaraRef(lineIndex: 0, refText: 'ב א')];
      final refs = await _detect(
        lines,
        prev,
        startLine: 20,
        endLine: 20,
      );
      expect(refs, hasLength(1));
    });
  });

  group('GemaraShamReferenceRule — ruleId', () {
    test('ruleId תקין', () async {
      final rule = GemaraShamReferenceRule();
      expect(rule.id, equals('gemara.sham.v1'));
    });
  });

  group('GemaraReferenceRule — normalizeAmud', () {
    test('. → א', () => expect(GemaraReferenceRule.normalizeAmud('.'), 'א'));
    test(': → ב', () => expect(GemaraReferenceRule.normalizeAmud(':'), 'ב'));
    test('ע"א → א', () => expect(GemaraReferenceRule.normalizeAmud('ע"א'), 'א'));
    test('ע"ב → ב', () => expect(GemaraReferenceRule.normalizeAmud('ע"ב'), 'ב'));
    test('null → null', () => expect(GemaraReferenceRule.normalizeAmud(null), isNull));
  });
}
