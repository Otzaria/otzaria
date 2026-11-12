import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import 'library_changes_dialog.dart';
import 'library_changes_fetcher.dart';
import 'library_changes_store.dart';

/// הורדת "מה חדש בספרים" אחרי עדכון והצגתו — פעם אחת לכל release.
class LibraryChangesNotes {
  LibraryChangesNotes({
    LibraryChangesStore? store,
    LibraryChangesFetcher? fetcher,
    Future<void> Function(BuildContext, List<LibraryChangesNote>)? showDialog,
    BuildContext? Function()? contextProvider,
    bool Function()? isOffline,
  }) : store = store ?? LibraryChangesStore(),
       _fetcherOverride = fetcher,
       _showDialog = showDialog ?? showLibraryChangesDialog,
       _context = contextProvider ?? (() => navigatorKey.currentContext),
       _isOffline =
           isOffline ??
           (() =>
               Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ??
               false);

  static final instance = LibraryChangesNotes();

  final LibraryChangesStore store;
  final LibraryChangesFetcher? _fetcherOverride;
  late final LibraryChangesFetcher _fetcher =
      _fetcherOverride ?? LibraryChangesFetcher(store: store);
  final Future<void> Function(BuildContext, List<LibraryChangesNote>)
  _showDialog;
  final BuildContext? Function() _context;
  final bool Function() _isOffline;

  /// ממתין לפני הצגה אוטומטית — המסך הראשי רושם כאן את סיום הסיור המודרך.
  Future<void> Function()? beforeAutoShow;

  /// עולה בכל שינוי בהערות השמורות — מסך ההגדרות מרענן לפיו את הכפתור.
  final revision = ValueNotifier<int>(0);

  bool _showing = false;
  bool _showAgain = false;

  /// אחרי עדכון ספרייה: מוריד את ההערות של [releaseTags] ומציג את הממתינות.
  /// תג שעוד אין לו קובץ נשאר בתור לעליות הבאות. לעולם אינו זורק.
  Future<void> afterLibraryUpdate(List<String> releaseTags) async {
    try {
      await _fetcher.enqueue(releaseTags);
      await _fetchQueued();
      await showPending();
    } catch (error, stackTrace) {
      _log(error, stackTrace);
    }
  }

  /// בעלייה: ניסיון חוזר לתגים שבתור (לא במצב מנותק) והצגת הממתינות.
  Future<void> onStartup() async {
    try {
      if (!_isOffline()) await _fetchQueued();
      await showPending();
    } catch (error, stackTrace) {
      _log(error, stackTrace);
    }
  }

  Future<void> _fetchQueued() async {
    if (await _fetcher.fetchQueued() > 0) revision.value++;
  }

  /// מציג את ההערות הממתינות (גם אלה שכתב המעדכן הלא-מקוון), ובסגירה מעביר
  /// אותן ל"נצפו". בלי Navigator הן נשארות לפעם הבאה.
  Future<void> showPending() async {
    if (_showing) {
      _showAgain = true;
      return;
    }
    _showing = true;
    try {
      await beforeAutoShow?.call();
      do {
        _showAgain = false;
        final pending = await store.readPending();
        if (pending.isEmpty) return;
        final context = _context();
        if (context == null || !context.mounted) return;
        await _showDialog(context, pending);
        await _markSeen(pending);
      } while (_showAgain);
    } catch (error, stackTrace) {
      _log(error, stackTrace);
    } finally {
      _showing = false;
    }
  }

  /// "מה חדש בגרסת הספרייה" ממסך ההגדרות: כל ההערות השמורות, החדשה קודם.
  Future<void> showAll(BuildContext context) async {
    if (_showing) return;
    _showing = true;
    try {
      final notes = await store.readAll();
      if (notes.isEmpty || !context.mounted) return;
      await _showDialog(context, notes);
      await _markSeen(notes);
    } catch (error, stackTrace) {
      _log(error, stackTrace);
    } finally {
      _showing = false;
      if (_showAgain) await showPending();
    }
  }

  Future<void> _markSeen(List<LibraryChangesNote> notes) async {
    await store.markSeen(notes);
    revision.value++;
  }

  void _log(Object error, StackTrace stackTrace) {
    debugPrint('[LibraryChanges] $error\n$stackTrace');
    try {
      ErrorLogFile.appendInBackground(
        title: 'Library changes notes',
        error: error,
        stackTrace: stackTrace,
      );
    } catch (_) {}
  }
}
