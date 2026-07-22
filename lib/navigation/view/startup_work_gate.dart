import 'package:flutter/foundation.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';

/// מתאם פשוט שמונע הרצת עבודות startup כבדות לפני שהוחלט
/// אם האינדוקס האוטומטי ירוץ, ולפני שהוא הסתיים בפועל.
class StartupWorkGate {
  bool _libraryLoaded = false;
  bool _indexingDecisionResolved = false;
  bool _indexingPendingOrRunning = false;
  bool _startupWorkStarted = false;

  /// מסמן שהספרייה נטענה.
  void markLibraryLoaded() {
    _libraryLoaded = true;
  }

  /// מסמן שהוחלט האם האינדוקס האוטומטי אמור לרוץ.
  void markIndexingDecisionResolved({required bool expectIndexing}) {
    _indexingDecisionResolved = true;
    _indexingPendingOrRunning = expectIndexing;
  }

  /// מעדכן את מצב האינדוקס בפועל.
  void markIndexingRunning(bool isRunning) {
    _indexingPendingOrRunning = isRunning;
  }

  /// מחזיר `true` פעם אחת בלבד, ורק כאשר בטוח להתחיל עבודות startup נוספות.
  bool consumeStartPermission() {
    if (_startupWorkStarted ||
        !_libraryLoaded ||
        !_indexingDecisionResolved ||
        _indexingPendingOrRunning) {
      return false;
    }

    _startupWorkStarted = true;
    return true;
  }
}

/// מתחיל עבודות אתחול מושהות פעם אחת לאחר פתיחת [gate].
///
/// עדכון הספרייה נשלח רק כשהסנכרון האוטומטי ועדכוני הרשת מותרים.
bool tryStartDeferredStartupWork({
  required StartupWorkGate gate,
  required VoidCallback startBackgroundSync,
  required bool Function() isAutoSyncEnabled,
  required bool Function() canUseSoftwareAndBookUpdates,
  required LibraryUpdateBloc Function() libraryUpdateBloc,
}) {
  if (!gate.consumeStartPermission()) {
    return false;
  }

  startBackgroundSync();
  if (isAutoSyncEnabled() && canUseSoftwareAndBookUpdates()) {
    try {
      libraryUpdateBloc().add(const StartLibraryUpdate());
    } catch (error) {
      debugPrint('Could not start library update: $error');
    }
  }
  return true;
}
