import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/marker_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/marker/models/marker_book_uid.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/models/marker_palette.dart';
import 'package:otzaria/marker/repository/marker_repository.dart';
import 'package:otzaria/marker/services/marker_actions.dart';
import 'package:otzaria/marker/services/marker_book_cache.dart';
import 'package:otzaria/marker/services/marker_note_requests.dart';
import 'package:otzaria/marker/services/marker_settings.dart';
import 'package:otzaria/marker/storage/marker_search_text.dart';
import 'package:otzaria/marker/view/pdf/marker_pdf.dart';
import 'package:otzaria/marker/view/reader/marker_reader_menu.dart';
import 'package:otzaria/marker/view/reader/marker_reader_selection.dart';
import 'package:otzaria/marker/view/widgets/marker_dialogs.dart';
import 'package:otzaria/marker/view/widgets/marker_marked_text.dart';
import 'package:otzaria/marker/view/widgets/marker_note_view.dart';
import 'package:otzaria/marker/view/widgets/marker_range_editor.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';
import 'package:otzaria/personal_notes/widgets/inline_note_editor.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/selection/keyboard_selection_settings.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

/// ההערות שנכתבו על סימוני המרקר בספר, בראש חלונית ההערות. כשהחלונית
/// מציגה רק את מה שבמסך, גם כאן מוצגים רק סימונים בטקסט הנראה. כשהסימונים
/// מוסתרים בכל הספרים, גם ההערות עליהם מוסתרות.
class MarkerNotesSection extends StatelessWidget {
  final Book book;

  /// ספר PDF: המקטע הוא עמוד, ואין סינון לפי הטקסט שבמסך.
  final bool pdf;

  /// [section] — הפסקה (מ-0) או העמוד (מ-1) שבו הסימון מתחיל.
  final void Function(int section) onNavigate;

  /// הבקר של צופה ה-PDF, לבחירה ולטקסט העמודים.
  final MarkerPdfController? Function()? pdfController;

  /// מפרש שמוצג לצד הספר: הסימונים נשמרים בו לפי [markerCommentaryUid], אין
  /// סינון לפי השורות שבמסך של הספר, ומיקום הסימון משתנה מטקסט המפרש שבקובץ.
  final bool commentary;

  const MarkerNotesSection({
    super.key,
    required this.book,
    required this.onNavigate,
    this.pdf = false,
    this.pdfController,
    this.commentary = false,
  });

  @override
  Widget build(BuildContext context) {
    final cache = MarkerBookCache.instance;
    final book = this.book;
    final uid = commentary && book is TextBook
        ? markerCommentaryUid(book)
        : markerBookUidOf(book);
    return ListenableBuilder(
      listenable: Listenable.merge([
        cache.contentListenable(book.title),
        MarkerSettings.instance,
        MarkerNoteRequests.editing,
      ]),
      builder: (context, _) {
        if (!MarkerSettings.instance.showHighlights) {
          return const SizedBox.shrink();
        }
        final marks =
            cache.marksOf(book.title, uid, pdf: pdf) ??
            const <MarkerHighlight>[];
        // סימון שההערה שלו נערכת מוצג גם לפני שיש לו הערה, וגם כשהסינון היה
        // מסתיר אותו.
        final pinned = MarkerNoteRequests.editing.value;
        final withNotes = [
          for (final mark in marks)
            if (mark.hasNote || pinned.contains(mark.id)) mark,
        ];
        if (withNotes.isEmpty) return const SizedBox.shrink();
        return BlocSelector<
          PersonalNotesBloc,
          PersonalNotesState,
          ({bool onlyVisible, String search})
        >(
          selector: (state) =>
              (onlyVisible: state.showOnlyVisible, search: state.searchQuery),
          builder: (context, view) {
            Widget section(List<int> visible) {
              final shown = _filter(
                withNotes,
                view.onlyVisible,
                visible,
                view.search,
                pinned,
              );
              if (shown.isEmpty) return const SizedBox.shrink();
              return _Section(
                marks: shown,
                onNavigate: onNavigate,
                location: MarkerNoteLocation(
                  pdf: pdf,
                  pdfController: pdfController,
                  commentary: commentary,
                ),
              );
            }

            if (pdf || commentary) return section(const []);
            // רשימה חדשה בכל גלילה; בונים מחדש רק כשהשורות עצמן השתנו. אותו
            // עץ גם כשהסינון כבוי, כדי שעורך פתוח לא ייסגר בהחלפה.
            return BlocBuilder<TextBookBloc, TextBookState>(
              buildWhen: (previous, current) =>
                  !listEquals(_visible(previous), _visible(current)),
              builder: (context, state) =>
                  section(view.onlyVisible ? _visible(state) : const []),
            );
          },
        );
      },
    );
  }

  static List<int> _visible(TextBookState state) =>
      state is TextBookLoaded ? state.visibleIndices : const [];

  static List<MarkerHighlight> _filter(
    List<MarkerHighlight> marks,
    bool onlyVisible,
    List<int> visible,
    String search,
    Set<String> pinned,
  ) {
    final lines = visible.toSet();
    // אותו חיפוש של חלונית ההערות, על ההערה ועל הטקסט המסומן.
    final terms = normalizeMarkerSearchText(search).split(' ')
      ..removeWhere((term) => term.isEmpty);
    bool matches(MarkerHighlight mark) {
      if (terms.isEmpty) return true;
      final text = normalizeMarkerSearchText(
        '${mark.text} ${mark.note?.plain ?? ''}',
      );
      return terms.every(text.contains);
    }

    return [
      for (final mark in marks)
        if (pinned.contains(mark.id) ||
            ((!onlyVisible ||
                    lines.isEmpty ||
                    mark.segments.any((s) => lines.contains(s.sectionIndex))) &&
                matches(mark)))
          mark,
    ]..sort(_byPlace);
  }
}

/// לפי המקום בספר: המקטע, ובתוכו תחילת הסימון.
int _byPlace(MarkerHighlight a, MarkerHighlight b) {
  final section = a.sectionStart.compareTo(b.sectionStart);
  return section != 0
      ? section
      : a.segments.first.start.compareTo(b.segments.first.start);
}

/// ההערות על סימונים במפרשים שמוצגים לצד הספר, כשורות באזור ההערות על
/// המפרשים — כמו ההערות האישיות שם. [builder] מקבל את השורות לפי שם המפרש;
/// לחיצה על שורה מעבירה את החלונית להערות המפרש, ושם אפשר לערוך אותן.
class MarkerCommentaryNoteTiles extends StatelessWidget {
  final List<TextBook> commentaries;
  final void Function(TextBook commentary, int section) onNavigate;
  final Widget Function(BuildContext context, Map<String, List<Widget>> tiles)
  builder;

  const MarkerCommentaryNoteTiles({
    super.key,
    required this.commentaries,
    required this.onNavigate,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final cache = MarkerBookCache.instance;
    final settings = MarkerSettings.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([
        for (final commentary in commentaries)
          cache.contentListenable(commentary.title),
        settings,
      ]),
      builder: (context, _) {
        final tiles = <String, List<Widget>>{};
        if (settings.showHighlights) {
          for (final commentary in commentaries) {
            final marks = [
              for (final mark
                  in cache.marksOf(
                        commentary.title,
                        markerCommentaryUid(commentary),
                      ) ??
                      const <MarkerHighlight>[])
                if (mark.hasNote) mark,
            ]..sort(_byPlace);
            if (marks.isEmpty) continue;
            tiles[commentary.title] = [
              for (final mark in marks)
                _CommentaryNoteTile(
                  key: ValueKey(mark.id),
                  mark: mark,
                  color: Color(
                    settings.palette.colorById(mark.colorId)?.argb ??
                        MarkerColor.argbOf(mark.colorHex),
                  ),
                  onTap: () => onNavigate(commentary, mark.sectionStart),
                ),
            ];
          }
        }
        return builder(context, tiles);
      },
    );
  }
}

class _CommentaryNoteTile extends StatelessWidget {
  final MarkerHighlight mark;
  final Color color;
  final VoidCallback onTap;

  const _CommentaryNoteTile({
    super.key,
    required this.mark,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    minLeadingWidth: 0,
    horizontalTitleGap: 8,
    leading: Icon(FluentIcons.highlight_24_filled, size: 18, color: color),
    title: MarkerMarkedText(mark, maxLines: 1, maxChars: 80),
    subtitle: Text(
      mark.note?.plain ?? '',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    onTap: onTap,
  );
}

class _Section extends StatelessWidget {
  final List<MarkerHighlight> marks;
  final void Function(int section) onNavigate;
  final MarkerNoteLocation location;

  const _Section({
    required this.marks,
    required this.onNavigate,
    required this.location,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = MarkerSettings.instance.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Icon(
                FluentIcons.highlight_24_regular,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'הערות על סימונים',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
        ),
        for (final mark in marks)
          MarkerNoteCard(
            key: ValueKey(mark.id),
            mark: mark,
            palette: palette,
            onTap: () => onNavigate(mark.sectionStart),
            location: location,
          ),
        const Divider(height: 16),
      ],
    );
  }
}

/// איפה הסימון בספר הפתוח: הבחירה הנוכחית וטקסט המקור, להעברה ולהזזת
/// הגבולות מתוך החלונית.
class MarkerNoteLocation {
  final bool pdf;
  final MarkerPdfController? Function()? pdfController;

  /// מפרש לצד הספר: הבחירה שבספר אינה בו, והגבולות נערכים מטקסט הקובץ.
  final bool commentary;

  const MarkerNoteLocation({
    required this.pdf,
    required this.pdfController,
    this.commentary = false,
  });

  bool get canMoveToSelection => !commentary;

  /// הבחירה הנוכחית בספר, כטיוטת סימון. [selected] — אם יש בחירה בכלל;
  /// [draft] null עם בחירה פירושו שאי אפשר לעגן אותה.
  Future<({bool selected, MarkerDraft? draft})> selection(
    BuildContext context,
  ) async {
    if (pdf) {
      final controller = pdfController?.call();
      if (controller == null || !controller.hasSelection) {
        return (selected: false, draft: null);
      }
      return (selected: true, draft: await controller.selectionDraft());
    }
    final state = context.read<TextBookBloc>().state;
    final text = state is TextBookLoaded ? state.selectedTextForNote : null;
    if (state is! TextBookLoaded || text == null || text.trim().isEmpty) {
      return (selected: false, draft: null);
    }
    return (
      selected: true,
      draft: await markerReaderSelectionDraft(
        context: context,
        state: state,
        selectedText: text,
        lineIndex: state.selectedTextSectionIndex,
        column: state.selectedTextStart,
      ),
    );
  }

  /// עורך הגבולות של [mark], עם טקסט המקור של המקטע הראשון והאחרון.
  Future<void> editRange(BuildContext context, MarkerHighlight mark) async {
    if (commentary) return editMarkerRangeFromBook(context, mark);
    final first = mark.segments.first.sectionIndex;
    final last = mark.segments.last.sectionIndex;
    if (pdf) {
      final controller = pdfController?.call();
      final firstText = await controller?.pageText(first);
      final lastText = await controller?.pageText(last);
      if (!context.mounted) return;
      if (firstText == null || lastText == null) {
        UiSnack.show(MarkerMessages.rangeNeedsBook);
        return;
      }
      await editMarkerRange(
        context,
        mark,
        firstSource: firstText,
        lastSource: lastText,
      );
      return;
    }
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;
    final settings = keyboardSelectionRenderSettings(
      state,
      context.read<SettingsBloc>().state,
    );
    final lines = await markerSourceLines(context, state, first, last);
    if (!context.mounted) return;
    if (lines == null) {
      UiSnack.show(MarkerMessages.rangeNeedsBook);
      return;
    }
    await editMarkerRange(
      context,
      mark,
      firstSource: TextRendererService.stripHtml(lines.first),
      lastSource: TextRendererService.stripHtml(lines.last),
      display: (source) => TextRendererService.stripHtml(
        TextRendererService.processText(source, settings),
      ),
    );
  }
}

enum _CardAction { moveToSelection, editRange, deleteNote, deleteMark }

/// כרטיס של הערה על סימון. ההערה נערכת בכרטיס עצמו, כמו הערה אישית.
@visibleForTesting
class MarkerNoteCard extends StatefulWidget {
  final MarkerHighlight mark;
  final MarkerPalette palette;
  final VoidCallback onTap;
  final MarkerNoteLocation? location;

  const MarkerNoteCard({
    super.key,
    required this.mark,
    required this.palette,
    required this.onTap,
    this.location,
  });

  @override
  State<MarkerNoteCard> createState() => _MarkerNoteCardState();
}

class _MarkerNoteCardState extends State<MarkerNoteCard>
    implements MarkerNoteEditorHost {
  /// רוחב שמתחתיו הפעולות מתקבצות לתפריט אחד.
  static const double _minActionsWidth = 300;

  ({String content, PersonalNoteContentFormat format})? _editing;
  bool _loading = false;
  bool _saving = false;
  bool _active = true;
  DateTime? _revealed;
  final ValueNotifier<int> _cancelRequest = ValueNotifier(0);

  MarkerHighlight get _mark => widget.mark;

  @override
  bool get isActiveHost => mounted && _active;

  @override
  void initState() {
    super.initState();
    MarkerNoteRequests.changes.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // גם כשהכרטיסייה חוזרת להיות פעילה, או עוברת לרקע.
    _active = TickerMode.valuesOf(context).enabled;
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    MarkerNoteRequests.changes.removeListener(_sync);
    // כרטיס שנבנה במקומו — למשל כשהחלונית נפתחת — לוקח את העורך, והטיוטה
    // שהעורך שמר בפירוקו נטענת בו.
    MarkerNoteRequests.release(_mark.id, this);
    _cancelRequest.dispose();
    super.dispose();
  }

  /// מציג את העורך כשההערה נפתחה לעריכה והכרטיס הזה הוא שמציג אותה. כרטיס
  /// בכרטיסייה ברקע אינו לוקח את העורך מכרטיס פעיל, ומוותר עליו לכרטיס פעיל.
  void _sync() {
    if (!mounted || _saving) return;
    final id = _mark.id;
    final open = MarkerNoteRequests.editing.value.contains(id);
    if (open && _active) MarkerNoteRequests.claim(id, this);
    if (!open || !MarkerNoteRequests.isOwner(id, this)) {
      if (_editing != null) setState(() => _editing = null);
      return;
    }
    if (_editing == null) {
      if (!_loading) unawaited(_load());
      return;
    }
    _reveal();
  }

  Future<void> _load() async {
    _loading = true;
    try {
      final draft = await PersonalNoteDraftService().loadDraft(
        bookId: _mark.bookTitle,
        noteId: markerNoteDraftId(_mark),
      );
      if (!mounted || !MarkerNoteRequests.isOwner(_mark.id, this)) return;
      setState(
        () => _editing = (
          content: draft?.content ?? _mark.note?.content ?? '',
          format:
              draft?.contentFormat ??
              _mark.note?.format ??
              PersonalNoteContentFormat.plain,
        ),
      );
    } finally {
      _loading = false;
    }
    _reveal();
  }

  /// הכרטיס נגלל אל מול העין פעם אחת לכל בקשה לערוך, גם כשהחלונית רק נפתחה.
  /// רק רשימת ההערות נגללת: Scrollable.ensureVisible היה גולל גם את
  /// ה-PageView של הכרטיסיות, ומעביר לכרטיסייה הסמוכה.
  void _reveal() {
    final at = MarkerNoteRequests.openedAt(_mark.id);
    if (at == null ||
        at == _revealed ||
        DateTime.now().difference(at) > const Duration(seconds: 3)) {
      return;
    }
    _revealed = at;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final card = mounted ? context.findRenderObject() : null;
      if (card == null) return;
      Scrollable.maybeOf(context)?.position.ensureVisible(
        card,
        duration: const Duration(milliseconds: 200),
        alignment: 0.1,
      );
    });
  }

  void _edit() => MarkerNoteRequests.open(_mark.id);

  /// הכרטיס נשאר ברשימה עד שהשמירה מסתיימת — גם לסימון שעוד אין לו הערה —
  /// כדי ששאלה על שינוי שנעשה בחלון אחר תוכל להופיע עליו.
  Future<void> _save(PersonalNoteEditorResult result) async {
    final mark = _mark;
    _saving = true;
    if (mounted) setState(() => _editing = null);
    try {
      await saveMarkerNote(mounted ? context : null, mark, result);
    } finally {
      _saving = false;
      MarkerNoteRequests.close(mark.id);
    }
  }

  void _cancel() => MarkerNoteRequests.close(_mark.id);

  Future<void> _onAction(_CardAction action) async {
    final location = widget.location;
    switch (action) {
      case _CardAction.moveToSelection:
        if (location == null) return;
        final current = await location.selection(context);
        if (!current.selected) {
          UiSnack.show(MarkerMessages.moveNeedsSelection);
          return;
        }
        await MarkerActions.instance.relocate(_mark, current.draft);
      case _CardAction.editRange:
        if (location != null) await location.editRange(context, _mark);
      case _CardAction.deleteNote:
        await deleteMarkerNote(context, _mark);
      case _CardAction.deleteMark:
        await MarkerActions.instance.remove([_mark.id]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = _editing;
    if (editing != null) return _editor(editing);
    return LayoutBuilder(
      builder: (context, constraints) =>
          _card(context, compact: constraints.maxWidth < _minActionsWidth),
    );
  }

  Widget _editor(({String content, PersonalNoteContentFormat format}) value) =>
      InlineNoteEditorCard(
        icon: _mark.hasNote
            ? FluentIcons.note_edit_24_regular
            : FluentIcons.note_add_24_regular,
        title: _mark.hasNote ? 'עריכת הערה לסימון' : 'הערה חדשה לסימון',
        onCancelPressed: () => _cancelRequest.value++,
        editor: InlineNoteEditor(
          note: markerNoteAsPersonalNote(_mark),
          referenceText: markerQuote(_mark.text),
          bookId: _mark.bookTitle,
          initialContent: value.content,
          initialFormat: value.format,
          draftNoteId: markerNoteDraftId(_mark),
          linkableNotes: const [],
          cancelRequest: _cancelRequest,
          onSave: _save,
          onCancel: _cancel,
        ),
      );

  Widget _card(BuildContext context, {required bool compact}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = Color(
      widget.palette.colorById(_mark.colorId)?.argb ??
          MarkerColor.argbOf(_mark.colorHex),
    );
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: BorderDirectional(start: BorderSide(color: color, width: 5)),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(10, 4, 2, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: widget.onTap,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: MarkerMarkedText(
                          _mark,
                          maxChars: 80,
                          maxLines: 2,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                  ..._actions(compact),
                ],
              ),
              if (_mark.hasNote)
                InkWell(
                  onTap: widget.onTap,
                  child: CollapsibleMarkerNote(
                    child: MarkerNoteView(
                      mark: _mark,
                      textStyle: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(bool compact) {
    final palette = widget.palette;
    final colors = [
      for (final color in palette.menuColors)
        AppMenuEntry<Object>(
          value: color,
          label: color.label,
          icon: FluentIcons.circle_24_filled,
          iconColor: Color(color.argb),
        ),
    ];
    final location = [
      if (widget.location case final location?) ...[
        if (location.canMoveToSelection)
          const AppMenuEntry<Object>(
            value: _CardAction.moveToSelection,
            label: 'העברה לטקסט שנבחר בספר',
            icon: FluentIcons.pin_24_regular,
          ),
        const AppMenuEntry<Object>(
          value: _CardAction.editRange,
          label: 'הוספה או הסרה של מילים…',
          icon: FluentIcons.arrow_autofit_width_24_regular,
        ),
      ],
    ];
    const delete = [
      AppMenuEntry<Object>(
        value: _CardAction.deleteNote,
        label: 'מחיקת ההערה',
        icon: FluentIcons.delete_24_regular,
      ),
      AppMenuEntry<Object>(
        value: _CardAction.deleteMark,
        label: 'מחיקת הסימון וההערה',
        icon: FluentIcons.eraser_24_regular,
        isDestructive: true,
      ),
    ];
    void onSelected(Object value) => switch (value) {
      MarkerColor color => MarkerActions.instance.recolor([_mark.id], color),
      _CardAction action => _onAction(action),
      _ => null,
    };
    // הצבע הנוכחי מסומן בתפריט, כמו בבחירת הקיבוץ.
    final current = palette.colorById(_mark.colorId);
    // באותו גודל של כפתורי ההערות האישיות.
    const padding = EdgeInsets.all(8);
    const constraints = BoxConstraints(minWidth: 32, minHeight: 32);
    Widget menu(String tooltip, IconData icon, List<AppMenuEntry<Object>> e) =>
        AppPopupMenuButton<Object>(
          tooltip: tooltip,
          icon: Icon(icon, size: 18),
          padding: padding,
          constraints: constraints,
          initialValue: e.any((entry) => entry.value == current)
              ? current
              : null,
          entries: e,
          onSelected: onSelected,
        );
    final edit = IconButton(
      tooltip: _mark.hasNote ? 'עריכת הערה' : 'הוספת הערה',
      iconSize: 18,
      padding: padding,
      constraints: constraints,
      onPressed: _edit,
      icon: Icon(
        _mark.hasNote
            ? FluentIcons.note_edit_24_regular
            : FluentIcons.note_add_24_regular,
      ),
    );
    if (compact) {
      return [
        edit,
        menu('פעולות נוספות', FluentIcons.more_vertical_24_regular, [
          ...colors,
          ...location,
          ...delete,
        ]),
      ];
    }
    return [
      edit,
      menu('שינוי הצבע', FluentIcons.color_24_regular, colors),
      if (location.isNotEmpty)
        menu('שינוי המיקום', FluentIcons.location_24_regular, location),
      menu('מחיקה', FluentIcons.delete_24_regular, delete),
    ];
  }
}

/// הערה ארוכה מוצגת מקוצרת, עם כפתור להצגתה כולה.
@visibleForTesting
class CollapsibleMarkerNote extends StatefulWidget {
  /// הגובה המרבי של הערה מקוצרת.
  static const double collapsedHeight = 140;

  final Widget child;

  const CollapsibleMarkerNote({super.key, required this.child});

  @override
  State<CollapsibleMarkerNote> createState() => _CollapsibleMarkerNoteState();
}

class _CollapsibleMarkerNoteState extends State<CollapsibleMarkerNote> {
  final ScrollController _scroll = ScrollController();
  bool _expanded = false;
  bool _overflows = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted || _expanded || !_scroll.hasClients) return;
    final overflows = _scroll.position.maxScrollExtent > 0;
    if (overflows != _overflows) setState(() => _overflows = overflows);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toggle = TextButton.icon(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
      ),
      onPressed: () => setState(() => _expanded = !_expanded),
      icon: Icon(
        _expanded
            ? FluentIcons.chevron_up_24_regular
            : FluentIcons.chevron_down_24_regular,
        size: 16,
      ),
      label: Text(_expanded ? 'הצגה מקוצרת' : 'הצגת ההערה כולה'),
    );
    if (_expanded) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [widget.child, toggle],
      );
    }
    final clipped = NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
        return false;
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxHeight: CollapsibleMarkerNote.collapsedHeight,
        ),
        child: SingleChildScrollView(
          controller: _scroll,
          physics: const NeverScrollableScrollPhysics(),
          child: widget.child,
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_overflows)
          ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                theme.colorScheme.surface,
                theme.colorScheme.surface.withValues(alpha: 0),
              ],
              stops: const [0.7, 1],
            ).createShader(rect),
            child: clipped,
          )
        else
          clipped,
        if (_overflows) toggle,
      ],
    );
  }
}
