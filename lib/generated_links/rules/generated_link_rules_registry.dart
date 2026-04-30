import 'package:otzaria/generated_links/rules/gemara_reference_rule.dart';
import 'package:otzaria/generated_links/rules/gemara_sham_reference_rule.dart';
import 'package:otzaria/generated_links/rules/generated_link_rule.dart';
import 'package:otzaria/generated_links/rules/shulchan_aruch_reference_rule.dart';
import 'package:otzaria/generated_links/rules/tanach_reference_rule.dart';
import 'package:otzaria/generated_links/rules/tanach_sham_reference_rule.dart';

/// רשם הכללים הפעילים.
///
/// הסדר קובע: כלל מוקדם יותר מקבל עדיפות בטווח חופף.
class GeneratedLinkRulesRegistry {
  static final List<GeneratedLinkRule> defaultRules = [
    GemaraReferenceRule(),
    GemaraShamReferenceRule(),
    TanachReferenceRule(),
    TanachShamReferenceRule(),
    ShulchanAruchReferenceRule(),
  ];

  /// מחרוזת גרסה מחושבת מכל הכללים הפעילים.
  ///
  /// שינוי גרסה של כלל אחד מפסיל cache שנבנה עם הגרסה הישנה.
  static String computeRulesVersion(List<GeneratedLinkRule> rules) {
    final parts = rules.map((r) => '${r.id}:${r.version}').join(',');
    return parts;
  }

  static String get defaultRulesVersion => computeRulesVersion(defaultRules);
}
