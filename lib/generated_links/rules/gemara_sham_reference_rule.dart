import 'package:otzaria/generated_links/rules/gemara_reference_rule.dart';
import 'package:otzaria/generated_links/rules/generated_link_rule.dart';

/// כלל לזיהוי הפניות `(שם)` ו-`(שם X Y)` בגמרא.
///
/// `(שם)` מתייחס לאותה מסכת ואותו דף כמו ההפניה האחרונה שזוהתה לפניו.
/// `(שם צב ב)` מתייחס לאותה מסכת עם דף אחר.
///
/// על המעבד לקרוא לכלל זה אחרי [GemaraReferenceRule] ולהעביר את התוצאות
/// שלו דרך [GeneratedLinkRuleContext.previousReferences].
class GemaraShamReferenceRule implements GeneratedLinkRule {
  /// מספר שורות look-behind מקסימלי לחיפוש הפניה קודמת.
  static const int _lookBehindLines = 20;

  @override
  String get id => 'gemara.sham.v1';

  @override
  int get version => 1;

  /// מזהה `(שם)` עם אופציה ל-`(שם X)` או `(שם X Y)`.
  static final RegExp _shamPattern = RegExp(
    r'\(שם(?:\s+[א-ת]{1,3}(?:\s+[אב](?![א-ת]))?)?\)',
    unicode: true,
  );

  /// מוצא דף ועמוד אופציונלי בתוך `(שם X Y)`.
  static final RegExp _shamDafPattern = RegExp(
    r'שם\s+([א-ת]{1,3})(?:\s+([אב])(?![א-ת]))?',
    unicode: true,
  );

  /// מחפש סוגריים/מרובעים עם תוכן ביניים.
  static final RegExp _bracketPattern = RegExp(
    r'[(\[][^)\]]+[)\]]',
    unicode: true,
  );

  @override
  Future<List<DetectedReference>> detect(
    GeneratedLinkRuleContext context,
    List<String> lines,
    LineRange lineRange,
  ) async {
    final results = <DetectedReference>[];

    for (var lineIdx = lineRange.start;
        lineIdx <= lineRange.end && lineIdx < lines.length;
        lineIdx++) {
      final line = lines[lineIdx];

      for (final match in _shamPattern.allMatches(line)) {
        final lastRef = _findLastGemaraRef(
          context.previousReferences,
          lineIdx,
          match.start,
        );
        if (lastRef == null) continue;

        if (_hasInterveningBrackets(lines, lastRef, lineIdx, match.start)) {
          continue;
        }

        final shamText = match.group(0)!;
        final String targetRefText;

        final dafMatch = _shamDafPattern.firstMatch(shamText);
        if (dafMatch == null) {
          // (שם) — אותו דף ועמוד
          targetRefText = lastRef.targetRefText;
        } else {
          // (שם X Y) — אותה מסכת, דף אחר
          final newDaf = dafMatch.group(1)!;
          final newAmud = dafMatch.group(2);

          // אימות גבולות דף
          final dafNum = GemaraReferenceRule.hebrewToInt(newDaf);
          if (dafNum == null || dafNum < 2) continue;
          final maxDaf = GemaraReferenceRule.maxDafForTractate(
              lastRef.targetBookTitle);
          if (maxDaf != null && dafNum > maxDaf) continue;

          targetRefText = newAmud != null ? '$newDaf $newAmud' : newDaf;
        }

        results.add(DetectedReference(
          sourceLineIndex: lineIdx,
          start: match.start,
          end: match.end,
          matchedText: shamText,
          targetBookTitle: lastRef.targetBookTitle,
          targetRefText: targetRefText,
          ruleId: id,
          confidence: 0.85,
        ));
      }
    }

    return results;
  }

  /// מאתר את ההפניה האחרונה לגמרא שנמצאת לפני [lineIdx]:[charPos].
  ///
  /// מחזיר null אם לא נמצאה הפניה בטווח [_lookBehindLines] שורות.
  DetectedReference? _findLastGemaraRef(
    List<DetectedReference> refs,
    int lineIdx,
    int charPos,
  ) {
    DetectedReference? last;

    for (final ref in refs) {
      // רק הפניות גמרא
      if (!ref.ruleId.startsWith('gemara.reference')) continue;

      if (ref.sourceLineIndex > lineIdx) continue;
      if (ref.sourceLineIndex == lineIdx && ref.start >= charPos) continue;
      if (lineIdx - ref.sourceLineIndex > _lookBehindLines) continue;

      if (last == null ||
          ref.sourceLineIndex > last.sourceLineIndex ||
          (ref.sourceLineIndex == last.sourceLineIndex &&
              ref.start > last.start)) {
        last = ref;
      }
    }

    return last;
  }

  /// בודק אם יש סוגריים/מרובעים עם תוכן בין [lastRef] לבין [shamStart].
  bool _hasInterveningBrackets(
    List<String> lines,
    DetectedReference lastRef,
    int shamLineIdx,
    int shamStart,
  ) {
    for (var lineIdx = lastRef.sourceLineIndex;
        lineIdx <= shamLineIdx;
        lineIdx++) {
      final line = lines[lineIdx];
      final segStart =
          lineIdx == lastRef.sourceLineIndex ? lastRef.end : 0;
      final segEnd =
          lineIdx == shamLineIdx ? shamStart : line.length;

      if (segStart >= segEnd) continue;

      final segment = line.substring(segStart, segEnd);
      if (_bracketPattern.hasMatch(segment)) return true;
    }
    return false;
  }
}
