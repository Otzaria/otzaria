import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/widgets/layout/tool_result_card_shell.dart';

/// מבקש חיפוש של [text] בכיוון הנתון.
typedef AramaicSearchRequest =
    void Function(String text, {required bool hebrewToAramaic});

class AramaicResultCard extends StatelessWidget {
  /// [query] הוא טקסט החיפוש המנורמל, להדגשה: בכותרת כשהחיפוש ארמי,
  /// ובפירושים כשהוא עברי.
  const AramaicResultCard({
    super.key,
    required this.aramaic,
    required this.hebrew,
    this.query = '',
    this.queryIsAramaic = true,
    this.onSearch,
  });

  final String aramaic;
  final String hebrew;
  final String query;
  final bool queryIsAramaic;
  final AramaicSearchRequest? onSearch;

  static final RegExp _quotes = RegExp("[\"'״׳]");
  static final RegExp _alternativeSeparator = RegExp(r'[,;\n]');
  static final RegExp _parenthetical = RegExp(r'\([^)]*\)');

  static const String _copyWithResultTooltip = 'העתק את הערך עם התוצאה';

  static String _plain(String text) =>
      removeVolwels(text).replaceAll(_quotes, '').trim();

  static final RegExp _listBullet = RegExp(r'^•\s*', multiLine: true);

  /// המונח הראשון בפירוש, לחיפוש הפוך ("ארץ, קרקע" -> "ארץ"). פירוש מרובה
  /// שורות או נקודות רשימה נמדד לפי השורה הראשונה, בלי הנקודה.
  static String searchTermOf(String meaning) {
    final withoutNotes = meaning
        .replaceAll(_parenthetical, ' ')
        .replaceAll(_listBullet, '');
    return withoutNotes
        .split(_alternativeSeparator)
        .map((part) => removeVolwels(part).trim())
        .firstWhere((part) => part.isNotEmpty, orElse: () => '');
  }

  /// פירושים להצגה: פירוש שכל חלקיו כבר הופיעו קודם (בערך אחר) מדולג.
  @visibleForTesting
  static List<ParsedAramaicMeaning> visibleMeanings(String hebrew) =>
      AramaicDictionaryEntryPresentation.parse(
        hebrew,
      ).withoutRepeatedMeanings().meanings;

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    UiSnack.show(UiSnack.textCopied);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final meanings = visibleMeanings(hebrew);
    final headwordPlain = _plain(aramaic);
    final vocalized = meanings
        .map((m) => m.expression)
        .whereType<String>()
        .where((e) => e != aramaic && _plain(e) == headwordPlain)
        .firstOrNull;
    final highlight = TextStyle(
      backgroundColor: cs.primaryContainer,
      color: cs.onPrimaryContainer,
    );

    return _HoverBuilder(
      builder: (context, hovering) => ToolResultCardShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppTokens.spaceMD - 4,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: _highlighted(
                            aramaic,
                            queryIsAramaic ? query : '',
                            highlight,
                          ),
                        ),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (vocalized != null)
                        Text(
                          vocalized,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!queryIsAramaic && onSearch != null)
                  _ActionButton(
                    visible: hovering,
                    icon: OtzariaIcons.search_24_regular,
                    tooltip: context.settingsText(
                      'חפש "{term}" בארמית',
                      args: {'term': aramaic},
                    ),
                    onPressed: () => onSearch!(aramaic, hebrewToAramaic: false),
                  ),
                if (queryIsAramaic)
                  _ActionButton(
                    visible: hovering,
                    icon: FluentIcons.copy_add_24_regular,
                    tooltip: context.settingsText(_copyWithResultTooltip),
                    onPressed: () => _copy(_entryAsText(meanings)),
                  ),
                _ActionButton(
                  visible: hovering,
                  icon: FluentIcons.copy_24_regular,
                  tooltip: context.settingsText('העתק את הערך'),
                  onPressed: () => _copy(aramaic),
                ),
              ],
            ),
            Divider(
              height: AppTokens.spaceMD,
              color: cs.outlineVariant,
            ),
            for (var i = 0; i < meanings.length; i++)
              _MeaningRow(
                showActions: hovering,
                meaning: meanings[i],
                number: meanings.length > 1 ? i + 1 : null,
                headwordPlain: headwordPlain,
                query: queryIsAramaic ? '' : query,
                highlight: highlight,
                onCopy: () => _copy(meanings[i].text),
                onCopyWithEntry: queryIsAramaic
                    ? null
                    : () => _copy('$aramaic\n${meanings[i].text}'),
                onSearch: queryIsAramaic && onSearch != null
                    ? () {
                        final term = searchTermOf(meanings[i].hebrewText);
                        if (term.isNotEmpty) {
                          onSearch!(term, hebrewToAramaic: true);
                        }
                      }
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  String _entryAsText(List<ParsedAramaicMeaning> meanings) {
    final lines = [
      for (var i = 0; i < meanings.length; i++)
        meanings.length > 1
            ? '${i + 1}. ${meanings[i].text}'
            : meanings[i].text,
    ];
    return '$aramaic\n${lines.join('\n')}';
  }
}

class _MeaningRow extends StatelessWidget {
  const _MeaningRow({
    required this.showActions,
    required this.meaning,
    required this.number,
    required this.headwordPlain,
    required this.query,
    required this.highlight,
    required this.onCopy,
    required this.onCopyWithEntry,
    required this.onSearch,
  });

  final bool showActions;
  final ParsedAramaicMeaning meaning;
  final int? number;
  final String headwordPlain;
  final String query;
  final TextStyle highlight;
  final VoidCallback onCopy;
  final VoidCallback? onCopyWithEntry;
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final expression = meaning.expression;
    final showExpression =
        expression != null &&
        AramaicResultCard._plain(expression) != headwordPlain;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (number != null)
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              margin: const EdgeInsetsDirectional.only(
                end: AppTokens.spaceSM + 2,
                top: 6,
              ),
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: AppTokens.borderRadiusAll,
              ),
              child: Text(
                '$number',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showExpression)
                    Text(
                      expression,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  if (meaning.mainText.isNotEmpty)
                    Text.rich(
                      TextSpan(
                        children: _withBold(
                          meaning.mainText,
                          query,
                          highlight,
                        ),
                      ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  if (meaning.expansion != null)
                    Text(
                      meaning.expansion!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (onSearch != null)
            _ActionButton(
              visible: showActions,
              icon: OtzariaIcons.search_24_regular,
              tooltip: context.settingsText('חפש בעברית'),
              onPressed: onSearch!,
            ),
          if (onCopyWithEntry != null)
            _ActionButton(
              visible: showActions,
              icon: FluentIcons.copy_add_24_regular,
              tooltip: context.settingsText(
                AramaicResultCard._copyWithResultTooltip,
              ),
              onPressed: onCopyWithEntry!,
            ),
          _ActionButton(
            visible: showActions,
            icon: FluentIcons.copy_24_regular,
            tooltip: context.settingsText('העתק פירוש'),
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.visible,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final bool visible;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: AppMotion.duration(context, AppTokens.animFast),
      child: IconButton(
        icon: Icon(icon, size: AppTokens.iconSM),
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        onPressed: onPressed,
      ),
    );
  }
}

/// מספק מצב ריחוף; במגע הפעולות תמיד גלויות כי אין ריחוף.
class _HoverBuilder extends StatefulWidget {
  const _HoverBuilder({required this.builder});

  final Widget Function(BuildContext context, bool hovering) builder;

  @override
  State<_HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<_HoverBuilder> {
  bool _hovering = false;

  static bool get _isTouch =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: widget.builder(context, _hovering || _isTouch),
    );
  }
}

/// כמו [_highlighted], ובנוסף מציג מודגש כל קטע שסומן ב-`**`.
List<InlineSpan> _withBold(String text, String query, TextStyle mark) {
  final spans = <InlineSpan>[];
  var copied = 0;
  for (final bold in AramaicDictionaryEntryPresentation.boldMarkup.allMatches(
    text,
  )) {
    if (bold.start > copied) {
      spans.addAll(
        _highlighted(text.substring(copied, bold.start), query, mark),
      );
    }
    spans.add(
      TextSpan(
        children: _highlighted(bold[1]!, query, mark),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
    copied = bold.end;
  }
  if (copied == 0) return _highlighted(text, query, mark);
  if (copied < text.length) {
    spans.addAll(_highlighted(text.substring(copied), query, mark));
  }
  return spans;
}

bool _isIgnorable(int unit) =>
    unit >= 0x0591 && unit <= 0x05C7 && unit != 0x05BE && unit != 0x05C0;

/// מפצל את [text] לקטעים ומסמן ב-[mark] כל מופע של [query] (טקסט בלי ניקוד
/// וגרשיים), גם כשהטקסט עצמו מנוקד.
List<InlineSpan> _highlighted(String text, String query, TextStyle mark) {
  if (query.isEmpty) return [TextSpan(text: text)];

  final plain = StringBuffer();
  final origin = <int>[];
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (_isIgnorable(unit) || AramaicResultCard._quotes.hasMatch(text[i])) {
      continue;
    }
    final isSeparator = unit == 0x05BE || unit == 0x05C0 || unit == 0x7C;
    plain.write(isSeparator ? ' ' : text[i]);
    origin.add(i);
  }

  final plainText = plain.toString();
  final spans = <InlineSpan>[];
  var copied = 0;
  var from = 0;
  while (true) {
    final start = plainText.indexOf(query, from);
    if (start < 0) break;

    final first = origin[start];
    var end = origin[start + query.length - 1] + 1;
    while (end < text.length && _isIgnorable(text.codeUnitAt(end))) {
      end++;
    }
    if (first > copied) {
      spans.add(TextSpan(text: text.substring(copied, first)));
    }
    spans.add(TextSpan(text: text.substring(first, end), style: mark));
    copied = end;
    from = start + query.length;
  }
  if (copied < text.length) spans.add(TextSpan(text: text.substring(copied)));
  return spans.isEmpty ? [TextSpan(text: text)] : spans;
}
