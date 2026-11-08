import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';

/// מפעיל קיצור "חפש בחלון" לפי ההגדרות. נקרא מתוך build, כדי שהמסך ייבנה
/// מחדש כשהמשתמש משנה את הקיצור.
ShortcutActivator currentWindowSearchActivator(
  BuildContext context, {
  bool mapCtrlToMeta = true,
}) {
  const key = ShortcutValidator.currentWindowSearchKey;
  final shortcut = context.select(
    (SettingsBloc bloc) =>
        bloc.state.shortcuts[key] ??
        ShortcutValidator.defaultShortcuts[key] ??
        'ctrl+f',
  );
  return ShortcutHelper.activatorFromShortcut(
        shortcut,
        mapCtrlToMeta: mapCtrlToMeta,
      ) ??
      const SingleActivator(LogicalKeyboardKey.keyF, control: true);
}
