import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/marker/models/marker_palette.dart';
import 'package:otzaria/marker/models/marker_query.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

/// מסנני מהירות: מצב, צבע ותגית, עם מונה לכל מסנן בתוך החיפוש הנוכחי.
/// מסנן שאין בו תוצאות מוסתר, אלא אם הוא הפעיל.
class MarkerFilterBar extends StatelessWidget {
  final MarkerQuery query;
  final MarkerCounts counts;
  final MarkerPalette palette;
  final List<({String tag, int count})> tags;
  final ValueChanged<MarkerQuery> onChanged;

  const MarkerFilterBar({
    super.key,
    required this.query,
    required this.counts,
    required this.palette,
    required this.tags,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final statusChips = [
      (MarkerStatusFilter.favorites, 'מועדפים', counts.favorites),
      (MarkerStatusFilter.noted, 'עם הערה', counts.noted),
      (MarkerStatusFilter.tagged, 'עם תגית', counts.tagged),
      (MarkerStatusFilter.needsRepair, 'דורשים תיקון', counts.needsRepair),
    ];
    final chips = <Widget>[
      FilterChip(
        label: const Text('הכול'),
        selected: !query.hasFilters,
        onSelected: (_) => onChanged(
          MarkerQuery(sort: query.sort, group: query.group),
        ),
      ),
      for (final (status, label, count) in statusChips)
        if (count > 0 || query.status == status)
          FilterChip(
            label: Text('$label · $count'),
            selected: query.status == status,
            onSelected: (selected) => onChanged(
              query.copyWith(
                status: selected ? status : MarkerStatusFilter.all,
              ),
            ),
          ),
      for (final color in palette.colors)
        if ((counts.byColor[color.id] ?? 0) > 0 || query.colorId == color.id)
          FilterChip(
            avatar: Icon(
              FluentIcons.circle_24_filled,
              color: Color(color.argb),
              size: 16,
            ),
            label: Text(
              '${color.label} · ${counts.byColor[color.id] ?? 0}',
            ),
            selected: query.colorId == color.id,
            onSelected: (selected) => onChanged(
              query.copyWith(colorId: () => selected ? color.id : null),
            ),
          ),
      if (tags.isNotEmpty || query.tag != null)
        AppPopupMenuButton<String>(
          tooltip: 'סינון לפי תגית',
          iconData: FluentIcons.tag_24_regular,
          highlighted: query.tag != null,
          initialValue: query.tag ?? '',
          onSelected: (tag) => onChanged(
            query.copyWith(tag: () => tag.isEmpty ? null : tag),
          ),
          entries: [
            const AppMenuEntry(value: '', label: 'כל התגיות'),
            for (final tag in tags)
              AppMenuEntry(
                value: tag.tag,
                label: '${tag.tag} · ${tag.count}',
              ),
          ],
        ),
      if (query.tag != null)
        InputChip(
          label: Text(query.tag!),
          onDeleted: () => onChanged(query.copyWith(tag: () => null)),
        ),
      if (query.bookTitle != null)
        InputChip(
          avatar: const Icon(FluentIcons.book_24_regular, size: 16),
          label: Text(markerBookLabel(query.bookTitle!, pdf: query.bookPdf)),
          onDeleted: () => onChanged(query.copyWith(bookTitle: () => null)),
        ),
    ];
    // בטלפון שורה אחת שנגללת לרוחב, כדי שהמסננים לא יתפסו חצי מסך.
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      child: narrow
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final chip in chips)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: chip,
                    ),
                ],
              ),
            )
          : Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: chips,
            ),
    );
  }
}
