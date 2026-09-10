/// דיאלוג בחירת אפשרויות הייצוא ל-PDF של "תיקון קוראים".
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/tools/tikkun_korim/engine/verse_range_slicer.dart';
import 'package:otzaria/tools/tikkun_korim/export/tikkun_pdf_exporter.dart';
import 'package:otzaria/utils/text/numeral_formats.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// רוחב תוכן הדיאלוג — מספיק לארבע אפשרויות היקף בשורה אחת.
const double kTikkunExportDialogWidth = 460;

/// מציג את דיאלוג הייצוא ומחזיר את האפשרויות שנבחרו, או `null` בביטול.
///
/// [columnCount] מספר הטורים בקריאה הנוכחית, [currentColumn] אינדקס הטור המוצג.
/// [allowOriginalPages] — האם הטורים הם עמודי שיטה שאפשר לשמר כדף לדף;
/// כשלא, מוצע רק עימוד בזרימה. [verseDomain] (פרק → הפסוק האחרון בו) מאפשר
/// בחירת טווח פסוקים; `null` מסתיר את האפשרות.
Future<TikkunExportOptions?> showTikkunExportDialog({
  required BuildContext context,
  required int columnCount,
  required int currentColumn,
  bool allowOriginalPages = true,
  Map<int, int>? verseDomain,
  String title = 'ייצוא ל-PDF',
  String confirmText = 'ייצא',
  TikkunExportOptions initial = const TikkunExportOptions(),
}) async {
  final total = columnCount < 1 ? 1 : columnCount;
  final current = currentColumn.clamp(0, total - 1);
  final domain = verseDomain == null || verseDomain.isEmpty
      ? null
      : verseDomain;
  final chapters = domain?.keys.toList()?..sort();
  var options = initial.copyWith(
    fromColumn: current,
    toColumn: current,
    // בטור יחיד "העמוד הנוכחי" ו"הכל" זהים — מוצג רק "הכל".
    scope: total == 1 && initial.scope == TikkunExportScope.currentColumn
        ? TikkunExportScope.all
        : null,
    mode: allowOriginalPages ? null : TikkunExportMode.flow,
    fromChapter: chapters?.first,
    fromVerse: chapters == null ? null : 1,
    toChapter: chapters?.last,
    toVerse: chapters == null ? null : domain![chapters.last],
  );
  final confirmed = await showTwoActionsDialog(
    context: context,
    title: title,
    content: '',
    confirmText: confirmText,
    customContent: TikkunExportForm(
      initial: options,
      columnCount: total,
      allowOriginalPages: allowOriginalPages,
      verseDomain: domain,
      onChanged: (value) => options = value,
    ),
  );
  return confirmed == true ? options : null;
}

/// גוף הדיאלוג — בחירת ההיקף, העימוד, גודל הדף והטורים.
class TikkunExportForm extends StatefulWidget {
  final TikkunExportOptions initial;
  final int columnCount;
  final bool allowOriginalPages;
  final Map<int, int>? verseDomain;
  final ValueChanged<TikkunExportOptions> onChanged;

  const TikkunExportForm({
    super.key,
    required this.initial,
    required this.columnCount,
    required this.onChanged,
    this.allowOriginalPages = true,
    this.verseDomain,
  });

  @override
  State<TikkunExportForm> createState() => _TikkunExportFormState();
}

class _TikkunExportFormState extends State<TikkunExportForm> {
  late TikkunExportOptions _options = widget.initial;
  late final TextEditingController _from = TextEditingController(
    text: '${_options.fromColumn + 1}',
  );
  late final TextEditingController _to = TextEditingController(
    text: '${_options.toColumn + 1}',
  );

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  late final List<int> _chapters = (widget.verseDomain?.keys.toList() ?? [])
    ..sort();

  void _update(TikkunExportOptions options) {
    setState(() => _options = options);
    widget.onChanged(options);
  }

  /// אפשרויות ההיקף הרלוונטיות: טווח עמודים רק כשיש כמה, פסוקים רק כשידועים.
  List<SegmentOption<TikkunExportScope>> get _scopeOptions => [
    if (widget.columnCount > 1)
      const SegmentOption(
        value: TikkunExportScope.currentColumn,
        label: 'העמוד הנוכחי',
      ),
    const SegmentOption(value: TikkunExportScope.all, label: 'הכל'),
    if (widget.columnCount > 1)
      const SegmentOption(
        value: TikkunExportScope.range,
        label: 'טווח עמודים',
      ),
    if (_chapters.isNotEmpty)
      const SegmentOption(
        value: TikkunExportScope.verseRange,
        label: 'טווח פסוקים',
      ),
  ];

  /// מעדכן את טווח הפסוקים ושומר על "מ" ≤ "עד": הקצה שלא שונה נגרר אחרי
  /// זה ששונה.
  void _setVerseRange({
    int? fromChapter,
    int? fromVerse,
    int? toChapter,
    int? toVerse,
  }) {
    final domain = widget.verseDomain!;
    var fromCh = fromChapter ?? _options.fromChapter;
    var fromVs = fromChapter != null ? 1 : (fromVerse ?? _options.fromVerse);
    var toCh = toChapter ?? _options.toChapter;
    var toVs = toChapter != null
        ? domain[toChapter] ?? 1
        : (toVerse ?? _options.toVerse);
    final changedTo = toChapter != null || toVerse != null;
    if (compareVerse(fromCh, fromVs, toCh, toVs) > 0) {
      if (changedTo) {
        fromCh = toCh;
        fromVs = toVs;
      } else {
        toCh = fromCh;
        toVs = fromVs;
      }
    }
    _update(
      _options.copyWith(
        fromChapter: fromCh,
        fromVerse: fromVs,
        toChapter: toCh,
        toVerse: toVs,
      ),
    );
  }

  /// ממיר קלט 1-based לאינדקס תקין, ושומר על from ≤ to.
  void _updateRange() {
    final last = widget.columnCount - 1;
    var from = (int.tryParse(_from.text.trim()) ?? 1) - 1;
    var to = (int.tryParse(_to.text.trim()) ?? widget.columnCount) - 1;
    from = from.clamp(0, last);
    to = to.clamp(0, last);
    if (to < from) to = from;
    _update(_options.copyWith(fromColumn: from, toColumn: to));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kTikkunExportDialogWidth,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_scopeOptions.length > 1)
              _field(
                'היקף',
                AppSegmentedControl<TikkunExportScope>(
                  expandToFillWidth: true,
                  showSelectedIcon: false,
                  currentValue: _options.scope,
                  options: _scopeOptions,
                  onChanged: (value) =>
                      _update(_options.copyWith(scope: value)),
                ),
              ),
            if (_options.scope == TikkunExportScope.range) _rangeFields(),
            if (_options.scope == TikkunExportScope.verseRange)
              _verseRangeFields(),
            if (widget.allowOriginalPages)
              _field(
                'עימוד',
                AppSegmentedControl<TikkunExportMode>(
                  expandToFillWidth: true,
                  showSelectedIcon: false,
                  currentValue: _options.mode,
                  options: const [
                    SegmentOption(
                      value: TikkunExportMode.originalPages,
                      label: 'עמודים מקוריים',
                    ),
                    SegmentOption(
                      value: TikkunExportMode.flow,
                      label: 'זרימה רציפה',
                    ),
                  ],
                  onChanged: (value) => _update(_options.copyWith(mode: value)),
                ),
              ),
            _field(
              'גודל דף',
              AppSegmentedControl<TikkunExportPageSize>(
                expandToFillWidth: true,
                showSelectedIcon: false,
                currentValue: _options.pageSize,
                options: [
                  for (final size in TikkunExportPageSize.values)
                    SegmentOption(value: size, label: size.label),
                ],
                onChanged: (value) =>
                    _update(_options.copyWith(pageSize: value)),
              ),
            ),
            _field(
              'טורים',
              AppSegmentedControl<TikkunExportColumns>(
                expandToFillWidth: true,
                showSelectedIcon: false,
                currentValue: _options.columns,
                options: const [
                  SegmentOption(
                    value: TikkunExportColumns.both,
                    label: 'שני הטורים',
                  ),
                  SegmentOption(
                    value: TikkunExportColumns.stamOnly,
                    label: 'סת"ם בלבד',
                  ),
                  SegmentOption(
                    value: TikkunExportColumns.nikudOnly,
                    label: 'מנוקד בלבד',
                  ),
                ],
                onChanged: (value) =>
                    _update(_options.copyWith(columns: value)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rangeFields() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      children: [
        Expanded(child: _numberField('מעמוד', _from)),
        const SizedBox(width: 12),
        Expanded(child: _numberField('עד עמוד', _to)),
        const SizedBox(width: 12),
        Text(
          'מתוך ${widget.columnCount}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );

  Widget _verseRangeFields() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      children: [
        _verseRow(
          label: 'מפרק',
          chapter: _options.fromChapter,
          verse: _options.fromVerse,
          onChapter: (value) => _setVerseRange(fromChapter: value),
          onVerse: (value) => _setVerseRange(fromVerse: value),
        ),
        const SizedBox(height: 8),
        _verseRow(
          label: 'עד פרק',
          chapter: _options.toChapter,
          verse: _options.toVerse,
          onChapter: (value) => _setVerseRange(toChapter: value),
          onVerse: (value) => _setVerseRange(toVerse: value),
        ),
      ],
    ),
  );

  Widget _verseRow({
    required String label,
    required int chapter,
    required int verse,
    required ValueChanged<int> onChapter,
    required ValueChanged<int> onVerse,
  }) {
    final lastVerse = widget.verseDomain![chapter] ?? 1;
    return Row(
      children: [
        SizedBox(width: 52, child: Text(label)),
        Expanded(
          child: AppDropdownField<int>(
            value: chapter,
            enableSearch: true,
            entries: [
              for (final ch in _chapters)
                AppMenuEntry(value: ch, label: toHebrewNumeral(ch)),
            ],
            onSelected: (value) => value == null ? null : onChapter(value),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('פסוק'),
        ),
        Expanded(
          child: AppDropdownField<int>(
            value: verse.clamp(1, lastVerse),
            enableSearch: true,
            entries: [
              for (var vs = 1; vs <= lastVerse; vs++)
                AppMenuEntry(value: vs, label: toHebrewNumeral(vs)),
            ],
            onSelected: (value) => value == null ? null : onVerse(value),
          ),
        ),
      ],
    );
  }

  Widget _numberField(String label, TextEditingController controller) =>
      RtlTextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: (_) => _updateRange(),
      );

  Widget _field(String label, Widget control) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        control,
      ],
    ),
  );
}
