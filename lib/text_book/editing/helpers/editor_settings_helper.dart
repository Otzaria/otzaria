import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import '../models/editor_settings.dart';

/// Helper class to get editor settings from local settings storage.
class EditorSettingsHelper {
  static EditorSettings getSettings() {
    return EditorSettings(
      previewDebounce: Duration(
        milliseconds:
            Settings.getValue<double>('key-editor-preview-debounce')?.toInt() ??
            150,
      ),
      globalDraftsQuotaMB:
          Settings.getValue<double>('key-editor-drafts-quota')?.toInt() ?? 100,
      draftCleanupDays:
          Settings.getValue<double>('key-editor-draft-cleanup-days')?.toInt() ??
          30,
    );
  }
}
