import 'package:flutter/widgets.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';

/// קיצורי קורא PDF לפי ההגדרות, לרבות המקלדת הנומרית ומוסכמות macOS.
Map<ShortcutActivator, VoidCallback> pdfReadingShortcutBindings({
  required VoidCallback zoomIn,
  required VoidCallback zoomOut,
  required VoidCallback resetZoom,
  required VoidCallback fitView,
  required VoidCallback previousLocation,
  required VoidCallback nextLocation,
  required VoidCallback nextMatch,
  required VoidCallback previousMatch,
}) {
  final actions = {
    ShortcutValidator.zoomInKey: zoomIn,
    ShortcutValidator.zoomOutKey: zoomOut,
    ShortcutValidator.zoomResetKey: resetZoom,
    ShortcutValidator.fitPdfViewKey: fitView,
    ShortcutValidator.previousPdfLocationKey: previousLocation,
    ShortcutValidator.nextPdfLocationKey: nextLocation,
    ShortcutValidator.findNextKey: nextMatch,
    ShortcutValidator.findPreviousKey: previousMatch,
  };
  return {
    for (final entry in actions.entries)
      for (final activator in ShortcutHelper.activatorsFromShortcut(
        ShortcutValidator.getShortcutValue(entry.key) ?? '',
      ))
        activator: entry.value,
  };
}
