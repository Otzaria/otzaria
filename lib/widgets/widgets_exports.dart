// Barrel re-export — כל הווידג'טים.
//
// דיאלוגים M3:
//   → lib/widgets/dialogs/dialogs_exports.dart
//
// כפתורי פעולה (ActionButton.recommended / .neutral / .ghost,
// SecondaryIconButton, PrimaryIconButton):
//   → lib/widgets/controls/action_buttons.dart
//
// כפתורי סרגל (BarButton.icon / .text):
//   → lib/widgets/controls/bar_button.dart
//
// Segmented control (AppSegmentedControl, SegmentOption):
//   → lib/widgets/controls/segmented_control.dart
//
// SettingsActionTile (switchTile / dropdownTile / segmentedTile):
//   → lib/settings/widgets/settings_card.dart
//
// ToolPanelWrapper:
//   → lib/widgets/misc/tool_ui_helpers.dart

export 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
export 'package:otzaria/widgets/controls/action_buttons.dart';
export 'package:otzaria/widgets/controls/bar_button.dart';
export 'package:otzaria/widgets/controls/custom_switch.dart';
export 'package:otzaria/widgets/controls/segmented_control.dart';
export 'package:otzaria/widgets/layout/app_card.dart';
export 'package:otzaria/widgets/layout/expandable_card.dart';
export 'package:otzaria/widgets/misc/expanding_chevron.dart';
export 'package:otzaria/widgets/misc/tool_ui_helpers.dart';

import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// סגנון כותרת בשורת הגדרה — alias לתאימות לאחור.
const kSettingsTitleStyle = AppTextStyles.settingTitle;

/// סגנון תת-כותרת בשורת הגדרה — alias לתאימות לאחור.
const kSettingsSubtitleStyle = AppTextStyles.settingSubtitle;

/// רווח אנכי סטנדרטי בין כרטיסי הגדרות.
const kSettingsCardSpacing = SizedBox(height: AppTokens.spaceMD);
