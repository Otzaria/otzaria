import 'dart:isolate';
import 'package:otzaria/generated_links/models/generated_inline_link.dart';
import 'package:otzaria/generated_links/models/generated_link_target.dart';
import 'package:otzaria/generated_links/repository/generated_links_book_resolver.dart';
import 'package:otzaria/generated_links/rules/generated_link_rule.dart';
import 'package:otzaria/generated_links/rules/generated_link_rules_registry.dart';

/// מריץ את כללי הזיהוי ב-isolate ופותר יעדים ב-main isolate.
///
/// שני שלבים:
///   1. Isolate: regex + כללי זיהוי → [DetectedReference]
///   2. Main thread: [GeneratedLinksBookResolver] → [GeneratedInlineLink]
class GeneratedLinksProcessor {
  final GeneratedLinksBookResolver resolver;

  /// ניתן להזרקה לצורך בדיקות — מחליף את הריצה ב-isolate.
  final Future<List<DetectedReference>> Function({
    required int sourceBookId,
    required String sourceBookTitle,
    required List<String> lines,
    required int startLine,
    required int endLine,
    required List<DetectedReference> previousRefs,
  })? runRulesOverride;

  GeneratedLinksProcessor({
    required this.resolver,
    this.runRulesOverride,
  });

  /// מפעיל כללים ב-isolate ומחזיר [DetectedReference] גולמי.
  Future<List<DetectedReference>> runRules({
    required int sourceBookId,
    required String sourceBookTitle,
    required List<String> lines,
    required int startLine,
    required int endLine,
    required List<DetectedReference> previousRefs,
  }) async {
    if (runRulesOverride != null) {
      return runRulesOverride!(
        sourceBookId: sourceBookId,
        sourceBookTitle: sourceBookTitle,
        lines: lines,
        startLine: startLine,
        endLine: endLine,
        previousRefs: previousRefs,
      );
    }

    // סריאליזציה לפני שליחה ל-isolate (Map<String, dynamic> בלבד)
    final prevJson = previousRefs.map((r) => r.toJson()).toList();
    final linesCopy = List<String>.unmodifiable(lines);

    final resultMaps = await Isolate.run(() async {
      final prevRefs = prevJson
          .map((m) => DetectedReference.fromJson(m ))
          .toList();
      final ctx = GeneratedLinkRuleContext(
        sourceBookId: sourceBookId,
        sourceBookTitle: sourceBookTitle,
        previousReferences: prevRefs,
      );
      final range = LineRange(startLine, endLine);
      final out = <Map<String, dynamic>>[];
      for (final rule in GeneratedLinkRulesRegistry.defaultRules) {
        for (final ref in await rule.detect(ctx, linesCopy, range)) {
          out.add(ref.toJson());
        }
      }
      return out;
    });

    return resultMaps
        .map((m) => DetectedReference.fromJson(m ))
        .toList();
  }

  /// מריץ כללים ואז פותר כל [DetectedReference] ל-[GeneratedInlineLink].
  ///
  /// הפניות שהיעד שלהן לא נפתר מושמטות בשקט.
  Future<List<GeneratedInlineLink>> processBatch({
    required int sourceBookId,
    required String sourceBookTitle,
    required List<String> lines,
    required int startLine,
    required int endLine,
    required List<DetectedReference> previousRefs,
  }) async {
    final refs = await runRules(
      sourceBookId: sourceBookId,
      sourceBookTitle: sourceBookTitle,
      lines: lines,
      startLine: startLine,
      endLine: endLine,
      previousRefs: previousRefs,
    );

    final links = <GeneratedInlineLink>[];
    for (final ref in refs) {
      final GeneratedLinkTarget? target = await resolver.resolve(
        bookTitle: ref.targetBookTitle,
        refText: ref.targetRefText,
      );
      if (target == null || !target.isResolved) continue;

      links.add(GeneratedInlineLink(
        sourceBookId: sourceBookId,
        sourceLineIndex: ref.sourceLineIndex,
        start: ref.start,
        end: ref.end,
        matchedText: ref.matchedText,
        target: target,
        ruleId: ref.ruleId,
        confidence: ref.confidence,
        createdAt: DateTime.now(),
      ));
    }

    return links;
  }
}
