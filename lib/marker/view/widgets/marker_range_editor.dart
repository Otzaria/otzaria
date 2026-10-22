import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/marker_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/models/marker_palette.dart';
import 'package:otzaria/marker/services/marker_actions.dart';
import 'package:otzaria/marker/services/marker_book_index.dart';
import 'package:otzaria/marker/services/marker_range_edit.dart';
import 'package:otzaria/marker/services/marker_settings.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/search_result_book_display.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/text_book/utils/link_processing.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/theme/marker_colors.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';
import 'package:pdfrx/pdfrx.dart';

/// הזזת גבולות הסימון במילים שלמות. [firstSource]/[lastSource] — טקסט המקור;
/// [display] מציג אותו כמו בקורא (שמות קודש, ניקוד) לתצוגה ולטקסט שנשמר.
Future<void> editMarkerRange(
  BuildContext context,
  MarkerHighlight mark, {
  required String firstSource,
  required String lastSource,
  String Function(String source) display = _same,
}) async {
  final edit = MarkerRangeEdit(
    mark: mark,
    firstSource: firstSource,
    lastSource: lastSource,
  );
  if (!edit.isValid) {
    UiSnack.show(MarkerMessages.rangeOutdated);
    return;
  }
  final palette = MarkerSettings.instance.palette;
  final color = Color(
    palette.colorById(mark.colorId)?.argb ?? MarkerColor.argbOf(mark.colorHex),
  );
  final confirmed = await showTwoActionsDialog(
    context: context,
    title: 'שינוי מיקום הסימון',
    content: '',
    confirmText: 'שמירה',
    customContent: _RangeEditor(edit: edit, color: color, display: display),
  );
  if (confirmed != true || !edit.changed) return;
  final segments = edit.buildSegments();
  if (segments == null) return;
  await MarkerActions.instance.setRange(
    mark,
    segments,
    display(MarkerRangeEdit.textOf(segments)),
  );
}

/// הזזת הגבולות כשהספר אינו פתוח (מסך המרקר): טקסט המקור נקרא מקובץ הספר,
/// ומוצג לפי הגדרות התצוגה של הספר.
Future<void> editMarkerRangeFromBook(
  BuildContext context,
  MarkerHighlight mark,
) async {
  // קריאת ספר גדול נמשכת רגע; לחיצה נוספת בינתיים אינה פותחת חלון שני.
  if (_readingSource) return;
  final library = context.read<LibraryBloc>().state.library;
  if (library == null) {
    UiSnack.show(MarkerMessages.libraryNotReady);
    return;
  }
  final book = MarkerBookIndex.of(
    library,
  ).find(mark.bookTitle, mark.bookUid, pdf: mark.pdf);
  if (book == null) {
    UiSnack.showError(MarkerMessages.bookNotFound);
    return;
  }
  final settings = context.read<SettingsBloc>().state;
  final first = mark.segments.first.sectionIndex;
  final last = mark.segments.last.sectionIndex;
  ({String first, String last, String Function(String) display})? source;
  _readingSource = true;
  try {
    source = switch (book) {
      PdfBook() => await _pdfSource(book.path, first, last),
      TextBook() => await _textSource(
        book,
        first,
        last,
        await SearchResultBookDisplay.load(
          book,
          perBookSettingsEnabled: settings.enablePerBookSettings,
        ).then((display) => display.profile(settings.textDisplayPolicy)),
      ),
      _ => null,
    };
  } catch (error) {
    debugPrint('Marker: reading the source of ${mark.id} failed: $error');
  } finally {
    _readingSource = false;
  }
  if (!context.mounted) return;
  if (source == null) {
    UiSnack.showError(MarkerMessages.sourceUnavailable);
    return;
  }
  await editMarkerRange(
    context,
    mark,
    firstSource: source.first,
    lastSource: source.last,
    display: source.display,
  );
}

bool _readingSource = false;

Future<({String first, String last, String Function(String) display})?>
_textSource(
  TextBook book,
  int first,
  int last,
  TextDisplayProfile profile,
) async {
  final lines = await splitContentLines(
    await TextBookRepository(
      fileSystem: FileSystemData.instance,
    ).getBookContent(book),
  );
  if (first < 0 || last >= lines.length) return null;
  final settings = RenderSettings.fromProfile(profile);
  return (
    first: TextRendererService.stripHtml(lines[first]),
    last: TextRendererService.stripHtml(lines[last]),
    display: (String source) => TextRendererService.stripHtml(
      TextRendererService.processText(source, settings),
    ),
  );
}

Future<({String first, String last, String Function(String) display})?>
_pdfSource(String path, int first, int last) async {
  final document = await PdfDocument.openFile(path);
  try {
    final pages = document.pages;
    if (first < 1 || last > pages.length) return null;
    final firstText = (await pages[first - 1].loadStructuredText()).fullText;
    final lastText = first == last
        ? firstText
        : (await pages[last - 1].loadStructuredText()).fullText;
    return (first: firstText, last: lastText, display: _same);
  } finally {
    await document.dispose();
  }
}

String _same(String text) => text;

class _RangeEditor extends StatefulWidget {
  final MarkerRangeEdit edit;
  final Color color;
  final String Function(String source) display;

  const _RangeEditor({
    required this.edit,
    required this.color,
    required this.display,
  });

  @override
  State<_RangeEditor> createState() => _RangeEditorState();
}

class _RangeEditorState extends State<_RangeEditor> {
  /// רוחב קבוע, כדי שהחלון לא יקפוץ כשהגבולות זזים.
  static const double _width = 520;

  /// גובה קבוע לתצוגת הטקסט, מאותה סיבה.
  static const double _previewHeight = 156;

  /// כמה מילים מוצגות לפני הסימון ואחריו.
  static const int _contextWords = 14;

  MarkerRangeEdit get _edit => widget.edit;

  void _apply(VoidCallback change) => setState(change);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final words = _edit.firstWords;
    final span = _edit.wordSpan;
    final slider = _edit.single && words.length > 1;
    // צבע הסימון, כהה מעט בערכה בהירה (צהוב בהיר על רקע לבן) ובהיר מעט
    // בכהה, לסרגל ולמסגרת.
    final accent = Color.lerp(
      widget.color,
      theme.brightness == Brightness.dark ? Colors.white : Colors.black,
      0.3,
    )!;
    // השוליים של חלון הדו-שיח ושל התוכן שבו.
    final width = (MediaQuery.sizeOf(context).width - 128).clamp(0.0, _width);
    // נגלל כשהחלון נמוך (טלפון לרוחב); בדסקטופ הוא נכנס כולו.
    return SizedBox(
      width: width,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              slider
                  ? 'גררו את קצות הסרגל, או הוסיפו והסירו מילים בתחילת הסימון '
                        'ובסופו.'
                  : 'הוסיפו או הסירו מילים בתחילת הסימון ובסופו.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: _previewHeight,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: SingleChildScrollView(child: _preview(theme)),
            ),
            if (slider) ...[
              const SizedBox(height: 4),
              RangeSlider(
                values: RangeValues(
                  span.first.toDouble(),
                  span.last.toDouble(),
                ),
                min: 0,
                max: (words.length - 1).toDouble(),
                divisions: words.length - 1,
                activeColor: accent,
                labels: RangeLabels(
                  _word(_edit.firstWords[span.first]),
                  _word(_edit.firstWords[span.last]),
                ),
                onChanged: (values) => _apply(
                  () => _edit.setWordSpan(
                    values.start.round(),
                    values.end.round(),
                  ),
                ),
              ),
            ] else
              const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _EdgeControls(
                    label: 'תחילת הסימון',
                    word: _edgeWord(start: true),
                    canGrow: _edit.canGrowStart,
                    canShrink: _edit.canShrinkStart,
                    onGrow: () => _apply(_edit.growStart),
                    onShrink: () => _apply(_edit.shrinkStart),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _EdgeControls(
                    label: 'סוף הסימון',
                    word: _edgeWord(start: false),
                    canGrow: _edit.canGrowEnd,
                    canShrink: _edit.canShrinkEnd,
                    onGrow: () => _apply(_edit.growEnd),
                    onShrink: () => _apply(_edit.shrinkEnd),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _summary(span),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _edit.changed ? () => _apply(_edit.reset) : null,
                  icon: const Icon(
                    FluentIcons.arrow_reset_24_regular,
                    size: 18,
                  ),
                  label: const Text('חזרה לגבולות השמורים'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _summary(({int first, int last}) span) {
    final status = _edit.changed ? 'הגבולות שונו' : 'הגבולות השמורים';
    if (!_edit.single) {
      final unit = _edit.mark.pdf ? 'עמודים' : 'פסקאות';
      return '$status · הסימון חוצה ${_edit.mark.segments.length} $unit';
    }
    final count = span.last - span.first + 1;
    return '$status · ${count == 1 ? 'מילה אחת' : '$count מילים'}';
  }

  String? _edgeWord({required bool start}) {
    final word = _edit.edgeWord(start: start);
    return word == null ? null : _word(word, start ? _edit.first : _edit.last);
  }

  String _word(MarkerWord word, [List<String>? chars]) => widget.display(
    (chars ?? _edit.first).sublist(word.start, word.end).join(),
  );

  Widget _preview(ThemeData theme) {
    final dim = theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
      height: 1.6,
    );
    final marked = theme.textTheme.bodyLarge?.copyWith(
      backgroundColor: widget.color.withValues(
        alpha: MarkerColors.fillOpacity(0.55, theme.brightness),
      ),
      height: 1.6,
    );
    final spans = <InlineSpan>[];
    if (_edit.single) {
      _addWindow(
        spans,
        _edit.first,
        _edit.firstWords,
        _edit.start,
        _edit.end,
        dim,
        marked,
      );
    } else {
      _addWindow(
        spans,
        _edit.first,
        _edit.firstWords,
        _edit.start,
        _edit.first.length,
        dim,
        marked,
      );
      spans.add(TextSpan(text: '\n…\n', style: dim));
      _addWindow(spans, _edit.last, _edit.lastWords, 0, _edit.end, dim, marked);
    }
    return Text.rich(TextSpan(children: spans));
  }

  /// הטקסט סביב [from]–[to], עם עד [_contextWords] מילים מכל צד.
  void _addWindow(
    List<InlineSpan> spans,
    List<String> chars,
    List<MarkerWord> words,
    int from,
    int to,
    TextStyle? dim,
    TextStyle? marked,
  ) {
    final before = words.where((w) => w.end <= from).toList();
    final after = words.where((w) => w.start >= to).toList();
    final windowStart = before.length > _contextWords
        ? before[before.length - _contextWords].start
        : 0;
    final windowEnd = after.length > _contextWords
        ? after[_contextWords - 1].end
        : chars.length;
    // הגבולות הם גבולות מילים, ולכן כל קטע מוצג בנפרד בלי לפצל שם קודש.
    String slice(int a, int b) => widget.display(chars.sublist(a, b).join());
    spans.addAll([
      if (windowStart > 0) TextSpan(text: '… ', style: dim),
      TextSpan(text: slice(windowStart, from), style: dim),
      TextSpan(text: slice(from, to), style: marked),
      TextSpan(text: slice(to, windowEnd), style: dim),
      if (windowEnd < chars.length) TextSpan(text: ' …', style: dim),
    ]);
  }
}

/// הכפתורים של קצה אחד של הסימון, עם המילה שהוא נמצא בה עכשיו.
class _EdgeControls extends StatelessWidget {
  final String label;
  final String? word;
  final bool canGrow;
  final bool canShrink;
  final VoidCallback onGrow;
  final VoidCallback onShrink;

  const _EdgeControls({
    required this.label,
    required this.word,
    required this.canGrow,
    required this.canShrink,
    required this.onGrow,
    required this.onShrink,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 6, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelLarge),
                Text(
                  word ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'הוספת מילה ב$label',
            onPressed: canGrow ? onGrow : null,
            icon: const Icon(FluentIcons.add_24_regular, size: 18),
          ),
          const SizedBox(width: 4),
          IconButton.outlined(
            tooltip: 'הסרת מילה מ$label',
            onPressed: canShrink ? onShrink : null,
            icon: const Icon(FluentIcons.subtract_24_regular, size: 18),
          ),
        ],
      ),
    );
  }
}
