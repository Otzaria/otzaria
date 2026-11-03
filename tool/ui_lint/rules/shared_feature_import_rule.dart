import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../ui_lint.dart';

/// UIL-024: רכיב משותף (lib/widgets) לא מייבא קוד פיצ'ר.
///
/// הרשימה היא זו של DESIGN_SYSTEM.md §3 כלל 4: settings bloc, plugins,
/// tabs ו-models. settings/l10n (settingsText) מותר.
class SharedFeatureImportRule extends UiLintRule {
  const SharedFeatureImportRule();

  static const sharedRoot = 'lib/widgets/';

  static const _forbidden = [
    'lib/settings/engine/',
    'lib/settings/settings_exports.dart',
    'lib/plugins/',
    'lib/tabs/',
    'lib/models/',
  ];

  @override
  String get id => 'UIL-024';

  @override
  int get stage => 2;

  @override
  String get title => 'רכיב משותף מייבא קוד פיצ\'ר';

  @override
  String get hint =>
      'להעביר את הנתון בפרמטר, את הצפיפות דרך AppDensity, ואת מה שהפיצ\'ר '
      'מוסיף דרך scope או ממשק שהפיצ\'ר מממש (DESIGN_SYSTEM.md §3 כלל 4, §4.1)';

  /// הנתון שהייבוא מצביע עליו, יחסית לשורש המאגר; null מחוץ ל-package:otzaria.
  static String? _target(String fromPath, String uri) {
    if (uri.startsWith('package:otzaria/')) {
      return 'lib/${uri.substring('package:otzaria/'.length)}';
    }
    if (uri.contains(':')) return null;
    return p.posix.normalize(p.posix.join(p.posix.dirname(fromPath), uri));
  }

  @override
  void check(UiLintFile file) {
    if (!file.path.startsWith(sharedRoot)) return;
    for (final directive in file.unit.directives) {
      if (directive is! NamespaceDirective) continue;
      final uri = directive.uri.stringValue;
      if (uri == null) continue;
      final target = _target(file.path, uri);
      if (target == null) continue;
      if (_forbidden.any(target.startsWith)) file.report(this, directive);
    }
  }
}
