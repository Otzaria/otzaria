import 'package:otzaria/generated_links/rules/generated_link_rule.dart';
import 'package:otzaria/generated_links/rules/tanach_reference_rule.dart';

/// כלל לזיהוי מראי מקומות לשולחן ערוך ונושאי כליו.
///
/// תומך בשלב זה בהפניות חלק+סימן, למשל `ביו"ד סי' פג`, ובהפניות לש"ך
/// באותו סימן, למשל `ביו"ד סי' פג בש"ך ס"ק טו`.
class ShulchanAruchReferenceRule implements GeneratedLinkRule {
  @override
  String get id => 'shulchan_aruch.reference.v1';

  @override
  int get version => 1;

  static const String _numPat = "(?:\\d+|[א-ת]{1,3}(?:[\"״׳'][א-ת]{1,3})?)";

  static final RegExp _partPattern = RegExp(
    r'(?<![א-ת])'
    r'(?:ב)?'
    r'('
    r'או["״]?ח|אוח|אורח\s+חיים|'
    r'יו["״]?ד|יוד|יורה\s+דעה|'
    r'אה["״]?ע|אבן\s+העזר|'
    r'חו["״]?מ|חומ|חושן\s+משפט'
    r')'
    r'\s+'
    r"(?:סי(?:מן|[׳'])?\.?|סימן)\s+"
    '($_numPat)',
    unicode: true,
  );

  static final RegExp _shachPattern = RegExp(
    r'(?<![א-ת])'
    r'(?:ב)?'
    r'('
    r'יו["״]?ד|יוד|יורה\s+דעה|'
    r'חו["״]?מ|חומ|חושן\s+משפט'
    r')'
    r'\s+'
    r"(?:סי(?:מן|[׳'])?\.?|סימן)\s+"
    '($_numPat)'
    r'\s+'
    r'(ב?ש["״]?ך|ב?שך)\s+'
    r'ס["״]?ק\s+'
    '($_numPat)',
    unicode: true,
  );

  static const Map<String, String> _canonicalPartTitles = {
    'אורח חיים': 'שולחן ערוך, אורח חיים',
    'יורה דעה': 'שולחן ערוך, יורה דעה',
    'אבן העזר': 'שולחן ערוך, אבן העזר',
    'חושן משפט': 'שולחן ערוך, חושן משפט',
  };

  static const Map<String, String> _shachTitles = {
    'יורה דעה': 'שפתי כהן על שולחן ערוך יורה דעה',
    'חושן משפט': 'שפתי כהן על שולחן ערוך חושן משפט',
  };

  @override
  Future<List<DetectedReference>> detect(
    GeneratedLinkRuleContext context,
    List<String> lines,
    LineRange lineRange,
  ) async {
    final results = <DetectedReference>[];

    for (var i = lineRange.start; i <= lineRange.end && i < lines.length; i++) {
      final line = lines[i];

      for (final match in _partPattern.allMatches(line)) {
        final part = _normalizePart(match.group(1)!);
        final bookTitle = _canonicalPartTitles[part];
        if (bookTitle == null) continue;

        final siman = _normalizeNumber(match.group(2)!);
        results.add(DetectedReference(
          sourceLineIndex: i,
          start: match.start,
          end: match.end,
          matchedText: match.group(0)!,
          targetBookTitle: bookTitle,
          targetRefText: 'סימן $siman',
          ruleId: id,
          confidence: 0.82,
        ));
      }

      for (final match in _shachPattern.allMatches(line)) {
        final part = _normalizePart(match.group(1)!);
        final bookTitle = _shachTitles[part];
        if (bookTitle == null) continue;

        final siman = _normalizeNumber(match.group(2)!);
        final seif = _normalizeNumber(match.group(4)!);
        final commentaryStart = line.indexOf(match.group(3)!, match.start);
        if (commentaryStart < 0) continue;

        results.add(DetectedReference(
          sourceLineIndex: i,
          start: commentaryStart,
          end: match.end,
          matchedText: line.substring(commentaryStart, match.end),
          targetBookTitle: bookTitle,
          targetRefText: 'סימן $siman סעיף $seif',
          ruleId: id,
          confidence: 0.86,
        ));
      }
    }

    return results;
  }

  static String _normalizePart(String raw) {
    final normalized = raw
        .replaceAll('"', '')
        .replaceAll('״', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return switch (normalized) {
      'אוח' || 'אורח חיים' => 'אורח חיים',
      'יוד' || 'יורה דעה' => 'יורה דעה',
      'אהע' || 'אבן העזר' => 'אבן העזר',
      'חומ' || 'חושן משפט' => 'חושן משפט',
      _ => normalized,
    };
  }

  static String _normalizeNumber(String raw) =>
      TanachReferenceRule.normalizeNumberText(raw);
}
