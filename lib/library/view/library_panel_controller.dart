import 'package:flutter/foundation.dart';
import 'package:otzaria/settings/settings_exports.dart';

/// בורר גלובלי לפאנלים של ספרייה.
///
/// משמש כדי לפתוח או לסגור את פאנל ההגדרות/תצוגה המקדימה גם מהקיצור
/// הגלובלי ומהסרגל העליון, בלי להציג דיאלוג.
class LibraryPanelController {
  LibraryPanelController._();

  static VoidCallback? _showSettingsPanel;
  static ValueChanged<SettingsState>? _openPreviewPanel;
  static ValueChanged<SettingsState>? _closePreviewPanel;
  static ValueChanged<SettingsState>? _togglePreviewPanel;

  static void register({
    required VoidCallback showSettingsPanel,
    required ValueChanged<SettingsState> openPreviewPanel,
    required ValueChanged<SettingsState> closePreviewPanel,
    required ValueChanged<SettingsState> togglePreviewPanel,
  }) {
    _showSettingsPanel = showSettingsPanel;
    _openPreviewPanel = openPreviewPanel;
    _closePreviewPanel = closePreviewPanel;
    _togglePreviewPanel = togglePreviewPanel;
  }

  static void unregister() {
    _showSettingsPanel = null;
    _openPreviewPanel = null;
    _closePreviewPanel = null;
    _togglePreviewPanel = null;
  }

  static bool openSettingsPanel() {
    final handler = _showSettingsPanel;
    if (handler == null) {
      return false;
    }
    handler();
    return true;
  }

  static bool openPreviewPanel(SettingsState settingsState) {
    final handler = _openPreviewPanel;
    if (handler == null) {
      return false;
    }
    handler(settingsState);
    return true;
  }

  static bool closePreviewPanel(SettingsState settingsState) {
    final handler = _closePreviewPanel;
    if (handler == null) {
      return false;
    }
    handler(settingsState);
    return true;
  }

  static bool togglePreviewPanel(SettingsState settingsState) {
    final handler = _togglePreviewPanel;
    if (handler == null) {
      return false;
    }
    handler(settingsState);
    return true;
  }
}
