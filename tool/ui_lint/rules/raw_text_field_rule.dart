import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-011: שדה קלט גולמי במקום RtlTextField (issue #1470).
class RawTextFieldRule extends UiLintRule {
  const RawTextFieldRule();

  static const _types = {'TextField', 'TextFormField', 'EditableText'};

  @override
  String get id => 'UIL-011';

  @override
  int get stage => 1;

  @override
  String get title => 'TextField/TextFormField/EditableText גולמי';

  @override
  String get hint =>
      'RtlTextField — שדה גולמי שובר חיצים ובחירה בעברית ב-Desktop '
      '(docs/rtl-text-field-guide.md)';

  @override
  void check(UiLintFile file) {
    for (final call in ctorCallsNamed(file.unit, _types)) {
      if (call.importPrefix == null) {
        file.report(this, call.node, identity: call.head);
      }
    }
  }
}
