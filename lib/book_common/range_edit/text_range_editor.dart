import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/book_common/range_edit/text_range_edit.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/controls/app_icon_button.dart';

/// עורך של [TextRangeEdit]: תצוגת הטווח בהקשרו, סרגל מילים, הוספה והסרה בכל
/// קצה, והזזת הטווח כולו. אינו יודע מה הטווח מסמן.
class TextRangeEditor extends StatefulWidget {
  final TextRangeEdit edit;

  /// מציג קטע מטקסט המקור כמו בקורא (ניקוד, שמות קודש).
  final String Function(String source) display;

  /// "שורה" או "פסקה", לתוויות, ו-[paragraphsName] ברבים.
  final String paragraphName;
  final String paragraphsName;

  /// שם הפסקה [index] לתצוגה (כתובת או מספר).
  final String Function(int index)? paragraphLabel;

  /// צבע הטווח בתצוגה; ברירת המחדל primaryContainer.
  final Color? highlight;

  /// נקרא אחרי כל שינוי, כדי שהעוטף יעדכן את מה שתלוי בו.
  final VoidCallback? onChanged;

  /// כפתור "חזרה למה שנשמר"; עוטף שיש לו מצב נוסף מציג כפתור משלו.
  final bool showReset;

  const TextRangeEditor({
    super.key,
    required this.edit,
    this.display = _same,
    this.paragraphName = 'פסקה',
    this.paragraphsName = 'פסקאות',
    this.paragraphLabel,
    this.highlight,
    this.onChanged,
    this.showReset = true,
  });

  @override
  State<TextRangeEditor> createState() => _TextRangeEditorState();
}

String _same(String text) => text;

class _TextRangeEditorState extends State<TextRangeEditor> {
  /// גובה קבוע לתצוגה, כדי שהחלון לא יקפוץ כשהקצוות זזים.
  static const double _previewHeight = 156;

  /// כמה מילים מוצגות לפני הטווח ואחריו.
  static const int _contextWords = 14;

  /// אורך מרבי של פסקה שלמה בתצוגה.
  static const int _maxParagraphChars = 600;

  TextRangeEdit get _edit => widget.edit;
  bool get _words => _edit.unit == TextRangeUnit.words;

  void _apply(VoidCallback change) {
    setState(change);
    widget.onChanged?.call();
  }

  String _label(int index) =>
      widget.paragraphLabel?.call(index) ??
      '${widget.paragraphName} ${index + 1}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final name = widget.paragraphName;
    final words = _edit.wordsOf(_edit.start.paragraph);
    final slider = _words && _edit.isSingleParagraph && words.length > 1;
    final span = _edit.wordSpan;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: _previewHeight,
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceMD,
            vertical: AppTokens.spaceSM,
          ),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppTokens.radius),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: SingleChildScrollView(child: _preview(theme)),
        ),
        if (slider)
          RangeSlider(
            values: RangeValues(span.first.toDouble(), span.last.toDouble()),
            min: 0,
            max: (words.length - 1).toDouble(),
            divisions: words.length - 1,
            labels: RangeLabels(_wordAt(span.first), _wordAt(span.last)),
            onChanged: (values) => _apply(
              () => _edit.setWordSpan(values.start.round(), values.end.round()),
            ),
          )
        else
          const SizedBox(height: AppTokens.spaceSM),
        Row(
          children: [
            Expanded(
              child: _EdgeControls(
                label: 'התחלה',
                value: _words
                    ? widget.display(_edit.edgeWord(atStart: true))
                    : _opening(_edit.start.paragraph),
                unit: _words ? 'מילה' : name,
                onGrow: _edit.canGrowStart
                    ? () => _apply(_edit.growStart)
                    : null,
                onShrink: _edit.canShrinkStart
                    ? () => _apply(_edit.shrinkStart)
                    : null,
              ),
            ),
            const SizedBox(width: AppTokens.spaceSMD),
            Expanded(
              child: _EdgeControls(
                label: 'סוף',
                value: _words
                    ? widget.display(_edit.edgeWord(atStart: false))
                    : _opening(_edit.end.paragraph),
                unit: _words ? 'מילה' : name,
                onGrow: _edit.canGrowEnd ? () => _apply(_edit.growEnd) : null,
                onShrink: _edit.canShrinkEnd
                    ? () => _apply(_edit.shrinkEnd)
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceSM),
        Row(
          children: [
            Expanded(
              child: Text(
                _summary(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: small,
              ),
            ),
            if (_words) ...[
              AppIconButton(
                tooltip: 'הזזה במילה אחורה',
                onPressed: _edit.canMoveEarlier
                    ? () => _apply(_edit.moveEarlier)
                    : null,
                icon: const Icon(FluentIcons.arrow_left_24_regular),
              ),
              AppIconButton(
                tooltip: 'הזזה במילה קדימה',
                onPressed: _edit.canMoveLater
                    ? () => _apply(_edit.moveLater)
                    : null,
                icon: const Icon(FluentIcons.arrow_right_24_regular),
              ),
            ],
            if (_words && !_edit.crossParagraphs) ...[
              AppIconButton(
                tooltip: 'מעבר ל$name הקודמת',
                onPressed: _edit.start.paragraph > 0
                    ? () => _apply(
                        () => _edit.goToParagraph(_edit.start.paragraph - 1),
                      )
                    : null,
                icon: const Icon(FluentIcons.arrow_up_24_regular),
              ),
              AppIconButton(
                tooltip: 'מעבר ל$name הבאה',
                onPressed: _edit.start.paragraph < _edit.paragraphCount - 1
                    ? () => _apply(
                        () => _edit.goToParagraph(_edit.start.paragraph + 1),
                      )
                    : null,
                icon: const Icon(FluentIcons.arrow_down_24_regular),
              ),
            ],
            if (!_words) ...[
              AppIconButton(
                tooltip: 'הזזה ב$name אחת אחורה',
                onPressed: _edit.canMoveEarlier
                    ? () => _apply(_edit.moveEarlier)
                    : null,
                icon: const Icon(FluentIcons.arrow_up_24_regular),
              ),
              AppIconButton(
                tooltip: 'הזזה ב$name אחת קדימה',
                onPressed: _edit.canMoveLater
                    ? () => _apply(_edit.moveLater)
                    : null,
                icon: const Icon(FluentIcons.arrow_down_24_regular),
              ),
            ],
          ],
        ),
        if (widget.showReset)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: ActionButton.ghost(
              text: 'חזרה למה שנשמר',
              icon: FluentIcons.arrow_reset_24_regular,
              onPressed: _edit.changed ? () => _apply(_edit.reset) : null,
            ),
          ),
      ],
    );
  }

  String _summary() {
    final start = _edit.start.paragraph;
    final end = _edit.end.paragraph;
    // כתובת לפי תוכן העניינים זהה לרוב לכמה פסקאות רצופות.
    final where = _label(start) == _label(end)
        ? _label(start)
        : '${_label(start)} – ${_label(end)}';
    if (!_words) {
      final count = end - start + 1;
      return count == 1 ? where : '$where · $count ${widget.paragraphsName}';
    }
    if (!_edit.isSingleParagraph) return where;
    final span = _edit.wordSpan;
    final count = span.last - span.first + 1;
    return '$where · ${count == 1 ? 'מילה אחת' : '$count מילים'}';
  }

  /// המילים הראשונות של הפסקה, שמזהות אותה גם כשהכתובת משותפת לכמה פסקאות.
  String _opening(int index) {
    final words = _edit.wordsOf(index);
    if (words.isEmpty) return _label(index);
    final text = _edit.paragraph(index);
    final to = words[words.length > 4 ? 3 : words.length - 1].end;
    return '${widget.display(text.substring(0, to))}${to < text.length ? '…' : ''}';
  }

  String _wordAt(int index) {
    final paragraph = _edit.start.paragraph;
    final word = _edit.wordsOf(paragraph)[index];
    return widget.display(
      _edit.paragraph(paragraph).substring(word.start, word.end),
    );
  }

  Widget _preview(ThemeData theme) {
    final cs = theme.colorScheme;
    final dim = theme.textTheme.bodyLarge?.copyWith(
      color: cs.onSurfaceVariant,
      height: 1.6,
    );
    final highlight = widget.highlight;
    final marked = theme.textTheme.bodyLarge?.copyWith(
      color: highlight == null ? cs.onPrimaryContainer : null,
      backgroundColor: highlight ?? cs.primaryContainer,
      height: 1.6,
    );
    final spans = <InlineSpan>[];
    final start = _edit.start;
    final end = _edit.end;
    if (_words && _edit.isSingleParagraph) {
      _addWindow(spans, start.paragraph, start.offset, end.offset, dim, marked);
    } else if (_words) {
      final first = _edit.paragraph(start.paragraph);
      _addWindow(
        spans,
        start.paragraph,
        start.offset,
        first.length,
        dim,
        marked,
      );
      final between = end.paragraph - start.paragraph - 1;
      spans.add(TextSpan(text: '\n', style: dim));
      if (between > 0) {
        spans.add(TextSpan(text: '${_middle(between)}\n', style: marked));
      }
      _addWindow(spans, end.paragraph, 0, end.offset, dim, marked);
    } else {
      if (start.paragraph > 0) {
        spans.add(
          TextSpan(text: '${_tail(start.paragraph - 1)}\n', style: dim),
        );
      }
      final count = end.paragraph - start.paragraph + 1;
      for (var p = start.paragraph; p <= end.paragraph; p++) {
        if (count > 3 && p == start.paragraph + 1) {
          spans.add(TextSpan(text: '${_middle(count - 2)}\n', style: marked));
          p = end.paragraph - 1;
          continue;
        }
        spans.add(TextSpan(text: _whole(p), style: marked));
        if (p < end.paragraph) spans.add(TextSpan(text: '\n', style: dim));
      }
      if (end.paragraph < _edit.paragraphCount - 1) {
        spans.add(TextSpan(text: '\n${_head(end.paragraph + 1)}', style: dim));
      }
    }
    return Text.rich(TextSpan(children: spans));
  }

  String _middle(int count) =>
      '… ועוד $count ${count == 1 ? widget.paragraphName : widget.paragraphsName} …';

  String _whole(int index) {
    final text = _edit.paragraph(index);
    return widget.display(
      text.length > _maxParagraphChars
          ? '${text.substring(0, _maxParagraphChars)}…'
          : text,
    );
  }

  String _tail(int index) {
    final words = _edit.wordsOf(index);
    if (words.isEmpty) return '';
    final from = words[words.length > 8 ? words.length - 8 : 0].start;
    return '${from > 0 ? '… ' : ''}${widget.display(_edit.paragraph(index).substring(from))}';
  }

  String _head(int index) {
    final words = _edit.wordsOf(index);
    if (words.isEmpty) return '';
    final text = _edit.paragraph(index);
    final to = words[words.length > 8 ? 7 : words.length - 1].end;
    return '${widget.display(text.substring(0, to))}${to < text.length ? ' …' : ''}';
  }

  /// הטקסט סביב [from]–[to] בפסקה, עם עד [_contextWords] מילים מכל צד.
  void _addWindow(
    List<InlineSpan> spans,
    int paragraph,
    int from,
    int to,
    TextStyle? dim,
    TextStyle? marked,
  ) {
    final text = _edit.paragraph(paragraph);
    final words = _edit.wordsOf(paragraph);
    final before = words.where((w) => w.end <= from).toList();
    final after = words.where((w) => w.start >= to).toList();
    final windowStart = before.length > _contextWords
        ? before[before.length - _contextWords].start
        : 0;
    final windowEnd = after.length > _contextWords
        ? after[_contextWords - 1].end
        : text.length;
    // כל קטע מוצג בנפרד בגבולות מילים, ולכן שם קודש אינו נחתך.
    String slice(int a, int b) => widget.display(text.substring(a, b));
    spans.addAll([
      if (windowStart > 0) TextSpan(text: '… ', style: dim),
      TextSpan(text: slice(windowStart, from), style: dim),
      TextSpan(text: slice(from, to), style: marked),
      TextSpan(text: slice(to, windowEnd), style: dim),
      if (windowEnd < text.length) TextSpan(text: ' …', style: dim),
    ]);
  }
}

/// הכפתורים של קצה אחד, עם המקום שהוא נמצא בו עכשיו.
class _EdgeControls extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final VoidCallback? onGrow;
  final VoidCallback? onShrink;

  const _EdgeControls({
    required this.label,
    required this.value,
    required this.unit,
    required this.onGrow,
    required this.onShrink,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppTokens.spaceSMD,
        AppTokens.spaceXS,
        AppTokens.spaceXS,
        AppTokens.spaceXS,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.radius),
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
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          AppIconButton(
            tooltip: 'הוספת $unit ב$label',
            onPressed: onGrow,
            icon: const Icon(FluentIcons.add_24_regular),
          ),
          AppIconButton(
            tooltip: 'הסרת $unit מה$label',
            onPressed: onShrink,
            icon: const Icon(FluentIcons.subtract_24_regular),
          ),
        ],
      ),
    );
  }
}
