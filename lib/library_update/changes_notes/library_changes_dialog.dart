import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/library/models/library.dart' show normalizeBookTitle;
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:positioned_sliver_list/positioned_sliver_list.dart';

import 'library_changes_store.dart';

enum LibraryChangesLineKind { title, subtitle, section, item, text }

class LibraryChangesLine {
  LibraryChangesLine(this.kind, this.text, {this.version})
    : searchKey = kind == LibraryChangesLineKind.item
          ? normalizeBookTitle(text)
          : '';

  final LibraryChangesLineKind kind;
  final String text;

  /// כותרת חלופית לקובץ שאין בו כותרת משלו — מוצגת כ"גרסת ספרייה N".
  final int? version;

  /// הטקסט המנורמל של פריט, כך ש-" בחיפוש מוצא גם ״.
  final String searchKey;
}

final _headingLine = RegExp(r'^(#{1,6})\s+(.*)$');
final _itemLine = RegExp(r'^[*\-+]\s+(.*)$');

/// מפרק את ה-Markdown של `library-changes.md` (כותרת, תאריך מודגש, כותרות
/// סעיפים ופריטי רשימה) לשורות — רשימה של אלפי ספרים נבנית בעצלות.
@visibleForTesting
List<LibraryChangesLine> parseLibraryChanges(LibraryChangesNote note) {
  final lines = <LibraryChangesLine>[];
  for (final raw in note.markdown.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final heading = _headingLine.firstMatch(line);
    if (heading != null) {
      lines.add(
        LibraryChangesLine(
          heading.group(1)!.length == 1
              ? LibraryChangesLineKind.title
              : LibraryChangesLineKind.section,
          _stripEmphasis(heading.group(2)!),
        ),
      );
      continue;
    }
    final item = _itemLine.firstMatch(line);
    if (item != null) {
      lines.add(
        LibraryChangesLine(
          LibraryChangesLineKind.item,
          _stripEmphasis(item.group(1)!),
        ),
      );
      continue;
    }
    final bold =
        line.startsWith('**') && line.endsWith('**') && line.length > 4;
    lines.add(
      LibraryChangesLine(
        bold ? LibraryChangesLineKind.subtitle : LibraryChangesLineKind.text,
        _stripEmphasis(line),
      ),
    );
  }
  if (lines.isEmpty || lines.first.kind != LibraryChangesLineKind.title) {
    lines.insert(
      0,
      LibraryChangesLine(
        LibraryChangesLineKind.title,
        note.releaseTag,
        version: note.version,
      ),
    );
  }
  return lines;
}

List<List<LibraryChangesLine>> _parseAll(List<LibraryChangesNote> notes) => [
  for (final note in notes) parseLibraryChanges(note),
];

/// מעל הגודל הזה הפירוק רץ ב-isolate ולא בבנייה.
const _parseInIsolateChars = 64 * 1024;

String _stripEmphasis(String text) => text.replaceAll('**', '').trim();

/// השורות של כל ההערות, ובחיפוש — רק פריטים שמכילים את [query] עם כותרות
/// הקובץ והסעיף שלהם.
@visibleForTesting
List<LibraryChangesLine> filterLibraryChanges(
  List<List<LibraryChangesLine>> notes,
  String query,
) {
  final q = normalizeBookTitle(query);
  if (q.isEmpty) return [for (final note in notes) ...note];
  final result = <LibraryChangesLine>[];
  for (final note in notes) {
    final header = <LibraryChangesLine>[];
    LibraryChangesLine? section;
    var sectionShown = false;
    var noteShown = false;
    for (final line in note) {
      switch (line.kind) {
        case LibraryChangesLineKind.title:
        case LibraryChangesLineKind.subtitle:
          if (section == null) header.add(line);
        case LibraryChangesLineKind.section:
          section = line;
          sectionShown = false;
        case LibraryChangesLineKind.text:
          break;
        case LibraryChangesLineKind.item:
          if (!line.searchKey.contains(q)) continue;
          if (!noteShown) {
            result.addAll(header);
            noteShown = true;
          }
          if (!sectionShown && section != null) {
            result.add(section);
            sectionShown = true;
          }
          result.add(line);
      }
    }
  }
  return result;
}

/// מציג את [notes] (החדשה קודם) בדיאלוג "מה חדש בספרים".
Future<void> showLibraryChangesDialog(
  BuildContext context,
  List<LibraryChangesNote> notes,
) => showDialog<void>(
  context: context,
  builder: settingsDialogBuilder(
    context,
    (_) => LibraryChangesDialog(notes: notes),
  ),
);

class LibraryChangesDialog extends StatefulWidget {
  const LibraryChangesDialog({super.key, required this.notes});

  final List<LibraryChangesNote> notes;

  static const searchDebounce = Duration(milliseconds: 200);

  @override
  State<LibraryChangesDialog> createState() => _LibraryChangesDialogState();
}

class _LibraryChangesDialogState extends State<LibraryChangesDialog> {
  final _search = TextEditingController();
  List<List<LibraryChangesLine>>? _parsed;
  List<LibraryChangesLine> _visible = const [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final chars = widget.notes.fold<int>(0, (n, e) => n + e.markdown.length);
    if (chars < _parseInIsolateChars) {
      _setParsed(_parseAll(widget.notes));
    } else {
      final notes = widget.notes;
      compute(_parseAll, notes).then((parsed) {
        if (mounted) setState(() => _setParsed(parsed));
      });
    }
  }

  void _setParsed(List<List<LibraryChangesLine>> parsed) {
    _parsed = parsed;
    _visible = filterLibraryChanges(parsed, _search.text);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(LibraryChangesDialog.searchDebounce, () {
      final parsed = _parsed;
      if (!mounted || parsed == null) return;
      setState(() => _visible = filterLibraryChanges(parsed, _search.text));
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AppDialog.singleAction(
      title: context.settingsText('מה חדש בספרים'),
      confirmText: context.settingsText('סגור'),
      customContent: SizedBox(
        width: size.width < 720 ? size.width * 0.9 : 640,
        height: size.height * 0.6,
        child: Column(
          children: [
            OtzariaSearchField(
              controller: _search,
              hintText: context.settingsText('חיפוש ספר ברשימה'),
              icon: OtzariaIcons.search_in_library_24_regular,
              selectAllOnFocus: false,
              onChanged: _onQueryChanged,
              onClear: () => _onQueryChanged(''),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _parsed == null
                  ? const Center(child: CircularProgressIndicator())
                  : _visible.isEmpty
                  ? Center(child: Text(context.settingsText('לא נמצאו ספרים')))
                  : ContentDirectionality(
                      child: Scrollbar(
                        // שורות בגובה משתנה: ListView רגיל בונה בקפיצת פס
                        // הגלילה את כל השורות שבדרך (#3022). מפתח לכל סינון,
                        // כדי שהגבהים שנמדדו לא יעברו לשורות אחרות.
                        child: SuperListView.builder(
                          key: ObjectKey(_visible),
                          itemCount: _visible.length,
                          itemBuilder: (context, index) =>
                              _LineView(line: _visible[index]),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineView extends StatelessWidget {
  const _LineView({required this.line});

  final LibraryChangesLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final version = line.version;
    return switch (line.kind) {
      LibraryChangesLineKind.title => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(
          version == null
              ? line.text
              : context.settingsText(
                  'גרסת ספרייה {version}',
                  args: {'version': version},
                ),
          style: theme.titleLarge,
        ),
      ),
      LibraryChangesLineKind.subtitle => Text(
        line.text,
        style: theme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
      LibraryChangesLineKind.section => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(line.text, style: theme.titleMedium),
      ),
      LibraryChangesLineKind.item => Padding(
        padding: const EdgeInsetsDirectional.only(start: 12, bottom: 2),
        child: Text('• ${line.text}'),
      ),
      LibraryChangesLineKind.text => Text(line.text),
    };
  }
}
