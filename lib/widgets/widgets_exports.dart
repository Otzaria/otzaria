// Barrel re-export — כל הווידג'טים שהיו כאן פוצלו לקבצים נפרדים.
//
// דיאלוגים M3:
//   → lib/widgets/dialogs/app_dialogs.dart
//
// כפתורי פעולה (RecommendedActionButton, NeutralActionButton,
// SecondaryIconButton, PrimaryIconButton):
//   → lib/widgets/buttons/action_buttons.dart
//
// Segmented button:
//   → lib/widgets/inputs/segmented_button_tile.dart
//
// SwitchSettingsTile:
//   → lib/settings/widgets/switch_settings_tile.dart
//
// toolCardColor, ToolPanelWrapper:
//   → lib/widgets/misc/tool_ui_helpers.dart

export 'package:otzaria/widgets/dialogs/app_dialogs.dart';
export 'package:otzaria/widgets/buttons/action_buttons.dart';
export 'package:otzaria/widgets/inputs/segmented_button_tile.dart';
export 'package:otzaria/settings/widgets/switch_settings_tile.dart';
export 'package:otzaria/widgets/misc/tool_ui_helpers.dart';

import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// סגנון כותרת בשורת הגדרה — alias לתאימות לאחור.
const kSettingsTitleStyle = AppTextStyles.settingTitle;

/// סגנון תת-כותרת בשורת הגדרה — alias לתאימות לאחור.
const kSettingsSubtitleStyle = AppTextStyles.settingSubtitle;

/// רווח אנכי סטנדרטי בין כרטיסי הגדרות.
const kSettingsCardSpacing = SizedBox(height: AppTokens.spaceMD);
