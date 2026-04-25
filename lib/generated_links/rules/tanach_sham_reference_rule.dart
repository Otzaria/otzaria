import 'package:otzaria/generated_links/rules/generated_link_rule.dart';
import 'package:otzaria/generated_links/rules/tanach_reference_rule.dart';

/// כלל לזיהוי הפניות `(שם)` בהקשר תנ"ך.
///
/// `(שם)` מתייחס לאותו ספר ואותו פרק כמו ההפניה האחרונה שזוהתה לפניו.
/// `(שם X, Y)` — אותו ספר, פרק אחר.
///
/// על המעבד לקרוא לכלל זה אחרי [TanachReferenceRule] ולהעביר את תוצאותיו
/// דרך [GeneratedLinkRuleContext.previousReferences].
class TanachShamReferenceRule implements GeneratedLinkRule {
  static const int _lookBehindLines = 20;

  @override
  String get id => 'tanach.sham.v1';

  @override
  int get version => 1;

  /// `(שם)` עם אופציה ל-`(שם X)` או `(שם X, Y)` / `(שם X Y)`.
  static final RegExp _shamPattern = RegExp(
    r'\(שם(?:\s+(?:\d+|[א-ת]{1,3})(?:(?:,\s*|\s+)(?:\d+|[א-ת]{1,3}))?)?\)',
    unicode: true,
  );

  static final RegExp _shamNumbersPattern = RegExp(
    r'שם\s+((?:\d+|[א-ת]{1,3}))(?:(?:,\s*|\s+)((?:\d+|[א-ת]{1,3})))?',
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
        final lastRef = _findLastTanachRef(
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

        final numsMatch = _shamNumbersPattern.firstMatch(shamText);
        if (numsMatch == null) {
          // (שם) — אותו ספר ואותו מראה מקום
          targetRefText = lastRef.targetRefText;
        } else {
          // (שם X) או (שם X, Y) — אותו ספר, פרק/פסוק שונה
          final ch = numsMatch.group(1)!;
          final vs = numsMatch.group(2);
          final book = lastRef.targetBookTitle;

          // אימות גבולות פרק
          final chNum = TanachReferenceRule.parseNumber(ch);
          if (chNum == null || chNum < 1) continue;
          final maxCh = TanachReferenceRule.maxChaptersForBook(book);
          if (maxCh != null && chNum > maxCh) continue;

          targetRefText = vs != null ? '$book $ch $vs' : '$book $ch';
        }

        results.add(DetectedReference(
          sourceLineIndex: lineIdx,
          start: match.start,
          end: match.end,
          matchedText: shamText,
          targetBookTitle: lastRef.targetBookTitle,
          targetRefText: targetRefText,
          ruleId: id,
          confidence: 0.83,
        ));
      }
    }

    return results;
  }

  DetectedReference? _findLastTanachRef(
    List<DetectedReference> refs,
    int lineIdx,
    int charPos,
  ) {
    DetectedReference? last;

    for (final ref in refs) {
      if (!ref.ruleId.startsWith('tanach.reference')) continue;

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
