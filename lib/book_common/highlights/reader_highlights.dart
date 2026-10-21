import 'package:flutter/widgets.dart';
import 'package:otzaria/marker/legacy/legacy_marker_plugin.dart';
import 'package:otzaria/marker/models/marker_book_uid.dart';
import 'package:otzaria/marker/services/marker_book_cache.dart';
import 'package:otzaria/plugins/models/plugin_highlight.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';

/// כל ההדגשות שהקורא מצייר: של התוספים ושל המרקר. נקודת הקריאה היחידה של
/// מסלולי הציור, כדי ששני המקורות יצוירו באותו renderer בנפרד.
abstract final class ReaderHighlights {
  /// מודיע על שינוי בהדגשות של [bookTitle] או בהדגשות התוספים. [plugins]
  /// false — במפרש, שבו מצוירים רק סימוני המרקר.
  static Listenable listenable(String bookTitle, {bool plugins = true}) =>
      plugins
      ? Listenable.merge([
          PluginHighlightRegistry.instance,
          MarkerBookCache.instance.listenable(bookTitle),
        ])
      : MarkerBookCache.instance.listenable(bookTitle);

  /// עולה בכל שינוי בכל מקור — לשער הסנכרון של הפסקאות.
  static int get revision =>
      PluginHighlightRegistry.instance.revision +
      MarkerBookCache.instance.revision;

  /// [bookVersion] — שם המהדורה החלופית, שמפרידה את סימוני המרקר שלה.
  static List<PluginHighlight> forSection({
    required String bookTitle,
    String? bookUid,
    String? bookVersion,
    required int sectionIndex,
    required Brightness brightness,
    bool plugins = true,
  }) {
    final plugin = plugins
        ? pluginHighlights(
            bookTitle: bookTitle,
            bookUid: bookUid,
            bookVersion: bookVersion,
            sectionIndex: sectionIndex,
          )
        : const <PluginHighlight>[];
    final marker = MarkerBookCache.instance.paint(
      bookTitle: bookTitle,
      bookUid: _markerUid(bookUid, bookVersion),
      sectionIndex: sectionIndex,
      brightness: brightness,
    );
    if (plugin.isEmpty) return marker;
    return marker.isEmpty ? plugin : [...marker, ...plugin];
  }

  /// הדגשות התוספים בפסקה. הדגשה של התוסף הישן שיובאה שייכת למרקר: היא
  /// מצוירת ונלחצת ממנו בלבד, גם כשהתוסף עדיין פעיל.
  static List<PluginHighlight> pluginHighlights({
    required String bookTitle,
    String? bookUid,
    String? bookVersion,
    required int sectionIndex,
  }) {
    final plugin = PluginHighlightRegistry.instance.getAllHighlights(
      bookId: bookTitle,
      sectionIndex: sectionIndex,
      bookUid: bookUid,
    );
    if (plugin.isEmpty) return plugin;
    final imported = MarkerBookCache.instance.legacyIds();
    if (imported.isEmpty) return plugin;
    return [
      for (final highlight in plugin)
        if (highlight.ownerPluginId != kLegacyMarkerPluginId ||
            !imported.contains(highlight.highlightId))
          highlight,
    ];
  }

  static void reanchorSection({
    required String bookTitle,
    String? bookUid,
    String? bookVersion,
    required int sectionIndex,
    required String sourceText,
  }) {
    PluginHighlightRegistry.instance.reanchorSection(
      bookId: bookTitle,
      sectionIndex: sectionIndex,
      sourceText: sourceText,
      bookUid: bookUid,
    );
    MarkerBookCache.instance.reanchorSection(
      bookTitle: bookTitle,
      bookUid: _markerUid(bookUid, bookVersion),
      sectionIndex: sectionIndex,
      sourceText: sourceText,
    );
  }

  /// עיגון מחדש של סימוני המרקר בלבד, לשורה של מפרש. שורה בלי סימון אינה
  /// עולה דבר; האירועים לתוספים שייכים לטקסט הראשי בלבד.
  static void reanchorMarkerSection({
    required String bookTitle,
    String? bookUid,
    String? bookVersion,
    required int sectionIndex,
    required String Function() sourceText,
  }) {
    final uid = _markerUid(bookUid, bookVersion);
    final cache = MarkerBookCache.instance;
    if (cache
        .marksInSection(
          bookTitle: bookTitle,
          bookUid: uid,
          sectionIndex: sectionIndex,
        )
        .isEmpty) {
      return;
    }
    final text = sourceText();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => cache.reanchorSection(
        bookTitle: bookTitle,
        bookUid: uid,
        sectionIndex: sectionIndex,
        sourceText: text,
      ),
    );
  }

  static String? _markerUid(String? bookUid, String? bookVersion) =>
      bookUid == null ? null : markerBookUid(bookUid, bookVersion);
}
