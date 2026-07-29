import 'dart:async';
import 'package:otzaria/theme/app_tokens.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/text/rtl_selection_shortcuts.dart';

/// TextField מותאם אישית עם תמיכה מלאה ב-RTL
///
/// מתקן בעיות ידועות ב-Flutter Desktop עם RTL:
/// 1. מקשי החיצים פועלים הפוך (כולל Shift+חיצים)
/// 2. Collapse של Selection בכיוון הנכון
/// 3. נראות מיידית של הסמן בניווט
/// 4. תפריט ההקשר המובנה לא מתאים
/// 5. בעיית autofocus באנדרואיד (המקלדת קופצת ונעלמת)
class RtlTextField extends StatefulWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int? maxLines;
  final int? minLines;
  final bool enabled;
  final TextStyle? style;
  final TextAlign textAlign;
  final TextAlignVertical? textAlignVertical;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;
  final Color? cursorColor;

  const RtlTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.minLines,
    this.enabled = true,
    this.style,
    this.textAlign = TextAlign.start,
    this.textAlignVertical,
    this.inputFormatters,
    this.obscureText = false,
    this.cursorColor,
  });

  @override
  State<RtlTextField> createState() => _RtlTextFieldState();
}

class _RtlTextFieldState extends State<RtlTextField> {
  /// חצי-מחזור הבהוב (תואם ל-_kCursorBlinkHalfPeriod של Flutter).
  static const Duration _blinkHalfPeriod = Duration(milliseconds: 500);

  /// משך ההבהוב מאז הפעולה האחרונה; אחריו הסמן נעלם עד הפעולה הבאה.
  static const Duration _blinkTimeout = Duration(seconds: 8);

  late TextEditingController _effectiveController;
  late FocusNode _effectiveFocusNode;

  Timer? _blinkTimer;
  int _blinkTicks = 0;
  bool _cursorVisible = true;

  @override
  void initState() {
    super.initState();

    _effectiveController = widget.controller ?? TextEditingController();
    // FocusNode פנימי דרוש לניהול ההבהוב לפי מצב הפוקוס
    _effectiveFocusNode = widget.focusNode ?? FocusNode();

    _effectiveController.addListener(_restartCursorBlink);
    _effectiveFocusNode.addListener(_handleFocusChange);

    // תיקון לבעיית autofocus באנדרואיד
    // במקום להשתמש ב-autofocus: true ישירות, נבקש פוקוס אחרי שהמסך נבנה
    if (widget.autofocus && widget.focusNode != null && Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.focusNode != null) {
          widget.focusNode!.requestFocus();
        }
      });
    }
  }

  @override
  void didUpdateWidget(RtlTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // עדכון controller אם השתנה
    if (widget.controller != oldWidget.controller) {
      _effectiveController.removeListener(_restartCursorBlink);
      _effectiveController = widget.controller ?? TextEditingController();
      _effectiveController.addListener(_restartCursorBlink);
    }
    // עדכון focusNode אם השתנה
    if (widget.focusNode != oldWidget.focusNode) {
      _effectiveFocusNode.removeListener(_handleFocusChange);
      if (oldWidget.focusNode == null) {
        _effectiveFocusNode.dispose();
      }
      _effectiveFocusNode = widget.focusNode ?? FocusNode();
      _effectiveFocusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _effectiveController.removeListener(_restartCursorBlink);
    _effectiveFocusNode.removeListener(_handleFocusChange);
    // נקה controller/focusNode רק אם יצרנו אותם
    if (widget.controller == null) {
      _effectiveController.dispose();
    }
    if (widget.focusNode == null) {
      _effectiveFocusNode.dispose();
    }
    super.dispose();
  }

  // ניהול הבהוב הסמן: ההבהוב המובנה מנוטרל (debugDeterministicCursor, ראו
  // main.dart) ומוחלף בהחלפת cursorColor — מתאפס בכל פעולה ונעצר אחרי timeout.

  void _handleFocusChange() {
    if (_effectiveFocusNode.hasFocus) {
      _restartCursorBlink();
    } else {
      _stopCursorBlink();
    }
  }

  /// מציג את הסמן מיידית ומתחיל מחזור הבהוב חדש.
  void _restartCursorBlink() {
    if (!_effectiveFocusNode.hasFocus) return;
    _blinkTimer?.cancel();
    _blinkTicks = 0;
    _setCursorVisible(true);
    _blinkTimer = Timer.periodic(_blinkHalfPeriod, _onBlinkTick);
  }

  void _stopCursorBlink() {
    _blinkTimer?.cancel();
    _blinkTimer = null;
    _setCursorVisible(false);
  }

  void _onBlinkTick(Timer timer) {
    _blinkTicks++;
    if (_blinkHalfPeriod * _blinkTicks >= _blinkTimeout) {
      _stopCursorBlink(); // תמה תקופת ההבהוב — הסמן נעלם
      return;
    }
    _setCursorVisible(!_cursorVisible);
  }

  void _setCursorVisible(bool visible) {
    if (visible == _cursorVisible) return;
    setState(() => _cursorVisible = visible);
  }

  @override
  Widget build(BuildContext context) {
    final bool isRtl = Directionality.of(context) == TextDirection.rtl;

    // באנדרואיד, לא משתמשים ב-autofocus ישירות אלא דרך requestFocus ב-initState
    final shouldUseAutofocus =
        widget.autofocus && (widget.focusNode == null || !Platform.isAndroid);

    Widget textField = TextField(
      controller: _effectiveController,
      focusNode: _effectiveFocusNode,
      decoration: widget.decoration,
      contextMenuBuilder: (context, editableTextState) =>
          const SizedBox.shrink(),
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      autofocus: shouldUseAutofocus,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      enabled: widget.enabled,
      style: widget.style,
      textAlign: widget.textAlign,
      textAlignVertical: widget.textAlignVertical,
      inputFormatters: widget.inputFormatters,
      obscureText: widget.obscureText,
      cursorWidth: 1.0, // דק יותר מברירת המחדל (2.0)
      // שקוף בשלב ה"כבוי" של ההבהוב ולאחר שנעצר (ראו ניהול ההבהוב למעלה)
      cursorColor: _cursorVisible ? widget.cursorColor : Colors.transparent,
    );

    // עטיפה בתיקון חיצים אם RTL
    // שימוש ב-CallbackShortcuts כדי להבטיח קדימות על פני ה-TextField
    if (isRtl) {
      // רמת מילה: Ctrl ב-Windows/Linux, Alt ב-macOS/iOS — תואם למיפוי
      // הפלטפורמה של Flutter (ב-Windows/Linux Alt+חץ שמור לקפיצת שורה).
      final wordByAlt = usesAltForWordNavigation();
      textField = CallbackShortcuts(
        bindings: {
          // חיצים רגילים (ללא Shift)
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _handleArrowKey(isVisualRight: false, extendSelection: false),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _handleArrowKey(isVisualRight: true, extendSelection: false),

          // Shift+חיצים (בחירה ברמת תו)
          const SingleActivator(
            LogicalKeyboardKey.arrowLeft,
            shift: true,
          ): () =>
              _handleArrowKey(isVisualRight: false, extendSelection: true),
          const SingleActivator(
            LogicalKeyboardKey.arrowRight,
            shift: true,
          ): () =>
              _handleArrowKey(isVisualRight: true, extendSelection: true),

          // Ctrl/Alt+חיצים (הזזת סמן ברמת מילה)
          SingleActivator(
            LogicalKeyboardKey.arrowLeft,
            control: !wordByAlt,
            alt: wordByAlt,
          ): () => _handleArrowKey(
            isVisualRight: false,
            extendSelection: false,
            byWord: true,
          ),
          SingleActivator(
            LogicalKeyboardKey.arrowRight,
            control: !wordByAlt,
            alt: wordByAlt,
          ): () => _handleArrowKey(
            isVisualRight: true,
            extendSelection: false,
            byWord: true,
          ),

          // Ctrl/Alt+Shift+חיצים (בחירה ברמת מילה)
          SingleActivator(
            LogicalKeyboardKey.arrowLeft,
            shift: true,
            control: !wordByAlt,
            alt: wordByAlt,
          ): () => _handleArrowKey(
            isVisualRight: false,
            extendSelection: true,
            byWord: true,
          ),
          SingleActivator(
            LogicalKeyboardKey.arrowRight,
            shift: true,
            control: !wordByAlt,
            alt: wordByAlt,
          ): () => _handleArrowKey(
            isVisualRight: true,
            extendSelection: true,
            byWord: true,
          ),
        },
        child: textField,
      );
    }

    // עטיפה בטיפול בתפריט הקשר
    return Listener(
      onPointerDown: (event) {
        if (event.buttons == 2) {
          _showContextMenu(context, event.position, _effectiveController);
        }
      },
      child: textField,
    );
  }

  /// מטפל בלחיצת חץ ב-RTL: מאציל ל-Actions המובנים עם כיוון מהופך
  /// (ויזואלית-שמאל = forward), מה שמתקן את באג הכיווניות של Flutter.
  void _handleArrowKey({
    required bool isVisualRight,
    required bool extendSelection,
    bool byWord = false,
  }) {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return;

    if (byWord) {
      Actions.invoke(
        focusContext,
        ExtendSelectionToNextWordBoundaryIntent(
          forward: !isVisualRight,
          collapseSelection: !extendSelection,
        ),
      );
    } else {
      Actions.invoke(
        focusContext,
        ExtendSelectionByCharacterIntent(
          forward: !isVisualRight,
          collapseSelection: !extendSelection,
        ),
      );
    }
  }

  void _showContextMenu(
    BuildContext context,
    Offset position,
    TextEditingController controller,
  ) {
    final selection = controller.selection;
    final textAtMenuOpen = controller.text;
    final hasSelection = selection.isValid && !selection.isCollapsed;

    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    List<PopupMenuEntry<String>> menuItems = [];

    if (hasSelection) {
      menuItems.addAll([
        _buildMenuItem(context, 'cut', 'גזור', FluentIcons.cut_24_regular),
        _buildMenuItem(context, 'copy', 'העתק', FluentIcons.copy_24_regular),
      ]);
    }

    menuItems.add(
      _buildMenuItem(
        context,
        'paste',
        'הדבק',
        FluentIcons.clipboard_paste_24_regular,
      ),
    );

    if (controller.text.isNotEmpty) {
      menuItems.addAll([
        const PopupMenuDivider(height: 8),
        _buildMenuItem(
          context,
          'selectAll',
          'בחר הכל',
          FluentIcons.select_all_on_24_regular,
        ),
      ]);
    }

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: menuItems,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: AppTokens.borderRadiusAll),
      color: Theme.of(context).colorScheme.surface,
    ).then((value) async {
      if (value == null) return;

      // שימוש ב-selection שנלכדה בפתיחת התפריט: לחיצה ימנית בלי פוקוס
      // מכווצת אותה אסינכרונית ברקע (secondary tap המובנה של Flutter).
      final currentText = controller.text;
      final currentSelection = currentText == textAtMenuOpen
          ? selection
          : controller.selection;
      if (!currentSelection.isValid ||
          currentSelection.end > currentText.length) {
        return;
      }

      switch (value) {
        case 'cut':
          final selectedText = currentText.substring(
            currentSelection.start,
            currentSelection.end,
          );
          await Clipboard.setData(ClipboardData(text: selectedText));
          final textAfterCut =
              currentText.substring(0, currentSelection.start) +
              currentText.substring(currentSelection.end);
          controller.text = textAfterCut;
          controller.selection = TextSelection.collapsed(
            offset: currentSelection.start,
          );
          // עדכון ידני: הקצאה ישירה ל-controller.text לא מפעילה את onChanged
          // של TextField (זה מגיע רק מנתיב הקלט הפנימי של EditableText).
          widget.onChanged?.call(textAfterCut);
          break;
        case 'copy':
          final selectedText = currentText.substring(
            currentSelection.start,
            currentSelection.end,
          );
          await Clipboard.setData(ClipboardData(text: selectedText));
          break;
        case 'paste':
          final data = await Clipboard.getData('text/plain');
          if (data?.text != null) {
            final newText =
                currentText.substring(0, currentSelection.start) +
                data!.text! +
                currentText.substring(currentSelection.end);
            controller.text = newText;
            controller.selection = TextSelection.collapsed(
              offset: currentSelection.start + data.text!.length,
            );
            // עדכון ידני: הקצאה ישירה ל-controller.text לא מפעילה את onChanged
            // של TextField (זה מגיע רק מנתיב הקלט הפנימי של EditableText).
            widget.onChanged?.call(newText);
          }
          break;
        case 'selectAll':
          controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: currentText.length,
          );
          break;
      }
    });
  }

  PopupMenuItem<String> _buildMenuItem(
    BuildContext context,
    String value,
    String label,
    IconData icon,
  ) {
    return PopupMenuItem<String>(
      value: value,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurface),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 14),
            textDirection: TextDirection.rtl,
          ),
        ],
      ),
    );
  }
}
