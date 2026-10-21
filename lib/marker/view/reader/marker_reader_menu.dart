import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/marker/models/marker_book_uid.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/models/marker_palette.dart';
import 'package:otzaria/marker/repository/marker_repository.dart';
import 'package:otzaria/marker/services/marker_actions.dart';
import 'package:otzaria/marker/services/marker_book_cache.dart';
import 'package:otzaria/marker/services/marker_selection.dart';
import 'package:otzaria/marker/services/marker_settings.dart';
import 'package:otzaria/marker/view/marker_navigation.dart';
import 'package:otzaria/marker/view/widgets/marker_dialogs.dart';
import 'package:otzaria/marker/view/widgets/marker_range_editor.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/utils/highlight_click_resolver.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reader_plugin_menu_entries.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// פריטי המרקר בתפריט של הטקסט הראשי: צבעים ומחק לבחירה, או פעולות על סימון
/// שנלחץ. [context] של מסך הקורא, לדיאלוגים שנפתחים אחרי שהתפריט נסגר.
List<AppContextMenuEntry> buildMarkerMenuEntries({
  required BuildContext context,
  required RenderObject? root,
  required TextBookLoaded state,
  required List<String> lines,
  required int paragraphIndex,
  required String? selectedText,
  required ReaderSelectionAnchor anchor,
  required RenderSettings Function() settings,
  required Offset tapPosition,
  TextRange? lineRange,
  VoidCallback? openNotes,
}) => _markerEntries(
  context: context,
  root: root,
  book: state.book,
  uid: markerBookUidOf(state.book),
  ref: state.currentTitle,
  protection: state.protection,
  lines: lines,
  paragraphIndex: paragraphIndex,
  selectedText: selectedText,
  anchor: anchor,
  settings: settings,
  tapPosition: tapPosition,
  lineRange: lineRange,
  openNotes: openNotes,
);

/// פריטי המרקר בתפריט של מפרש — בטור של צורת הדף או ברשימת המפרשים.
/// [book] הוא ספר המפרש ו-[lines] שורותיו. ההגנה על המפרש נטענת רק בסימון.
List<AppContextMenuEntry> buildCommentaryMarkerEntries({
  required BuildContext context,
  required RenderObject? root,
  required TextBook book,
  required String? ref,
  required Future<BookProtection> Function() protection,
  required List<String> lines,
  required int paragraphIndex,
  required String? selectedText,
  required ReaderSelectionAnchor anchor,
  required RenderSettings Function() settings,
  required Offset tapPosition,
  TextRange? lineRange,
}) {
  return _markerEntries(
    context: context,
    root: root,
    book: book,
    uid: markerCommentaryUid(book),
    ref: ref,
    loadProtection: protection,
    lines: lines,
    paragraphIndex: paragraphIndex,
    selectedText: selectedText,
    anchor: anchor,
    settings: settings,
    tapPosition: tapPosition,
    lineRange: lineRange,
    commentary: true,
  );
}

/// המזהה היציב של מפרש. ספר שנבנה מקישור בלי book_id חסר את נתיב הקטגוריה
/// שהמזהה נגזר ממנו, ולכן הסימון נשמר לפי הכותרת בלבד.
String? markerCommentaryUid(TextBook book) =>
    book.id == null ? null : markerBookUidOf(book);

List<AppContextMenuEntry> _markerEntries({
  required BuildContext context,
  required RenderObject? root,
  required TextBook book,
  required String? uid,
  required String? ref,
  BookProtection? protection,
  Future<BookProtection> Function()? loadProtection,
  required List<String> lines,
  required int paragraphIndex,
  required String? selectedText,
  required ReaderSelectionAnchor anchor,
  required RenderSettings Function() settings,
  required Offset tapPosition,
  TextRange? lineRange,
  VoidCallback? openNotes,
  bool commentary = false,
}) {
  final markerSettings = MarkerSettings.instance;
  if (paragraphIndex < 0 ||
      paragraphIndex >= lines.length ||
      lines[paragraphIndex].isEmpty) {
    return const [];
  }
  final palette = markerSettings.palette;

  if (selectedText != null && selectedText.trim().isNotEmpty) {
    // ההגדרה מסתירה רק את הסימון מהבחירה; פעולות על סימון קיים נשארות.
    if (!(commentary
        ? markerSettings.showInCommentaryMenu
        : markerSettings.showInContextMenu)) {
      return const [];
    }
    final renderSettings = settings();
    MarkerDraft? draftWith(BookProtection protection) => markerDraftFor(
      book: book,
      bookUid: uid,
      protection: protection,
      ref: ref,
      lines: lines,
      paragraphIndex: paragraphIndex,
      selectedText: selectedText,
      anchor: anchor,
      settings: renderSettings,
    );
    // הטיוטה מראש רק למחק, ורק כשיש סימון בשורות שנבחרו; הסימון עצמו נבנה
    // בלחיצה. כשההגנה עוד לא ידועה, הוא נבנה מחדש אחרי שנטענה.
    final first = anchor.lineStart ?? paragraphIndex;
    final last = anchor.lineEnd ?? first;
    final marksHere = (MarkerBookCache.instance.marksOf(book.title, uid) ?? [])
        .any(
          (mark) => mark.segments.any(
            (s) => s.sectionIndex >= first && s.sectionIndex <= last,
          ),
        );
    final draft = marksHere
        ? draftWith(protection ?? BookProtection.none)
        : null;
    Future<MarkerDraft?> draftForMark() async => loadProtection != null
        ? draftWith(await loadProtection())
        : draft ?? draftWith(protection ?? BookProtection.none);
    final touched = draft == null
        ? const <String>{}
        : _visibleMarksUnder(
            book.title,
            uid,
            draft.segments,
            Theme.of(context).brightness,
          );
    return [
      AppContextMenuEntry.colorRow([
        for (final color in palette.menuColors)
          AppContextMenuColorAction(
            id: color.id,
            color: Color(color.argb),
            label: 'סימון ב${color.label}',
            onTap: () async =>
                MarkerActions.instance.mark(await draftForMark(), color),
          ),
        if (touched.isNotEmpty)
          AppContextMenuColorAction(
            id: 'marker-erase',
            color: const Color(0x00000000),
            label: touched.length == 1
                ? 'מחיקת הסימון'
                : 'מחיקת ${touched.length} הסימונים',
            icon: FluentIcons.eraser_24_regular,
            onTap: () => MarkerActions.instance.remove(touched),
          ),
        ?markerNoteColorAction(
          context,
          touched,
          MarkerBookCache.instance.marksOf(book.title, uid) ?? const [],
          openNotes: openNotes,
        ),
      ]),
    ];
  }

  if (root == null) return const [];
  // הטקסט כפי שהקורא מציג אותו: שמות קודש, ניקוד וטעמים לפי ההגדרות.
  String display(String source) => TextRendererService.stripHtml(
    TextRendererService.processText(source, settings()),
  );
  // שורה שעוד לא נטענה ריקה ברשימה החלקית; בלי הטקסט שלה אין מה להציג.
  String? source(int section) =>
      section < lines.length && lines[section].isNotEmpty
      ? TextRendererService.stripHtml(lines[section])
      : null;
  final pieces = MarkerBookCache.instance.paint(
    bookTitle: book.title,
    bookUid: uid,
    sectionIndex: paragraphIndex,
    brightness: Theme.of(context).brightness,
  );
  if (pieces.isEmpty) return const [];
  final clickedIds = {
    for (final piece in resolveClickedHighlights(
      root: root,
      globalPosition: tapPosition,
      bookId: book.title,
      bookUid: uid,
      sectionIndex: paragraphIndex,
      rawText: lines[paragraphIndex],
      settings: settings(),
      lineRange: lineRange,
      highlights: pieces,
    ))
      piece.highlightId,
  };
  if (clickedIds.isEmpty) return const [];
  final clicked = [
    for (final mark in MarkerBookCache.instance.marksInSection(
      bookTitle: book.title,
      bookUid: uid,
      sectionIndex: paragraphIndex,
    ))
      if (clickedIds.contains(mark.id)) mark,
  ];
  if (clicked.isEmpty) return const [];
  if (clicked.length == 1) {
    return [
      AppContextMenuEntry(
        label: 'סימון',
        icon: FluentIcons.highlight_24_regular,
        childrenBuilder: () => markerActionEntries(
          context,
          clicked.single,
          palette,
          source,
          display: display,
          openNotes: openNotes,
        ),
      ),
    ];
  }
  return [
    AppContextMenuEntry(
      label: 'סימונים',
      icon: FluentIcons.highlight_24_regular,
      childrenBuilder: () => [
        for (final mark in clicked)
          AppContextMenuEntry(
            label: markerQuote(mark.text, 30),
            childrenBuilder: () => markerActionEntries(
              context,
              mark,
              palette,
              source,
              display: display,
              openNotes: openNotes,
            ),
          ),
      ],
    ),
  ];
}

/// הסימונים שנראים מתחת לבחירה. סימון שמוסתר כולו תחת סימון חדש יותר, או
/// שאינו מצויר כלל, אינו נמחק בלי שהמשתמש ראה אותו.
Set<String> _visibleMarksUnder(
  String bookTitle,
  String? bookUid,
  List<MarkerSegment> segments,
  Brightness brightness,
) => {
  for (final segment in segments)
    for (final piece in MarkerBookCache.instance.paint(
      bookTitle: bookTitle,
      bookUid: bookUid,
      sectionIndex: segment.sectionIndex,
      brightness: brightness,
    ))
      if (piece.range.start.grapheme < segment.end &&
          segment.start < piece.range.end.grapheme)
        piece.highlightId,
};

/// כפתור ההערה בשורת הצבעים, כשהבחירה נמצאת על סימון אחד: הוספת הערה
/// לסימון או עריכתה, בלי לחפש את הסימון בתפריט. [marks] — הסימונים בספר.
AppContextMenuColorAction? markerNoteColorAction(
  BuildContext context,
  Set<String> touched,
  List<MarkerHighlight> marks, {
  VoidCallback? openNotes,
}) {
  if (touched.length != 1) return null;
  final id = touched.single;
  final mark = marks.where((mark) => mark.id == id).firstOrNull;
  if (mark == null) return null;
  return AppContextMenuColorAction(
    id: 'marker-note',
    color: const Color(0x00000000),
    label: mark.hasNote ? 'עריכת הערה' : 'הוספת הערה',
    icon: mark.hasNote
        ? FluentIcons.note_edit_24_regular
        : FluentIcons.note_add_24_regular,
    onTap: () => editMarkerNote(context, mark, openNotes: openNotes),
  );
}

/// הפעולות על סימון שנלחץ. [source] — טקסט המקור של פסקה או עמוד, להתאמת
/// הגבולות; null כשהוא עוד לא ידוע. [openNotes] — פותח את חלונית ההערות,
/// כדי שההערה תיערך בה ולא בחלון קופץ.
List<AppContextMenuEntry> markerActionEntries(
  BuildContext context,
  MarkerHighlight mark,
  MarkerPalette palette,
  String? Function(int section) source, {
  String Function(String source)? display,
  VoidCallback? openNotes,
}) {
  final actions = MarkerActions.instance;
  final firstSource = source(mark.segments.first.sectionIndex);
  final lastSource = source(mark.segments.last.sectionIndex);
  return [
    AppContextMenuEntry.colorRow([
      for (final color in palette.menuColors)
        AppContextMenuColorAction(
          id: color.id,
          color: Color(color.argb),
          label: color.label,
          selected: color.id == mark.colorId,
          onTap: () => actions.recolor([mark.id], color),
        ),
    ]),
    AppContextMenuEntry(
      label: mark.hasNote ? 'עריכת הערה' : 'הוספת הערה',
      icon: mark.hasNote
          ? FluentIcons.note_edit_24_regular
          : FluentIcons.note_add_24_regular,
      onTap: () => editMarkerNote(context, mark, openNotes: openNotes),
    ),
    if (mark.hasNote)
      AppContextMenuEntry(
        label: 'מחיקת ההערה',
        icon: FluentIcons.delete_24_regular,
        onTap: () => deleteMarkerNote(context, mark),
      ),
    if (firstSource != null && lastSource != null)
      AppContextMenuEntry(
        label: 'שינוי המיקום…',
        icon: FluentIcons.arrow_autofit_width_24_regular,
        onTap: () => editMarkerRange(
          context,
          mark,
          firstSource: firstSource,
          lastSource: lastSource,
          display: display ?? (text) => text,
        ),
      ),
    AppContextMenuEntry(
      label: 'תגיות…',
      icon: FluentIcons.tag_24_regular,
      onTap: () => editMarkerTags(context, mark),
    ),
    AppContextMenuEntry(
      label: mark.favorite ? 'הסרה מהמועדפים' : 'הוספה למועדפים',
      icon: mark.favorite
          ? FluentIcons.star_off_24_regular
          : FluentIcons.star_24_regular,
      onTap: () => actions.setFavorite([mark.id], !mark.favorite),
    ),
    AppContextMenuEntry(
      label: 'העתקה עם מראה מקום',
      icon: FluentIcons.copy_24_regular,
      onTap: () => actions.copy(mark),
    ),
    AppContextMenuEntry(
      label: 'הצגה ברשימת המרקר',
      icon: OtzariaIcons.text_bullet_list_24_regular,
      onTap: () => openMarkerList(context, focus: mark),
    ),
    const AppContextMenuEntry.divider(),
    AppContextMenuEntry(
      label: 'מחיקת הסימון',
      icon: FluentIcons.eraser_24_regular,
      isDestructive: true,
      onTap: () => actions.remove([mark.id]),
    ),
  ];
}
