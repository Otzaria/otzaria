import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/models/direct_error_report.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/utils/canonical_json.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// מאתר את [selected] כתת-מחרוזת יחידה ומדויקת של [line]; null כשאין מופע
/// או שיש יותר מאחד — אסור לנחש איזה מופע סומן.
({int start, int end})? locateSelectionInLine(String line, String selected) {
  if (selected.isEmpty) return null;
  final first = line.indexOf(selected);
  if (first < 0) return null;
  if (line.indexOf(selected, first + 1) >= 0) return null;
  return (start: first, end: first + selected.length);
}

/// בונה את תבנית הצעת התיקון מהשורה הגולמית: לבחירה שאותרה חד-משמעית,
/// אחרת לשורה כולה.
TextCorrection buildCorrectionTemplate(String originalLine, String selected) {
  final located =
      _locateAsDisplayed(originalLine, selected) ??
      _locateAsDisplayed(originalLine, selected.trim());
  if (located == null) {
    return TextCorrection.wholeLine(originalLine: originalLine);
  }
  return TextCorrection.selection(
    originalLine: originalLine,
    start: located.start,
    end: located.end,
  );
}

/// התצוגה עשויה להסתיר ניקוד, טעמים ותגיות — מופע יחיד בגולמי מתקבל רק אם
/// גם בנוסח המצומצם ביותר יש מופע אחד, ואינו בתוך תגית.
({int start, int end})? _locateAsDisplayed(String line, String selected) {
  final located = locateSelectionInLine(line, selected);
  if (located == null) return null;
  if (line.lastIndexOf('<', located.start) >
      line.lastIndexOf('>', located.start)) {
    return null;
  }
  final shown = removeVolwels(stripHtmlIfNeeded(line));
  return locateSelectionInLine(shown, removeVolwels(selected)) == null
      ? null
      : located;
}

enum TextDiffOp { equal, removed, added }

class TextDiffSegment {
  final TextDiffOp op;
  final String text;

  const TextDiffSegment(this.op, this.text);

  @override
  bool operator ==(Object other) =>
      other is TextDiffSegment && other.op == op && other.text == text;

  @override
  int get hashCode => Object.hash(op, text);

  @override
  String toString() => '${op.name}:"$text"';
}

final RegExp _diffTokenPattern = RegExp(r'\s+|\S+');

/// תקרת תאי ה-LCS; מעבר לה החלק האמצעי מוצג כהחלפה אחת.
const int _maxLcsCells = 400000;

/// הבדל ברמת מילה בין [before] ל-[after]. מילה נשמרת שלמה (עם הניקוד שלה),
/// ורווחים הם אסימונים נפרדים כדי ששינוי רווח יוצג.
List<TextDiffSegment> computeTextDiff(String before, String after) {
  final a = _diffTokenPattern.allMatches(before).map((m) => m[0]!).toList();
  final b = _diffTokenPattern.allMatches(after).map((m) => m[0]!).toList();

  var prefix = 0;
  while (prefix < a.length && prefix < b.length && a[prefix] == b[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < a.length - prefix &&
      suffix < b.length - prefix &&
      a[a.length - 1 - suffix] == b[b.length - 1 - suffix]) {
    suffix++;
  }

  final segments = <TextDiffSegment>[];
  void add(TextDiffOp op, String text) {
    if (text.isEmpty) return;
    if (segments.isNotEmpty && segments.last.op == op) {
      segments[segments.length - 1] = TextDiffSegment(
        op,
        segments.last.text + text,
      );
    } else {
      segments.add(TextDiffSegment(op, text));
    }
  }

  add(TextDiffOp.equal, a.sublist(0, prefix).join());
  final midA = a.sublist(prefix, a.length - suffix);
  final midB = b.sublist(prefix, b.length - suffix);
  if (midA.length * midB.length > _maxLcsCells) {
    add(TextDiffOp.removed, midA.join());
    add(TextDiffOp.added, midB.join());
  } else {
    for (final segment in _lcsDiff(midA, midB)) {
      add(segment.op, segment.text);
    }
  }
  add(TextDiffOp.equal, a.sublist(a.length - suffix).join());
  return segments;
}

List<TextDiffSegment> _lcsDiff(List<String> a, List<String> b) {
  final n = a.length;
  final m = b.length;
  final table = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      table[i][j] = a[i] == b[j]
          ? table[i + 1][j + 1] + 1
          : (table[i + 1][j] >= table[i][j + 1]
                ? table[i + 1][j]
                : table[i][j + 1]);
    }
  }
  final result = <TextDiffSegment>[];
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      result.add(TextDiffSegment(TextDiffOp.equal, a[i]));
      i++;
      j++;
    } else if (table[i + 1][j] >= table[i][j + 1]) {
      result.add(TextDiffSegment(TextDiffOp.removed, a[i]));
      i++;
    } else {
      result.add(TextDiffSegment(TextDiffOp.added, b[j]));
      j++;
    }
  }
  for (; i < n; i++) {
    result.add(TextDiffSegment(TextDiffOp.removed, a[i]));
  }
  for (; j < m; j++) {
    result.add(TextDiffSegment(TextDiffOp.added, b[j]));
  }
  return result;
}

/// אופן ההצעה: טקסט חלופי, מחיקה מכוונת (""), או ללא הצעה (null).
enum ProposalMode { replace, delete, none }

/// מצב העורך: ההצעה הנוכחית ושגיאה שחוסמת שליחה (null = תקין).
class TextCorrectionDraft {
  final TextCorrection correction;
  final String? error;

  const TextCorrectionDraft({required this.correction, this.error});

  bool get isValid => error == null;

  bool get hasProposal => correction.proposedText != null;
}

/// מחשב את ההצעה ואת שגיאת החסימה עבור [mode] ו-[editedText].
TextCorrectionDraft evaluateCorrectionDraft({
  required TextCorrection original,
  required ProposalMode mode,
  required String editedText,
}) {
  const max = TextCorrection.maxTextLength;
  final proposed = switch (mode) {
    ProposalMode.replace => editedText,
    ProposalMode.delete => '',
    ProposalMode.none => null,
  };
  final correction = original.withProposedText(proposed);
  String? error;
  if (hasLoneSurrogate(original.originalLine) ||
      (proposed != null && hasLoneSurrogate(proposed))) {
    error = ReportMessages.invalidCharacters;
  } else if (original.originalLine.length > max) {
    error = ReportMessages.originalTooLong(max);
  } else if (proposed != null && proposed.length > max) {
    error = ReportMessages.proposalTooLong(max);
  } else if (proposed != null && proposed == original.target) {
    error = ReportMessages.proposalIdentical;
  }
  return TextCorrectionDraft(correction: correction, error: error);
}

/// עורך הצעת תיקון: המקור מוצג בנפרד ואינו ניתן לעריכה, ושדה העריכה נטען
/// מראש בעותק שלו. כל שינוי מדווח דרך [onChanged].
class TextCorrectionEditor extends StatefulWidget {
  final TextCorrection original;
  final double fontSize;
  final ValueChanged<TextCorrectionDraft> onChanged;

  const TextCorrectionEditor({
    super.key,
    required this.original,
    required this.fontSize,
    required this.onChanged,
  });

  @override
  State<TextCorrectionEditor> createState() => _TextCorrectionEditorState();
}

class _TextCorrectionEditorState extends State<TextCorrectionEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.original.target,
  );
  ProposalMode _mode = ProposalMode.replace;

  TextCorrectionDraft get _draft => evaluateCorrectionDraft(
    original: widget.original,
    mode: _mode,
    editedText: _controller.text,
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(_notify);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onChanged(_draft);
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_notify);
    _controller.dispose();
    super.dispose();
  }

  void _notify() {
    if (!mounted) return;
    setState(() {});
    widget.onChanged(_draft);
  }

  void _setMode(ProposalMode mode) {
    _mode = mode;
    _notify();
  }

  TextStyle _textStyle(BuildContext context) =>
      (Theme.of(context).textTheme.bodyLarge ?? const TextStyle()).copyWith(
        fontSize: widget.fontSize,
        fontFamily:
            Settings.getValue<String>(SettingsRepository.keyFontFamily) ??
            AppFonts.defaultFont,
      );

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = _textStyle(context);
    final original = widget.original;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'טקסט המקור (לא ניתן לעריכה):',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          key: const ValueKey('correction-original'),
          constraints: const BoxConstraints(maxHeight: 150),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: AppTokens.borderRadiusAll,
          ),
          child: SingleChildScrollView(
            child: Text.rich(
              TextSpan(
                style: textStyle,
                children: [
                  TextSpan(
                    text: original.contextBefore,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  TextSpan(
                    text: original.target,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(
                    text: original.contextAfter,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!original.hasSelection) ...[
          const SizedBox(height: 4),
          Text(
            ReportMessages.correctionWholeLineNotice,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 8),
        AppSegmentedControl<ProposalMode>(
          options: const [
            SegmentOption(
              value: ProposalMode.replace,
              label: 'טקסט מוצע',
              icon: FluentIcons.edit_24_regular,
            ),
            SegmentOption(
              value: ProposalMode.delete,
              label: 'מחיקת הקטע',
              icon: FluentIcons.delete_24_regular,
            ),
            SegmentOption(
              value: ProposalMode.none,
              label: 'ללא הצעה',
              icon: FluentIcons.dismiss_circle_24_regular,
            ),
          ],
          currentValue: _mode,
          onChanged: _setMode,
          expandToFillWidth: true,
        ),
        const SizedBox(height: 8),
        if (_mode == ProposalMode.replace)
          RtlTextField(
            key: const ValueKey('correction-proposal-field'),
            controller: _controller,
            autofocus: true,
            minLines: 2,
            maxLines: null,
            style: textStyle,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              labelText: 'הנוסח המתוקן',
              errorText: draft.error,
              errorMaxLines: 3,
              helperText:
                  '${_controller.text.length} / ${TextCorrection.maxTextLength}',
            ),
          )
        else if (draft.error != null)
          Text(
            draft.error!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
            ),
          ),
        if (draft.hasProposal && draft.error == null) ...[
          const SizedBox(height: 8),
          Text(
            'השינוי המוצע:',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          TextCorrectionDiffView(
            key: const ValueKey('correction-diff'),
            before: original.target,
            after: draft.correction.proposedText!,
            style: textStyle,
          ),
        ],
      ],
    );
  }
}

/// תצוגת ההבדל: נמחק מסומן בקו חוצה, נוסף מודגש — בצבעי ה-theme בלבד.
class TextCorrectionDiffView extends StatelessWidget {
  final String before;
  final String after;
  final TextStyle style;

  const TextCorrectionDiffView({
    super.key,
    required this.before,
    required this.after,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final segments = computeTextDiff(before, after);
    return Container(
      constraints: const BoxConstraints(maxHeight: 150),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: SingleChildScrollView(
        child: Text.rich(
          TextSpan(
            style: style,
            children: [
              for (final segment in segments)
                TextSpan(
                  text: segment.text,
                  style: switch (segment.op) {
                    TextDiffOp.equal => null,
                    TextDiffOp.removed => TextStyle(
                      color: colorScheme.onErrorContainer,
                      backgroundColor: colorScheme.errorContainer,
                      decoration: TextDecoration.lineThrough,
                    ),
                    TextDiffOp.added => TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      backgroundColor: colorScheme.primaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
