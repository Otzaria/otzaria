import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/models/marker_palette.dart';
import 'package:otzaria/marker/services/marker_actions.dart';
import 'package:otzaria/marker/services/marker_export.dart';
import 'package:otzaria/marker/view/marker_navigation.dart';
import 'package:otzaria/marker/view/widgets/marker_dialogs.dart';
import 'package:otzaria/marker/view/widgets/marker_marked_text.dart';
import 'package:otzaria/marker/view/widgets/marker_note_view.dart';
import 'package:otzaria/marker/view/widgets/marker_range_editor.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

enum _TileAction {
  open,
  note,
  deleteNote,
  range,
  tags,
  favorite,
  copy,
  delete,
}

/// שורה ברשימת המרקר. לחיצה פותחת את הספר במקום הסימון; Enter עושה אותו
/// דבר מהמקלדת.
class MarkerTile extends StatelessWidget {
  final MarkerHighlight mark;
  final MarkerPalette palette;
  final bool selecting;
  final bool selected;
  final bool focused;
  final ValueChanged<String> onToggleSelected;

  const MarkerTile({
    super.key,
    required this.mark,
    required this.palette,
    required this.selecting,
    required this.selected,
    required this.focused,
    required this.onToggleSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = palette.colorById(mark.colorId);
    final swatch = Color(color?.argb ?? MarkerColor.argbOf(mark.colorHex));
    final place = [mark.bookTitle, ?mark.ref].where((s) => s.isNotEmpty);
    final needsRepair = mark.status.needsRepair;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      clipBehavior: Clip.antiAlias,
      color: focused || selected ? cs.secondaryContainer : null,
      child: InkWell(
        onTap: selecting
            ? () => onToggleSelected(mark.id)
            : () => openMarkInBook(context, mark),
        onLongPress: () => onToggleSelected(mark.id),
        child: DecoratedBox(
          // הפס בצבע הסימון לכל גובה הכרטיס; הכרטיס מעגל את פינותיו.
          decoration: BoxDecoration(
            border: BorderDirectional(
              start: BorderSide(color: swatch, width: 6),
            ),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 4, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (selecting)
                  Checkbox(
                    value: selected,
                    semanticLabel: 'בחירת הסימון',
                    onChanged: (_) => onToggleSelected(mark.id),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (needsRepair)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(
                                end: 4,
                              ),
                              child: Tooltip(
                                message:
                                    mark.status == MarkerAnchorStatus.failed
                                    ? 'הטקסט המסומן לא נמצא בספר. פתחו את הספר וסמנו אותו מחדש.'
                                    : 'מקום הסימון אינו ודאי. פתחו את הספר כדי לבדוק אותו.',
                                child: Icon(
                                  FluentIcons.warning_16_regular,
                                  size: 16,
                                  color: cs.error,
                                  semanticLabel: 'דורש תיקון',
                                ),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              place.join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: cs.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      MarkerMarkedText(
                        mark,
                        maxLines: 3,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.4,
                        ),
                      ),
                      if (mark.hasNote)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          constraints: const BoxConstraints(maxHeight: 140),
                          // בלי גבול גובה העורך מתכווץ לתוכן; הכרטיס חותך הערה ארוכה.
                          child: SingleChildScrollView(
                            physics: const NeverScrollableScrollPhysics(),
                            child: IgnorePointer(
                              child: MarkerNoteView(
                                mark: mark,
                                maxChars: 400,
                                textStyle: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (color != null)
                            _Chip(
                              icon: FluentIcons.circle_16_filled,
                              iconColor: swatch,
                              text: color.label,
                            ),
                          _Chip(
                            icon: OtzariaIcons.calendar_24_regular,
                            text: markerDateLabel(mark.createdAt),
                          ),
                          if (mark.pdf)
                            const _Chip(
                              icon: OtzariaIcons.document_pdf_24_regular,
                              text: 'PDF',
                            ),
                          for (final tag in mark.tags)
                            _Chip(icon: FluentIcons.tag_16_regular, text: tag),
                        ],
                      ),
                    ],
                  ),
                ),
                // בבחירה מרובה הכרטיס כולו בוחר; הכפתורים רק היו מצרים אותו.
                if (!selecting) ...[
                  IconButton(
                    tooltip: mark.favorite
                        ? 'הסרה מהמועדפים'
                        : 'הוספה למועדפים',
                    onPressed: () => MarkerActions.instance.setFavorite([
                      mark.id,
                    ], !mark.favorite),
                    icon: Icon(
                      mark.favorite
                          ? FluentIcons.star_24_filled
                          : FluentIcons.star_24_regular,
                      color: mark.favorite ? cs.primary : null,
                    ),
                  ),
                  AppPopupMenuButton<Object>(
                    tooltip: 'פעולות',
                    icon: const Icon(FluentIcons.more_vertical_24_regular),
                    onSelected: (value) => _onSelected(context, value),
                    entries: [
                      const AppMenuEntry(
                        value: _TileAction.open,
                        label: 'פתיחה בספר',
                        icon: FluentIcons.book_open_24_regular,
                      ),
                      for (final color in palette.menuColors)
                        AppMenuEntry(
                          value: color,
                          label: 'צבע: ${color.label}',
                          icon: color.id == mark.colorId
                              ? FluentIcons.checkmark_circle_24_filled
                              : FluentIcons.circle_24_filled,
                          iconColor: Color(color.argb),
                        ),
                      AppMenuEntry(
                        value: _TileAction.note,
                        label: mark.hasNote ? 'עריכת הערה' : 'הוספת הערה',
                        icon: mark.hasNote
                            ? FluentIcons.note_edit_24_regular
                            : FluentIcons.note_add_24_regular,
                      ),
                      if (mark.hasNote)
                        const AppMenuEntry(
                          value: _TileAction.deleteNote,
                          label: 'מחיקת ההערה',
                          icon: FluentIcons.delete_24_regular,
                        ),
                      const AppMenuEntry(
                        value: _TileAction.range,
                        label: 'שינוי המיקום…',
                        icon: FluentIcons.arrow_autofit_width_24_regular,
                      ),
                      const AppMenuEntry(
                        value: _TileAction.tags,
                        label: 'תגיות…',
                        icon: FluentIcons.tag_24_regular,
                      ),
                      AppMenuEntry(
                        value: _TileAction.favorite,
                        label: mark.favorite
                            ? 'הסרה מהמועדפים'
                            : 'הוספה למועדפים',
                        icon: mark.favorite
                            ? FluentIcons.star_off_24_regular
                            : FluentIcons.star_24_regular,
                      ),
                      const AppMenuEntry(
                        value: _TileAction.copy,
                        label: 'העתקה עם מראה מקום',
                        icon: FluentIcons.copy_24_regular,
                      ),
                      const AppMenuEntry(
                        value: _TileAction.delete,
                        label: 'מחיקת הסימון',
                        icon: FluentIcons.eraser_24_regular,
                        isDestructive: true,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onSelected(BuildContext context, Object value) {
    final actions = MarkerActions.instance;
    switch (value) {
      case MarkerColor color:
        actions.recolor([mark.id], color);
      case _TileAction.open:
        openMarkInBook(context, mark);
      case _TileAction.note:
        editMarkerNote(context, mark);
      case _TileAction.deleteNote:
        deleteMarkerNote(context, mark);
      case _TileAction.range:
        editMarkerRangeFromBook(context, mark);
      case _TileAction.tags:
        editMarkerTags(context, mark);
      case _TileAction.favorite:
        actions.setFavorite([mark.id], !mark.favorite);
      case _TileAction.copy:
        actions.copy(mark);
      case _TileAction.delete:
        actions.remove([mark.id]);
    }
  }
}

/// תווית קטנה בתחתית הכרטיס: הצבע, התאריך או תגית.
class _Chip extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String text;

  const _Chip({required this.icon, required this.text, this.iconColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor ?? cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
