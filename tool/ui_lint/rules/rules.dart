import '../ui_lint.dart';
import 'hardcoded_color_rule.dart';
import 'icon_button_tooltip_rule.dart';
import 'literal_font_size_rule.dart';
import 'literal_radius_rule.dart';
import 'literal_width_breakpoint_rule.dart';
import 'material_icons_rule.dart';
import 'primary_color_rule.dart';
import 'raw_dialog_rule.dart';
import 'raw_menu_rule.dart';
import 'raw_text_field_rule.dart';
import 'rtl_icon_rule.dart';
import 'ui_snack_literal_rule.dart';

/// הכללים הפעילים, לפי הסדר בקטלוג.
const List<UiLintRule> uiLintRules = [
  RawDialogRule(),
  IconButtonTooltipRule(),
  PrimaryColorRule(),
  MaterialIconsRule(),
  RtlIconRule(),
  UiSnackLiteralRule(),
  RawMenuRule(),
  RawTextFieldRule(),
  HardcodedColorRule(),
  LiteralFontSizeRule(),
  LiteralRadiusRule(),
  LiteralWidthBreakpointRule(),
];
