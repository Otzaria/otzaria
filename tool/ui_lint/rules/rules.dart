import '../ui_lint.dart';
import 'elevation_shadow_rule.dart';
import 'hardcoded_color_rule.dart';
import 'icon_button_tooltip_rule.dart';
import 'icon_size_rule.dart';
import 'literal_duration_rule.dart';
import 'literal_font_family_rule.dart';
import 'literal_font_size_rule.dart';
import 'literal_radius_rule.dart';
import 'literal_width_breakpoint_rule.dart';
import 'local_alpha_rule.dart';
import 'material_icons_rule.dart';
import 'physical_direction_rule.dart';
import 'primary_color_rule.dart';
import 'raw_dialog_rule.dart';
import 'raw_menu_rule.dart';
import 'raw_text_field_rule.dart';
import 'rtl_icon_rule.dart';
import 'shared_feature_import_rule.dart';
import 'snack_bar_rule.dart';
import 'spacing_scale_rule.dart';
import 'state_color_override_rule.dart';
import 'ui_snack_literal_rule.dart';

/// הכללים הפעילים, לפי הסדר בקטלוג.
const List<UiLintRule> uiLintRules = [
  RawDialogRule(),
  IconButtonTooltipRule(),
  PrimaryColorRule(),
  MaterialIconsRule(),
  RtlIconRule(),
  StateColorOverrideRule(),
  SnackBarRule(),
  UiSnackLiteralRule(),
  RawTextFieldRule(),
  RawMenuRule(),
  HardcodedColorRule(),
  LocalAlphaRule(),
  LiteralFontSizeRule(),
  LiteralFontFamilyRule(),
  LiteralRadiusRule(),
  SpacingScaleRule(),
  PhysicalDirectionRule(),
  LiteralWidthBreakpointRule(),
  LiteralDurationRule(),
  IconSizeRule(),
  SharedFeatureImportRule(),
  ElevationShadowRule(),
];
