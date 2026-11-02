import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-006: RtlIcon רק לאייקון כיווני רשום, ואין היפוך ידני של אייקון.
///
/// אייקוני OtzariaIcons מצוירים RTL מלכתחילה, ו-RtlIcon היה הופך אותם שוב.
/// אייקון Fluent או Material שאינו רשום ב-rtl_icon.dart אינו מתהפך כלל.
class RtlIconRule extends UiLintRule {
  const RtlIconRule();

  static const registryPath = 'lib/widgets/misc/rtl_icon.dart';

  static final _registries = <String, Set<String>>{};

  @override
  String get id => 'UIL-006';

  @override
  int get stage => 1;

  @override
  String get title => 'RtlIcon לאייקון לא רשום, או Transform.flip סביב אייקון';

  @override
  String get hint =>
      'OtzariaIcons, אייקון סימטרי או אייקון שמתהפך בעצמו (matchTextDirection): '
      'Icon(...). אייקון כיווני אחר: לרשום ב-$registryPath ולהשתמש ב-RtlIcon '
      '(DESIGN_SYSTEM.md §2.5.1)';

  /// האייקונים שבמפות ובסט של rtl_icon.dart, לפני build().
  static Set<String> registered(String root) =>
      _registries.putIfAbsent(p.normalize(root), () {
        final source = File(p.join(root, registryPath)).readAsStringSync();
        final build = source.indexOf('Widget build(');
        final definitions = build > 0 ? source.substring(0, build) : source;
        final icons = {
          for (final match in RegExp(
            r'\b(?:FluentIcons|Icons)\.\w+',
          ).allMatches(definitions))
            match.group(0)!,
        };
        if (icons.isEmpty) {
          throw StateError('לא נמצאו אייקונים רשומים ב-$registryPath');
        }
        return icons;
      });

  @override
  void check(UiLintFile file) {
    for (final call in ctorCallsNamed(file.unit, {'RtlIcon', 'Transform'})) {
      if (call.importPrefix != null) continue;
      if (call.typeName == 'RtlIcon' && call.constructor == null) {
        final icon = call.positional.firstOrNull?.unParenthesized;
        if (icon is! PrefixedIdentifier) continue;
        final name = icon.toSource();
        if (icon.prefix.name == 'OtzariaIcons' ||
            ({'FluentIcons', 'Icons'}.contains(icon.prefix.name) &&
                !registered(file.root).contains(name))) {
          file.report(this, call.node, identity: name);
        }
      } else if (call.typeName == 'Transform' && _mirrors(call)) {
        final child = call.named('child');
        final inner = child == null ? null : asCtorCall(child.unParenthesized);
        if (inner != null && {'Icon', 'RtlIcon'}.contains(inner.typeName)) {
          file.report(this, call.node, identity: call.head);
        }
      }
    }
  }

  /// `Transform.flip(...)` או `Transform.scale(scaleX: -n)`: היפוך אופקי.
  static bool _mirrors(CtorCall call) {
    if (call.constructor == 'flip') return true;
    final scaleX = call.named('scaleX')?.unParenthesized;
    return call.constructor == 'scale' &&
        scaleX is PrefixExpression &&
        scaleX.operator.lexeme == '-';
  }
}
