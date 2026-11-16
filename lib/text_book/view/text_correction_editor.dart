import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/reports/view_scope.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';
import 'package:otzaria/widgets/smart_text/otzaria_widget_factory.dart';
import 'package:otzaria/widgets/smart_text/raised_markers.dart';
import 'package:otzaria/widgets/smart_text/smart_text_css.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

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
  if (!_isPlainTextRange(line, located.start, located.end)) return null;
  final shown = removeVolwels(stripHtmlIfNeeded(line));
  return locateSelectionInLine(shown, removeVolwels(selected)) == null
      ? null
      : located;
}

// Conservative: unknown named references also use the whole-line path. This
// guard does not decode or attempt to map visible characters back to raw HTML.
final RegExp _htmlCharacterReference = RegExp(
  r'&(?:#[xX][0-9a-fA-F]+;?|#[0-9]+;?|[a-zA-Z][a-zA-Z0-9]*;?)',
);

/// Text outside tags and comments that cuts no character reference: visible
/// "&amp;" in raw "&amp;amp;" must not map to only part of the reference.
bool _isPlainTextRange(String html, int start, int end) =>
    _isVisibleSourceRange(html, start, end) &&
    !_htmlCharacterReference
        .allMatches(html)
        .any((reference) => reference.start < end && reference.end > start);

/// A `>` in a quoted attribute or comment is not a tag end. Ambiguous markup
/// uses the unchanged whole-line path without mapping decoded text to HTML.
bool _isVisibleSourceRange(String html, int start, int end) {
  var inTag = false;
  var inComment = false;
  String? quote;
  for (var i = 0; i < end; i++) {
    if (!inTag && !inComment && html.startsWith('<!--', i)) {
      inComment = true;
    } else if (!inTag && !inComment && html[i] == '<') {
      inTag = true;
    }
    if (i >= start && (inTag || inComment)) return false;
    if (inComment) {
      if (html.startsWith('-->', i)) {
        if (i + 2 >= start) return false;
        inComment = false;
        i += 2;
      }
    } else if (inTag) {
      final char = html[i];
      if (quote != null) {
        if (char == quote) quote = null;
      } else if (char == '"' || char == "'") {
        quote = char;
      } else if (char == '>') {
        inTag = false;
      }
    }
  }
  return !inTag && !inComment;
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

const String _targetTag = 'correction-target';
const String _removedTag = 'correction-removed';
const String _addedTag = 'correction-added';

/// בשורה יש תגיות או ישויות, ולכן תצוגתה בספר שונה מקוד המקור.
bool hasRenderableMarkup(String html) =>
    html.contains('<') || _htmlCharacterReference.hasMatch(html);

/// [html] with the text of [start, end) wrapped in a marker, one wrapper per run
/// between tags so the markup stays balanced.
String markTargetInHtml(String html, int start, int end) {
  // בחירה מטיוטה ישנה עלולה לחתוך ישות; אז מסומנת השורה כולה.
  if (!_isPlainTextRange(html, start, end)) (start, end) = (0, html.length);
  final out = StringBuffer();
  var inTag = false;
  var inComment = false;
  String? quote;
  var open = false;
  for (var i = 0; i < html.length; i++) {
    if (!inTag && !inComment) {
      if (html.startsWith('<!--', i)) {
        inComment = true;
      } else if (html[i] == '<') {
        inTag = true;
      }
    }
    final mark = !inTag && !inComment && i >= start && i < end;
    if (mark != open) {
      out.write(open ? '</$_targetTag>' : '<$_targetTag>');
      open = mark;
    }
    final char = html[i];
    out.write(char);
    if (inComment) {
      if (html.startsWith('-->', i)) {
        out.write('->');
        i += 2;
        inComment = false;
      }
    } else if (inTag) {
      if (quote != null) {
        if (char == quote) quote = null;
      } else if (char == '"' || char == "'") {
        quote = char;
      } else if (char == '>') {
        inTag = false;
      }
    }
  }
  if (open) out.write('</$_targetTag>');
  return out.toString();
}

/// ההבדל בין [before] ל-[after] כ-HTML, השינויים עטופים בסימון; null כששינוי
/// נוגע בתגית או בישות, או כולו רווחים שהרינדור מכווץ — אלה נאמנים רק כקוד מקור.
String? correctionDiffHtml({
  required String before,
  required String after,
  String contextBefore = '',
  String contextAfter = '',
}) {
  final fullBefore = '$contextBefore$before$contextAfter';
  final fullAfter = '$contextBefore$after$contextAfter';
  final out = StringBuffer(contextBefore);
  var beforePos = contextBefore.length;
  var afterPos = contextBefore.length;
  var visibleChange = false;
  for (final segment in computeTextDiff(before, after)) {
    if (segment.op != TextDiffOp.equal && segment.text.trim().isNotEmpty) {
      visibleChange = true;
    }
    final text = segment.text;
    switch (segment.op) {
      case TextDiffOp.equal:
        out.write(text);
        beforePos += text.length;
        afterPos += text.length;
      case TextDiffOp.removed:
        if (!_isPlainTextRange(
          fullBefore,
          beforePos,
          beforePos + text.length,
        )) {
          return null;
        }
        out.write('<$_removedTag>$text</$_removedTag>');
        beforePos += text.length;
      case TextDiffOp.added:
        if (!_isPlainTextRange(fullAfter, afterPos, afterPos + text.length)) {
          return null;
        }
        out.write('<$_addedTag>$text</$_addedTag>');
        afterPos += text.length;
    }
  }
  if (!visibleChange) return null;
  out.write(contextAfter);
  return out.toString();
}

/// אופן ההצעה: טקסט חלופי או מחיקה מכוונת ("").
///
/// אין מצב "ללא הצעה": הצעת תיקון בלי הצעה היא בעצם דיווח חופשי, ולכן מי שאין לו
/// הצעה בוחר "דיווח חופשי".
enum ProposalMode { replace, delete }

/// מצב העורך: ההצעה הנוכחית ושגיאה שחוסמת שליחה (null = תקין).
class TextCorrectionDraft {
  final TextCorrection correction;
  final String? error;
  final String? editedText;
  final ProposalMode? mode;

  const TextCorrectionDraft({
    required this.correction,
    this.error,
    this.editedText,
    this.mode,
  });

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
  };
  final correction = original.withProposedText(proposed);
  String? error;
  if (hasLoneSurrogate(original.originalLine) || hasLoneSurrogate(proposed)) {
    error = ReportMessages.invalidCharacters;
  } else if (original.originalLine.length > max) {
    error = ReportMessages.originalTooLong(max);
  } else if (proposed.length > max) {
    error = ReportMessages.proposalTooLong(max);
  } else if (proposed == original.target) {
    error = ReportMessages.proposalIdentical;
  }
  return TextCorrectionDraft(
    correction: correction,
    error: error,
    editedText: editedText,
    mode: mode,
  );
}

/// עורך הצעת תיקון: המקור מוצג בנפרד ואינו ניתן לעריכה, ושדה העריכה נטען
/// מראש בעותק שלו. כל שינוי מדווח דרך [onChanged].
class TextCorrectionEditor extends StatefulWidget {
  final TextCorrection original;
  final double fontSize;
  final ValueChanged<TextCorrectionDraft> onChanged;

  /// נטען מההצעה שב-[original] (עריכת דיווח שמור) במקום מהטקסט המקורי.
  final bool restoreProposal;

  /// Unvalidated local draft state, including the text hidden by delete mode.
  final String? initialText;
  final ProposalMode? initialMode;

  const TextCorrectionEditor({
    super.key,
    required this.original,
    required this.fontSize,
    required this.onChanged,
    this.restoreProposal = false,
    this.initialText,
    this.initialMode,
  });

  @override
  State<TextCorrectionEditor> createState() => _TextCorrectionEditorState();
}

class _TextCorrectionEditorState extends State<TextCorrectionEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText ?? _restoredText ?? widget.original.target,
  );
  // דיווח שמור מגרסה קודמת עם "ללא הצעה" (null) נפתח בעריכת טקסט.
  late ProposalMode _mode =
      widget.initialMode ??
      (widget.restoreProposal && widget.original.proposedText == ''
          ? ProposalMode.delete
          : ProposalMode.replace);
  bool _showSource = false;

  String? get _restoredText {
    final proposed = widget.original.proposedText;
    return widget.restoreProposal && proposed != null && proposed.isNotEmpty
        ? proposed
        : null;
  }

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
        fontFamily: AppFonts.renderFontFamily(
          Settings.getValue<String>(SettingsRepository.keyFontFamily) ??
              AppFonts.defaultFont,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = _textStyle(context);
    final original = widget.original;
    final sourceDirection = reportContentDirection(
      original.originalLine,
      isHtml: true,
    );
    final errorText = draft.error == null
        ? null
        : reportFeedbackText(context, draft.error!);
    final hasMarkup = hasRenderableMarkup(original.originalLine);
    final rendered = hasMarkup && !_showSource;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.settingsText('טקסט המקור (לא ניתן לעריכה):'),
                style: TextStyle(
                  fontSize: AppTokens.fontMD,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ),
            if (hasMarkup)
              AppSegmentedControl<bool>(
                key: const ValueKey('correction-view-toggle'),
                options: [
                  SegmentOption(
                    value: false,
                    label: context.settingsText('כמו בספר'),
                    icon: FluentIcons.book_open_24_regular,
                  ),
                  SegmentOption(
                    value: true,
                    label: context.settingsText('קוד מקור'),
                    icon: FluentIcons.code_24_regular,
                  ),
                ],
                currentValue: _showSource,
                onChanged: (value) => setState(() => _showSource = value),
              ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceSM),
        Container(
          key: const ValueKey('correction-original'),
          constraints: const BoxConstraints(maxHeight: 150),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: AppTokens.borderRadiusAll,
          ),
          child: SingleChildScrollView(
            child: rendered
                ? CorrectionHtml(
                    html: markTargetInHtml(
                      original.originalLine,
                      original.selectionStart ?? 0,
                      original.selectionEnd ?? original.originalLine.length,
                    ),
                    style: textStyle,
                    direction: sourceDirection,
                  )
                : Text.rich(
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
                    textDirection: sourceDirection,
                  ),
          ),
        ),
        if (!original.hasSelection) ...[
          const SizedBox(height: 4),
          Text(
            context.settingsText(ReportMessages.correctionWholeLineNotice),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 8),
        AppSegmentedControl<ProposalMode>(
          options: [
            SegmentOption(
              value: ProposalMode.replace,
              label: context.settingsText('טקסט מוצע'),
              icon: FluentIcons.edit_24_regular,
            ),
            SegmentOption(
              value: ProposalMode.delete,
              label: context.settingsText('מחיקת הקטע'),
              icon: FluentIcons.delete_24_regular,
            ),
          ],
          currentValue: _mode,
          onChanged: _setMode,
          expandToFillWidth: true,
        ),
        const SizedBox(height: 8),
        if (hasMarkup && _mode == ProposalMode.replace) ...[
          Text(
            context.settingsText(
              'שדה העריכה מציג את קוד המקור, כולל תגיות העיצוב. "כמו בספר" מראה איך השורה והשינוי ייראו בספר.',
            ),
            key: const ValueKey('correction-source-explanation'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTokens.spaceXS),
        ],
        if (_mode == ProposalMode.replace)
          Directionality(
            textDirection: sourceDirection,
            child: RtlTextField(
              key: const ValueKey('correction-proposal-field'),
              controller: _controller,
              autofocus: true,
              minLines: 2,
              maxLines: null,
              style: textStyle,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: colorScheme.brightness == Brightness.dark
                    ? colorScheme.surfaceContainerHighest
                    : AppSurfaces.card(context),
                labelText: context.settingsText('הנוסח המתוקן'),
                errorText: errorText,
                errorMaxLines: 3,
                helperText:
                    '${_controller.text.length} / ${TextCorrection.maxTextLength}',
              ),
            ),
          )
        else if (draft.error != null)
          Text(
            errorText!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
            ),
          ),
        if (draft.hasProposal && draft.error == null) ...[
          const SizedBox(height: 8),
          Text(
            context.settingsText('השינוי המוצע:'),
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
            renderHtml: rendered,
            contextBefore: original.contextBefore,
            contextAfter: original.contextAfter,
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

  /// מציג כמו בספר, עם ההקשר; שינוי שנוגע בתגית מוצג כקוד מקור.
  final bool renderHtml;
  final String contextBefore;
  final String contextAfter;

  const TextCorrectionDiffView({
    super.key,
    required this.before,
    required this.after,
    required this.style,
    this.renderHtml = false,
    this.contextBefore = '',
    this.contextAfter = '',
  });

  /// מעבר לזה השינוי עלול להיות מחוץ לתיבה הנגללת, ולכן מרונדר בלי הקשר.
  static const int _maxRenderedContext = 300;

  @override
  Widget build(BuildContext context) {
    final withContext =
        contextBefore.length + contextAfter.length <= _maxRenderedContext;
    final html = renderHtml
        ? correctionDiffHtml(
            before: before,
            after: after,
            contextBefore: withContext ? contextBefore : '',
            contextAfter: withContext ? contextAfter : '',
          )
        : null;
    if (!renderHtml || html != null) return _box(context, html);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _box(context, null),
        const SizedBox(height: AppTokens.spaceXS),
        Text(
          context.settingsText(
            'השינוי נוגע בתגיות העיצוב או ברווחים בלבד, ולכן הוא מוצג כקוד מקור.',
          ),
          key: const ValueKey('correction-diff-source-notice'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _box(BuildContext context, String? html) {
    final colorScheme = Theme.of(context).colorScheme;
    final segments = html == null
        ? computeTextDiff(before, after)
        : const <TextDiffSegment>[];
    final direction = reportContentDirection(
      before.isEmpty ? after : before,
      isHtml: true,
    );
    return Container(
      constraints: const BoxConstraints(maxHeight: 150),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: SingleChildScrollView(
        child: html != null
            ? CorrectionHtml(html: html, style: style, direction: direction)
            : Text.rich(
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
                textDirection: direction,
              ),
      ),
    );
  }
}

/// שורת ספר מרונדרת כמו בקורא, עם סימוני היעד וההבדל בצבעי ה-theme.
class CorrectionHtml extends StatelessWidget {
  final String html;
  final TextStyle style;
  final TextDirection direction;

  const CorrectionHtml({
    super.key,
    required this.html,
    required this.style,
    required this.direction,
  });

  static String _css(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  static final _markTags = RegExp(
    '<(/?)($_targetTag|$_removedTag|$_addedTag)>',
  );

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final styles = {
      _targetTag:
          'font-weight:bold;background-color:${_css(colorScheme.secondaryContainer)}',
      _removedTag:
          'text-decoration:line-through;color:${_css(colorScheme.onErrorContainer)};background-color:${_css(colorScheme.errorContainer)}',
      _addedTag:
          'font-weight:bold;color:${_css(colorScheme.onPrimaryContainer)};background-color:${_css(colorScheme.primaryContainer)}',
    };
    final marked = html.replaceAllMapped(
      _markTags,
      (match) =>
          match[1] == '/' ? '</span>' : '<span style="${styles[match[2]]}">',
    );
    final processed = TextRendererService.prepareInlineMarkers(
      marked,
      unhighlighted: html.replaceAll(_markTags, ''),
    );
    return Directionality(
      textDirection: direction,
      child: RaisedMarkerOverlay.wrap(
        context: context,
        markers: RaisedMarkers.extract(processed),
        baseStyle: style,
        child: HtmlWidget(
          processed,
          textStyle: style,
          factoryBuilder: OtzariaWidgetFactory.new,
          // קישורים בשורה מובילים לספרים; בתוך דיווח הם לקריאה בלבד.
          onTapUrl: (_) => true,
          customStylesBuilder: (element) => smartTextElementCss(
            element.localName,
            element.classes,
            hasHref: element.attributes.containsKey('href'),
            fontFamily: style.fontFamily,
            linkColorCss: _css(AppSurfaces.readerLink(colorScheme)),
            headingColorCss: _css(colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
