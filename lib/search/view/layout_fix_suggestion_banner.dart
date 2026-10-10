import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/search/utils/hebrew_layout_suggestion.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/app_tokens.dart';

/// באנר "האם התכוונת ל..." לטקסט שהוקלד בעברית במצב מקלדת אנגלי
/// (issue #975). מוצג רק כשההמרה לפי מיקום המקשים מניבה טקסט עברי, ואינו
/// משנה דבר בעצמו — לחיצה על ההצעה היא שמפעילה את [onAccept] עם הטקסט
/// המומר. הטקסט של המשתמש לעולם לא מוחלף אוטומטית.
///
/// חשוב להזין לכאן את הטקסט *הגולמי* מהשדה ולא שאילתה מנורמלת: פסיק
/// ונקודה הם המקשים של ת ו-ץ, ונרמול החיפוש מוחק אותם — ההצעה תצא חסרה.
class LayoutFixSuggestionBanner extends StatelessWidget {
  /// הטקסט שהוקלד, כמות שהוא.
  final String query;

  /// נקרא עם הטקסט המומר כשהמשתמש לוחץ על ההצעה.
  final ValueChanged<String> onAccept;

  /// הסבר קצר על תוצאת הלחיצה, מוצג בקצה השורה (אופציונלי).
  final String? hint;

  /// צומת פוקוס ל-InkWell — מאפשר למארח להקפיץ את הפוקוס להצעה (Tab
  /// מהשדה) ולהפעיל אותה ב-Enter/רווח.
  final FocusNode? focusNode;

  const LayoutFixSuggestionBanner({
    super.key,
    required this.query,
    required this.onAccept,
    this.hint,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    if (SettingsTextScope.languageOf(context) != SettingsLanguage.hebrew) {
      return const SizedBox.shrink();
    }
    final suggestion = suggestHebrewKeyboardFix(query);
    if (suggestion == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.tertiaryContainer,
      // Enter על ההצעה מפעיל אותה כאן ונעצר: מארח שמגיש ב-Enter (דיאלוג
      // החיפוש) היה מריץ אחרת את הטקסט השגוי במקום להחיל את ההצעה.
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        },
        child: InkWell(
          focusNode: focusNode,
          onTap: () => onAccept(suggestion),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 6.0,
            ),
            child: Row(
              children: [
                Icon(
                  FluentIcons.keyboard_24_regular,
                  size: 16,
                  color: cs.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(fontSize: 13, color: cs.onSurface),
                      children: [
                        const TextSpan(text: 'האם התכוונת לחפש: '),
                        TextSpan(
                          text: suggestion,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                            decoration: TextDecoration.underline,
                            decorationColor: cs.primary,
                          ),
                        ),
                        const TextSpan(text: '?'),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(width: AppTokens.spaceSM),
                  Text(
                    hint!,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// הצעת תיקון-מקלדת חיה תוך כדי הקלדה: מאזינה ל-[controller] ומציגה את
/// הבאנר כשהטקסט הנוכחי נראה כהקלדה עברית במצב אנגלי. לחיצה מחליפה את
/// תוכן השדה בהצעה (הסמן בסופה) וקוראת ל-[onApplied] — שם המסך המארח
/// מרענן את החיפוש החי שלו. ההחלפה נעשית רק בלחיצה, לעולם לא אוטומטית.
///
/// נגישות מקלדת (בסגנון הצעות האיות של Gmail): כשמסופק [fieldFocusNode],
/// Tab בתוך השדה — בזמן שההצעה מוצגת — מעביר את הפוקוס להצעה, ו-Enter
/// (או רווח) מחיל אותה ומחזיר את הפוקוס לשדה. כשאין הצעה, Tab מתנהג
/// כרגיל.
class TypingLayoutFixSuggestion extends StatefulWidget {
  final TextEditingController controller;

  /// נקרא אחרי שההצעה כבר הוחלה על השדה, עם הטקסט המומר.
  final ValueChanged<String>? onApplied;

  final String? hint;

  /// צומת הפוקוס של שדה הטקסט המלווה — ליירוט Tab ולהחזרת הפוקוס אחרי
  /// ההחלה. אופציונלי: בלעדיו ההצעה עדיין נגישה בסדר המעבר הרגיל.
  final FocusNode? fieldFocusNode;

  const TypingLayoutFixSuggestion({
    super.key,
    required this.controller,
    this.onApplied,
    this.hint,
    this.fieldFocusNode,
  });

  @override
  State<TypingLayoutFixSuggestion> createState() =>
      _TypingLayoutFixSuggestionState();
}

class _TypingLayoutFixSuggestionState extends State<TypingLayoutFixSuggestion> {
  final FocusNode _suggestionFocus = FocusNode(
    debugLabel: 'layout-fix-suggestion',
  );

  /// ה-handler שהיה על צומת השדה לפנינו — משוחזר ב-dispose, כדי לא לדרוס
  /// התנהגות של מארח אחר.
  FocusOnKeyEventCallback? _previousFieldHandler;

  @override
  void initState() {
    super.initState();
    _attachToField(widget.fieldFocusNode);
  }

  @override
  void didUpdateWidget(TypingLayoutFixSuggestion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fieldFocusNode != widget.fieldFocusNode) {
      _detachFromField(oldWidget.fieldFocusNode);
      _attachToField(widget.fieldFocusNode);
    }
  }

  @override
  void dispose() {
    _detachFromField(widget.fieldFocusNode);
    _suggestionFocus.dispose();
    super.dispose();
  }

  void _attachToField(FocusNode? node) {
    if (node == null) return;
    _previousFieldHandler = node.onKeyEvent;
    node.onKeyEvent = _handleFieldKey;
  }

  void _detachFromField(FocusNode? node) {
    if (node == null) return;
    if (node.onKeyEvent == _handleFieldKey) {
      node.onKeyEvent = _previousFieldHandler;
    }
    _previousFieldHandler = null;
  }

  KeyEventResult _handleFieldKey(FocusNode node, KeyEvent event) {
    // Tab נקי בלבד: Ctrl+Tab (מעבר טאבים), Shift+Tab (מעבר אחורה) וכל
    // צירוף מודיפייר אחר ממשיכים למטפלים הקיימים — לא נוגעים בהם.
    final keyboard = HardwareKeyboard.instance;
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.tab &&
        SettingsTextScope.languageOfStatic(context) ==
            SettingsLanguage.hebrew &&
        !keyboard.isShiftPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed &&
        suggestHebrewKeyboardFix(widget.controller.text) != null &&
        _suggestionFocus.canRequestFocus) {
      _suggestionFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return _previousFieldHandler?.call(node, event) ?? KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => LayoutFixSuggestionBanner(
        query: widget.controller.text,
        hint: widget.hint,
        focusNode: _suggestionFocus,
        onAccept: (suggestion) {
          widget.controller.value = TextEditingValue(
            text: suggestion,
            selection: TextSelection.collapsed(offset: suggestion.length),
          );
          widget.onApplied?.call(suggestion);
          // החלה מהמקלדת משאירה את הפוקוס על באנר שנעלם — חוזרים לשדה.
          widget.fieldFocusNode?.requestFocus();
        },
      ),
    );
  }
}
