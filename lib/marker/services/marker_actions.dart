import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/messages/marker_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/models/marker_palette.dart';
import 'package:otzaria/marker/repository/marker_repository.dart';
import 'package:otzaria/marker/services/marker_settings.dart';
import 'package:otzaria/plugins/models/plugin_reader_selection.dart';
import 'package:otzaria/marker/models/marker_query.dart';
import 'package:otzaria/marker/services/marker_transfer.dart';

/// פעולות המשתמש על סימונים, משותפות לקורא ולמסך המרקר. כל פעולה מדווחת
/// בעצמה על הצלחה או כשל, ולכן הקוראים לה אינם צריכים לטפל בשגיאות.
class MarkerActions {
  MarkerActions({MarkerRepository? repository, MarkerSettings? settings})
    : _repository = repository ?? MarkerRepository(),
      _settingsSource = settings;

  static final MarkerActions instance = MarkerActions();

  final MarkerRepository _repository;
  final MarkerSettings? _settingsSource;

  MarkerSettings get _settings => _settingsSource ?? MarkerSettings.instance;

  // ===== קריאות ושמירות שהמסך מטפל בתוצאה שלהן בעצמו =====
  // אלה זורקות שגיאה במקום להציג הודעה: למשל הערה שהשתנתה בחלון אחר
  // מציגה שאלה, ולא "השמירה נכשלה".

  /// כל הסימונים שמתאימים ל-[query], בסדר הרשימה — להדפסה ולייצוא.
  Future<List<MarkerHighlight>> matching(
    MarkerQuery query, {
    List<String> colorOrder = const [],
  }) => _repository.query(
    query,
    offset: 0,
    limit: MarkerTransfer.maxRecords,
    colorOrder: colorOrder,
  );

  Future<List<({String tag, int count})>> tags() => _repository.tags();

  /// מחליף את התגית [from] ב-[to] בכל הסימונים; [to] ריק מוחק אותה.
  Future<int> replaceTag(String from, String? to) =>
      _repository.replaceTag(from, to);

  /// שומר את ההערה, או מוחק אותה כש-[note] ריק. זורק
  /// [MarkerConflictException] כשהסימון השתנה מאז [expectedVersion].
  Future<MarkerHighlight?> writeNote(
    String id,
    MarkerNote? note, {
    int? expectedVersion,
  }) => _repository.setNote(id, note, expectedVersion: expectedVersion);

  /// מסמן את [draft]; null פירושו שהבחירה לא עוגנה.
  Future<MarkerHighlight?> mark(MarkerDraft? draft, MarkerColor color) async {
    if (draft == null) {
      UiSnack.showError(MarkerMessages.cannotAnchor);
      return null;
    }
    if (_tooLong(draft.segments)) {
      UiSnack.showError(MarkerMessages.tooLong);
      return null;
    }
    try {
      final result = await _repository.create(draft, color);
      if (_settings.isBookHidden(draft.bookTitle, pdf: draft.pdf)) {
        await _settings.setBookHidden(draft.bookTitle, false, pdf: draft.pdf);
      }
      if (!_settings.showHighlights) {
        UiSnack.show(MarkerMessages.markedWhileHidden(color.label));
        return result.highlight;
      }
      switch (result.outcome) {
        case MarkerCreateOutcome.created:
          UiSnack.showQuick(MarkerMessages.marked(color.label));
        case MarkerCreateOutcome.recolored:
          UiSnack.showQuick(MarkerMessages.recolored(color.label));
        case MarkerCreateOutcome.repaired:
          UiSnack.showQuick(MarkerMessages.repaired);
        case MarkerCreateOutcome.unchanged:
          UiSnack.showQuick(MarkerMessages.alreadyMarked);
      }
      return result.highlight;
    } catch (error, stackTrace) {
      _reportFailure('mark', error, stackTrace);
      return null;
    }
  }

  /// מוחק ומציע לבטל את המחיקה.
  Future<void> remove(Iterable<String> ids) async {
    try {
      final removed = await _repository.delete(ids);
      if (removed.isEmpty) {
        UiSnack.show(MarkerMessages.deletedElsewhere);
        return;
      }
      UiSnack.showWithAction(
        message: MarkerMessages.removed(removed.length),
        actionLabel: MarkerMessages.undo,
        duration: const Duration(seconds: 30),
        onAction: () => _restore(removed),
      );
    } catch (error, stackTrace) {
      _reportFailure('remove', error, stackTrace, MarkerMessages.removeFailed);
    }
  }

  Future<void> _restore(List<MarkerHighlight> removed) async {
    try {
      await _repository.restore(removed);
      UiSnack.showQuick(MarkerMessages.restored);
    } catch (error, stackTrace) {
      _reportFailure(
        'restore',
        error,
        stackTrace,
        MarkerMessages.restoreFailed,
      );
    }
  }

  Future<void> recolor(Iterable<String> ids, MarkerColor color) async {
    try {
      final updated = await _repository.setColor(ids, color);
      if (updated.isNotEmpty) {
        UiSnack.showQuick(
          MarkerMessages.colorChanged(updated.length, color.label),
        );
      }
    } catch (error, stackTrace) {
      _reportFailure('recolor', error, stackTrace);
    }
  }

  Future<void> setFavorite(Iterable<String> ids, bool favorite) async {
    try {
      await _repository.setFavorite(ids, favorite);
    } catch (error, stackTrace) {
      _reportFailure('favorite', error, stackTrace);
    }
  }

  Future<void> setTags(String id, List<String> tags) async {
    try {
      final updated = await _repository.setTags(id, tags);
      if (updated.isNotEmpty) UiSnack.showQuick(MarkerMessages.tagsSaved);
    } catch (error, stackTrace) {
      _reportFailure('tags', error, stackTrace);
    }
  }

  Future<void> addTags(Iterable<String> ids, List<String> tags) async {
    try {
      final updated = await _repository.addTags(ids, tags);
      if (updated.isNotEmpty) {
        UiSnack.showQuick(MarkerMessages.tagsAdded(updated.length));
      }
    } catch (error, stackTrace) {
      _reportFailure('tags', error, stackTrace);
    }
  }

  /// שומר גבולות חדשים ל-[mark], אם לא השתנה בינתיים בחלון אחר.
  Future<bool> setRange(
    MarkerHighlight mark,
    List<MarkerSegment> segments,
    String text,
  ) async {
    if (_tooLong(segments)) {
      UiSnack.showError(MarkerMessages.tooLong);
      return false;
    }
    try {
      final saved = await _repository.setRange(
        mark.id,
        segments,
        text,
        expectedVersion: mark.version,
      );
      if (saved == null) {
        UiSnack.show(MarkerMessages.deletedElsewhere);
        return false;
      }
      UiSnack.showQuick(MarkerMessages.rangeSaved);
      return true;
    } on MarkerConflictException {
      UiSnack.show(MarkerMessages.changedElsewhere);
      return false;
    } catch (error, stackTrace) {
      _reportFailure('range', error, stackTrace);
      return false;
    }
  }

  /// מעביר את [mark] לטקסט של [draft] — הבחירה הנוכחית בספר — עם ההערה,
  /// הצבע והתגיות שלו. אפשר לבטל את ההעברה מההודעה.
  Future<bool> relocate(MarkerHighlight mark, MarkerDraft? draft) async {
    if (draft == null) {
      UiSnack.showError(MarkerMessages.cannotAnchor);
      return false;
    }
    if (draft.bookTitle != mark.bookTitle || draft.pdf != mark.pdf) {
      UiSnack.showError(MarkerMessages.moveOtherBook);
      return false;
    }
    final segments = [...draft.segments]
      ..sort((a, b) => a.sectionIndex.compareTo(b.sectionIndex));
    if (_tooLong(segments)) {
      UiSnack.showError(MarkerMessages.tooLong);
      return false;
    }
    try {
      final saved = await _repository.setRange(
        mark.id,
        segments,
        draft.text,
        expectedVersion: mark.version,
        moveTo: (ref: draft.ref),
      );
      if (saved == null) {
        UiSnack.show(MarkerMessages.deletedElsewhere);
        return false;
      }
      UiSnack.showWithAction(
        message: MarkerMessages.moved,
        actionLabel: MarkerMessages.undo,
        duration: const Duration(seconds: 15),
        onAction: () async {
          try {
            await _repository.setRange(
              mark.id,
              mark.segments,
              mark.text,
              expectedVersion: saved.version,
              moveTo: (ref: mark.ref),
            );
          } on MarkerConflictException {
            UiSnack.show(MarkerMessages.changedElsewhere);
          } catch (error, stackTrace) {
            _reportFailure('undo move', error, stackTrace);
          }
        },
      );
      return true;
    } on MarkerConflictException {
      UiSnack.show(MarkerMessages.changedElsewhere);
      return false;
    } catch (error, stackTrace) {
      _reportFailure('move', error, stackTrace);
      return false;
    }
  }

  /// עוגן ארוך מהמותר נשמר, אבל אינו נקרא בחזרה מהמסד.
  static bool _tooLong(List<MarkerSegment> segments) => segments.any(
    (segment) =>
        segment.end - segment.start >
        PluginTextRangeAnchor.maxExactTextGraphemes,
  );

  /// מסתיר או מציג את הסימונים בספר. כשהתצוגה כבויה בהגדרות, מדליק אותה.
  Future<void> toggleBookVisible(String bookTitle, {bool pdf = false}) async {
    if (!_settings.showHighlights) {
      await _settings.setBookHidden(bookTitle, false, pdf: pdf);
      await _settings.setShowHighlights(true);
      UiSnack.show(MarkerMessages.highlightsTurnedOn);
      return;
    }
    final hide = !_settings.isBookHidden(bookTitle, pdf: pdf);
    await _settings.setBookHidden(bookTitle, hide, pdf: pdf);
    UiSnack.show(hide ? MarkerMessages.bookHidden : MarkerMessages.bookShown);
  }

  /// הטקסט, מראה המקום וההערה, כמו בהעתקת ציטוט.
  static String citationOf(MarkerHighlight mark) {
    final place = [mark.bookTitle, ?mark.ref].where((s) => s.isNotEmpty);
    return [
      mark.text,
      '(${place.join(' · ')})',
      if (mark.hasNote) mark.note!.plain.trim(),
    ].join('\n');
  }

  Future<void> copy(MarkerHighlight mark) async {
    await Clipboard.setData(ClipboardData(text: citationOf(mark)));
    UiSnack.showQuick(MarkerMessages.copied);
  }

  void _reportFailure(
    String action,
    Object error,
    StackTrace stackTrace, [
    String message = MarkerMessages.saveFailed,
  ]) {
    debugPrint('Marker $action failed: $error');
    debugPrintStack(stackTrace: stackTrace, maxFrames: 8);
    UiSnack.showError(message);
  }
}
