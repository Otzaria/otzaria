import 'dart:async';
import 'package:otzaria/theme/app_tokens.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/text/rtl_hard_break_workaround.dart';
import 'package:otzaria/widgets/text/rtl_selection_shortcuts.dart';

/// שדה קלט עם ניווט, בחירה ותפריט הקשר מותאמים ל-RTL.
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
  final ScrollController? scrollController;

  /// ממלא את הגובה הזמין. מחייב `maxLines: null` ו-`minLines: null`.
  final bool expands;

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
    this.scrollController,
    this.expands = false,
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

  // שדה רב-שורתי: ה-TextField מקבל עותק עם \r\n (rtl_hard_break_workaround),
  // ו-_effectiveController נשאר עם \n בלבד — זה מה שהאפליקציה רואה.
  TextEditingController? _rawController;
  final _expandMapper = HardBreakValueMapper(expand: true);
  final _collapseMapper = HardBreakValueMapper(expand: false);
  int _rawSyncDepth = 0;
  late String _lastChangedText;

  bool get _hardBreakWorkaroundActive => _rawController != null;

  /// ה-controller שבאמת מוזן ל-TextField (ושאליו מתייחסים ניווט/בחירה
  /// פנימיים) — הגולמי כשהעוקף פעיל, אחרת ה-controller הרגיל.
  TextEditingController get _boundController =>
      _rawController ?? _effectiveController;

  Timer? _blinkTimer;
  int _blinkTicks = 0;
  bool _cursorVisible = true;

  @override
  void initState() {
    super.initState();

    _effectiveController = widget.controller ?? TextEditingController();
    // FocusNode פנימי דרוש לניהול ההבהוב לפי מצב הפוקוס
    _effectiveFocusNode = widget.focusNode ?? FocusNode();

    _setUpHardBreakWorkaround();
    _boundController.addListener(_restartCursorBlink);
    _effectiveFocusNode.addListener(_handleFocusChange);

    // גם FocusNode שכבר בפוקוס: Flutter פותח מקלדת רק בשינוי פוקוס.
    if (_effectiveFocusNode.hasPrimaryFocus ||
        (widget.autofocus && widget.focusNode != null && Platform.isAndroid)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editable?.requestKeyboard();
      });
    }
  }

  EditableTextState? get _editable =>
      _effectiveFocusNode.context?.findAncestorStateOfType<EditableTextState>();

  @override
  void didUpdateWidget(RtlTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // עדכון controller ו/או מעבר חד-שורתי↔רב-שורתי: בונים מחדש את העוקף
    // (הגולמי תלוי ב-controller הנוכחי וב-maxLines).
    final controllerChanged = widget.controller != oldWidget.controller;
    final multilineChanged =
        (widget.maxLines != 1) != (oldWidget.maxLines != 1);
    if (controllerChanged || multilineChanged) {
      _boundController.removeListener(_restartCursorBlink);
      _tearDownHardBreakWorkaround();
      if (controllerChanged) {
        if (oldWidget.controller == null) _effectiveController.dispose();
        _effectiveController = widget.controller ?? TextEditingController();
      }
      _setUpHardBreakWorkaround();
      _boundController.addListener(_restartCursorBlink);
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
    _boundController.removeListener(_restartCursorBlink);
    _tearDownHardBreakWorkaround();
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

  void _setUpHardBreakWorkaround() {
    _lastChangedText = _effectiveController.text;
    if (widget.maxLines == 1) return;
    // לא משנים כאן את ה-controller של הקורא: זה רץ בזמן build, ומאזינים שלו
    // היו מופעלים באמצע הבנייה. \r שכבר היה בטקסט ינוקה בפעולה הראשונה בשדה.
    _rawController = TextEditingController.fromValue(
      _expandMapper.map(_effectiveController.value),
    );
    _rawController!.addListener(_syncCleanFromRawLive);
    _effectiveController.addListener(_syncRawFromCleanExternally);
  }

  /// מסיר את עוקף באג-הסמן ומשחרר את ה-controller הגולמי.
  void _tearDownHardBreakWorkaround() {
    if (!_hardBreakWorkaroundActive) return;
    _rawController!.removeListener(_syncCleanFromRawLive);
    _effectiveController.removeListener(_syncRawFromCleanExternally);
    _rawController!.dispose();
    _rawController = null;
  }

  /// מסנכרן גם תזוזת סמן בלבד: קוראים כמו כפתורי העיצוב בעורך הספרים קוראים
  /// את controller.selection ישירות. onChanged מופעל רק כשהטקסט השתנה.
  void _syncCleanFromRawLive() {
    final clean = _collapseMapper.map(
      _rawController!.value,
      matchingText: _effectiveController.text,
    );
    _rawSyncDepth++;
    try {
      if (_effectiveController.value != clean) {
        _effectiveController.value = clean;
      }
    } finally {
      _rawSyncDepth--;
    }
  }

  void _handleRawOnChanged(String rawText) {
    final text = _effectiveController.text;
    if (text == _lastChangedText) return;
    _lastChangedText = text;
    widget.onChanged?.call(text);
  }

  void _handleRawOnSubmitted(String rawText) {
    widget.onSubmitted?.call(_effectiveController.text);
  }

  void _syncRawFromCleanExternally() {
    // השוואת הערכים מאפשרת למאזין חיצוני לתקן עריכה בלי לאבד את התיקון.
    if (_effectiveController.value ==
        _collapseMapper.map(
          _rawController!.value,
          matchingText: _effectiveController.text,
        )) {
      return;
    }
    final clean = _effectiveController.value;
    // כתיבה חיצונית משנה את נקודת הייחוס של onChanged, אך תיקון מאזין
    // במהלך קלט משתמש עדיין חייב להימסר פעם אחת עם הטקסט הסופי.
    if (_rawSyncDepth == 0) _lastChangedText = clean.text;
    final raw = clean.composing.isValid && !clean.composing.isCollapsed
        ? clean
        : _expandMapper.map(clean, matchingText: _rawController!.text);
    if (_rawController!.value != raw) _rawController!.value = raw;
  }

  void _copySelection(
    CopySelectionTextIntent intent, {
    bool fromToolbar = false,
  }) {
    final value = _effectiveController.value;
    final selection = value.selection;
    if (!widget.enabled ||
        widget.obscureText ||
        !selection.isValid ||
        selection.isCollapsed) {
      return;
    }
    unawaited(
      Clipboard.setData(
        ClipboardData(text: selection.textInside(value.text)),
      ).catchError((Object error, StackTrace stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            context: ErrorDescription('בעת העתקת טקסט'),
          ),
        );
      }),
    );
    final editable = _editable;
    if (editable == null) return;
    final raw = _boundController.value;
    if (intent.collapseSelection) {
      editable.userUpdateTextEditingValue(
        raw.replaced(raw.selection, ''),
        intent.cause,
      );
    } else if (fromToolbar) {
      editable.bringIntoView(raw.selection.extent);
      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.fuchsia) {
        editable.userUpdateTextEditingValue(
          raw.copyWith(
            selection: TextSelection.collapsed(offset: raw.selection.end),
            composing: TextRange.empty,
          ),
          SelectionChangedCause.toolbar,
        );
      }
    }
    if (fromToolbar || intent.cause == SelectionChangedCause.toolbar) {
      editable.hideToolbar(false);
    }
    editable.clipboardStatus.update();
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

  PointerDeviceKind? _lastPointerKind;

  @override
  Widget build(BuildContext context) {
    final bool isRtl = Directionality.of(context) == TextDirection.rtl;

    // באנדרואיד, לא משתמשים ב-autofocus ישירות אלא דרך requestFocus ב-initState
    final shouldUseAutofocus =
        widget.autofocus && (widget.focusNode == null || !Platform.isAndroid);

    Widget textField = TextField(
      controller: _boundController,
      scrollController: widget.scrollController,
      expands: widget.expands,
      focusNode: _effectiveFocusNode,
      decoration: widget.decoration,
      contextMenuBuilder: (context, editableTextState) {
        // לחיצה ימנית פותחת את התפריט מה-Listener; במגע Flutter מבקש כאן את
        // התפריט שלו אחרי לחיצה ארוכה, ובמקומו נפתח שלנו.
        if (_lastPointerKind
            case PointerDeviceKind.touch ||
                PointerDeviceKind.stylus ||
                PointerDeviceKind.invertedStylus) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            editableTextState.hideToolbar(false);
            _showContextMenu(
              this.context,
              editableTextState.contextMenuAnchors.primaryAnchor,
              // תפריט שלוקח פוקוס מוחק את ידיות הבחירה, והמקלדת נסגרת ונפתחת.
              requestFocus: false,
            );
          });
        }
        return const SizedBox.shrink();
      },
      // ה-callbacks של TextField מקבלים טקסט עם \r\n; בשדה רב-שורתי
      // onChanged מקבל את הטקסט הנקי אחרי סנכרון ה-controller.
      onChanged: _hardBreakWorkaroundActive
          ? _handleRawOnChanged
          : widget.onChanged,
      onSubmitted: _hardBreakWorkaroundActive
          ? _handleRawOnSubmitted
          : widget.onSubmitted,
      autofocus: shouldUseAutofocus,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      enabled: widget.enabled,
      style: widget.style,
      textAlign: widget.textAlign,
      textAlignVertical: widget.textAlignVertical,
      inputFormatters: _hardBreakWorkaroundActive
          ? ((widget.inputFormatters?.isNotEmpty ?? false)
                ? [CleanSpaceFormatterAdapter(widget.inputFormatters!)]
                : const [HardBreakInputFormatter()])
          : widget.inputFormatters,
      obscureText: widget.obscureText,
      cursorWidth: 1.0, // דק יותר מברירת המחדל (2.0)
      // שקוף בשלב ה"כבוי" של ההבהוב ולאחר שנעצר (ראו ניהול ההבהוב למעלה)
      cursorColor: _cursorVisible ? widget.cursorColor : Colors.transparent,
      // ברירת המחדל max מציירת בטקסט RTL רב-שורתי כל בחירה עד הקצה השמאלי.
      selectionWidthStyle: ui.BoxWidthStyle.tight,
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

    if (_hardBreakWorkaroundActive) {
      textField = Actions(
        actions: {
          CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
            onInvoke: (intent) {
              _copySelection(intent);
              return null;
            },
          ),
        },
        child: textField,
      );
    }

    if (_hardBreakWorkaroundActive) {
      // נגישות מפעילה copySelection ישירות; המיזוג נותן קדימות לפעולות הנקיות.
      textField = AnimatedBuilder(
        animation: Listenable.merge([_boundController, _effectiveFocusNode]),
        child: textField,
        builder: (context, child) {
          final value = _boundController.value;
          final canCopy =
              _effectiveFocusNode.hasFocus &&
              widget.enabled &&
              !widget.obscureText &&
              value.selection.isValid &&
              !value.selection.isCollapsed;
          return MergeSemantics(
            child: Semantics(
              onCopy: canCopy
                  ? () => _copySelection(
                      CopySelectionTextIntent.copy,
                      fromToolbar: true,
                    )
                  : null,
              onCut: canCopy
                  ? () => _copySelection(
                      const CopySelectionTextIntent.cut(
                        SelectionChangedCause.toolbar,
                      ),
                    )
                  : null,
              child: child,
            ),
          );
        },
      );
    }

    // עטיפה בטיפול בתפריט הקשר
    return Listener(
      onPointerDown: (event) {
        _lastPointerKind = event.kind;
        if (event.buttons == 2) {
          _showContextMenu(context, event.position);
        }
      },
      child: textField,
    );
  }

  /// מטפל בלחיצת חץ ב-RTL לפי הסדר החזותי של מיקומי הסמן: החץ חוצה את
  /// הגרפמה שלידו בצד החץ, גם בגבול בין קטע עברי ללטיני (issue #3445).
  void _handleArrowKey({
    required bool isVisualRight,
    required bool extendSelection,
    bool byWord = false,
  }) {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final editable = _editable;
    final selection = _boundController.selection;
    if (focusContext == null || editable == null || !selection.isValid) return;
    final render = editable.renderEditable;

    final TextPosition target;
    if (!extendSelection && !byWord && !selection.isCollapsed) {
      // כמו ב-Flutter: חץ בלי Shift מכווץ את הבחירה, כאן לקצה שבכיוון החץ.
      final start = TextPosition(offset: selection.start);
      final end = TextPosition(
        offset: selection.end,
        affinity: TextAffinity.upstream,
      );
      final s = _caretPoint(render, start);
      final e = _caretPoint(render, end);
      final toEnd = (e.dy - s.dy).abs() > 0.5
          ? !isVisualRight
          : (e.dx < s.dx) != isVisualRight;
      target = toEnd ? end : start;
    } else {
      // ה-affinity השמור, לא זה של extent: בבחירה פתוחה extent נצמד תמיד
      // לטקסט הנבחר, ובגבול בין קטעים זה מיקום חזותי אחר.
      final caret = TextPosition(
        offset: selection.extentOffset,
        affinity: selection.affinity,
      );
      var position = caret;
      final boundary = byWord ? render.wordBoundaries.moveByWordBoundary : null;
      while (true) {
        final step = _crossAdjacentText(
          render,
          position,
          isVisualRight,
          boundary: boundary,
        );
        if (step != null) {
          if (step.useNativeWord) {
            // בטווח מעורב או LTR שנגלש נשמרת פעולת המילה המקורית.
            final index =
                (selection.affinity == TextAffinity.downstream
                        ? selection.extentOffset
                        : selection.extentOffset - 1)
                    .clamp(0, _boundController.text.length - 1);
            final direction = render
                .getBoxesForSelection(
                  TextSelection(baseOffset: index, extentOffset: index + 1),
                )
                .firstOrNull
                ?.direction;
            Actions.invoke(
              focusContext,
              ExtendSelectionToNextWordBoundaryIntent(
                forward: direction == TextDirection.ltr
                    ? isVisualRight
                    : !isVisualRight,
                collapseSelection: !extendSelection,
              ),
            );
            return;
          }
          position = step.position;
        } else {
          final edge = _adjacentLineEdge(render, position, isVisualRight);
          if (edge == null) break;
          final crossedHardBreak = TextSelection(
            baseOffset: position.offset,
            extentOffset: edge.offset,
          ).textInside(_boundController.text).contains('\n');
          position = edge;
          if (byWord && !crossedHardBreak) continue;
        }
        // בבחירה פתוחה Flutter מתעלם משינוי affinity בלבד, גם בגלישת שורה.
        if (!extendSelection || position.offset != caret.offset) break;
      }
      target = position;
    }
    // כמו בתנועה הלוגית: downstream, אלא אם הוא מצויר במקום אחר (גבול קטעים).
    final downstream = TextPosition(offset: target.offset);
    final position =
        (_caretPoint(render, downstream) - _caretPoint(render, target))
                .distance <
            0.5
        ? downstream
        : target;

    Actions.invoke(
      focusContext,
      UpdateSelectionIntent(
        editable.textEditingValue,
        extendSelection
            ? TextSelection(
                baseOffset: selection.baseOffset,
                extentOffset: position.offset,
                affinity: position.affinity,
              )
            : TextSelection.fromPosition(position),
        SelectionChangedCause.keyboard,
      ),
    );
  }

  /// חוצה גרפמה סמוכה, או מתקדם עד [boundary] כשהטווח בעל כיוון אחיד.
  /// null בקצה השורה.
  ({TextPosition position, bool useNativeWord})? _crossAdjacentText(
    RenderEditable render,
    TextPosition caret,
    bool toRight, {
    TextBoundary? boundary,
  }) {
    final text = _boundController.text;
    final from = _caretPoint(render, caret);
    // נקודה בתוך הגרפמה הסמוכה; המיקום שחוזר צמוד לאחד מקצותיה.
    final hit = render.getPositionForPoint(
      render.localToGlobal(
        Offset(
          toRight ? from.dx + render.cursorWidth + 1.5 : from.dx - 1.5,
          from.dy,
        ),
      ),
    );
    final chars = CharacterBoundary(text);
    final after =
        hit.affinity == TextAffinity.downstream && hit.offset < text.length;
    if (!after && hit.offset == 0) return null;
    final grapheme = chars.getTextBoundaryAt(
      after ? hit.offset : hit.offset - 1,
    );
    final box = render
        .getBoxesForSelection(
          TextSelection(baseOffset: grapheme.start, extentOffset: grapheme.end),
        )
        .firstOrNull;
    if (box == null) return null;
    // הקצה השמאלי של גרפמה LTR הוא תחילתה, ושל RTL — סופה.
    final position = (box.direction == TextDirection.ltr) != toRight
        ? TextPosition(offset: grapheme.start)
        : TextPosition(offset: grapheme.end, affinity: TextAffinity.upstream);
    final moved = _caretPoint(render, position) - from;
    if (moved.dy.abs() > 0.5) return null;
    if (toRight ? moved.dx <= 0.5 : moved.dx >= -0.5) return null;
    if (boundary == null) return (position: position, useNativeWord: false);

    final forward = position.offset == grapheme.end;
    final leading = boundary.getLeadingTextBoundaryAt(grapheme.end - 1) ?? 0;
    final trailing =
        boundary.getTrailingTextBoundaryAt(grapheme.start) ?? text.length;
    // במילה LTR נגלשת, הגבול הלוגי עשוי להיות בשורה הפוכה לכיוון החץ.
    if (box.direction == TextDirection.ltr &&
        render.getLineAtOffset(TextPosition(offset: leading)).start !=
            render
                .getLineAtOffset(
                  TextPosition(
                    offset: trailing,
                    affinity: TextAffinity.upstream,
                  ),
                )
                .start) {
      return (position: position, useNativeWord: true);
    }
    final limit = forward ? trailing : leading;
    final mixedWord = render
        .getBoxesForSelection(
          TextSelection(
            baseOffset: forward ? grapheme.start : limit,
            extentOffset: forward ? limit : grapheme.end,
          ),
        )
        .any((part) => part.direction != box.direction);
    if (mixedWord) return (position: position, useNativeWord: true);

    final offset = forward
        ? chars.getLeadingTextBoundaryAt(limit)!
        : chars.getTrailingTextBoundaryAt(limit - 1)!;
    return (
      position: TextPosition(
        offset: offset,
        affinity: forward ? TextAffinity.upstream : TextAffinity.downstream,
      ),
      useNativeWord: false,
    );
  }

  /// בקצה השורה החץ עובר לשורה הסמוכה בסדר הקריאה (שמאלה = הבאה), אל הקצה
  /// שממנו ממשיכים לקרוא. null כשאין שורה כזו.
  TextPosition? _adjacentLineEdge(
    RenderEditable render,
    TextPosition caret,
    bool toRight,
  ) {
    final from = _caretPoint(render, caret);
    final lineHeight = render.preferredLineHeight;
    final hit = render.getPositionForPoint(
      render.localToGlobal(
        from.translate(0, toRight ? -lineHeight : lineHeight),
      ),
    );
    // בעוקף שבירת השורה המיקום עשוי ליפול בין \r ל-\n — חוזרים לתחילת הגרפמה.
    final edge = TextPosition(
      offset: CharacterBoundary(
        _boundController.text,
      ).getLeadingTextBoundaryAt(hit.offset)!,
      affinity: hit.affinity,
    );
    if ((_caretPoint(render, edge).dy - from.dy).abs() < 0.5) return null;
    // בוחרים תיבה קיצונית בשאילתה אחת; נקודה מחוץ לטקסט אינה אמינה.
    final line = render.getLineAtOffset(edge);
    ui.TextBox? outer;
    for (final box in render.getBoxesForSelection(
      TextSelection(baseOffset: line.start, extentOffset: line.end),
    )) {
      if (box.left == box.right) continue;
      if (outer == null ||
          (toRight ? box.left < outer.left : box.right > outer.right)) {
        outer = box;
      }
    }
    if (outer == null) return edge;
    final inset = ((outer.right - outer.left) / 2).clamp(0.0, 0.1);
    final edgeHit = render.getPositionForPoint(
      render.localToGlobal(
        Offset(
          toRight ? outer.left + inset : outer.right - inset,
          (outer.top + outer.bottom) / 2,
        ),
      ),
    );
    final after =
        edgeHit.affinity == TextAffinity.downstream &&
        edgeHit.offset < _boundController.text.length;
    if (!after && edgeHit.offset == 0) return edge;
    final grapheme = CharacterBoundary(
      _boundController.text,
    ).getTextBoundaryAt(after ? edgeHit.offset : edgeHit.offset - 1);
    final forward = (outer.direction == TextDirection.ltr) != toRight;
    return TextPosition(
      offset: forward ? grapheme.end : grapheme.start,
      affinity: forward ? TextAffinity.upstream : TextAffinity.downstream,
    );
  }

  /// מרכז הסמן ב-[position] בקואורדינטות של [render], כולל הגלילה.
  Offset _caretPoint(RenderEditable render, TextPosition position) => render
      .getEndpointsForSelection(TextSelection.fromPosition(position))
      .first
      .point
      .translate(0, -render.preferredLineHeight / 2);

  void _showContextMenu(
    BuildContext context,
    Offset position, {
    bool requestFocus = true,
  }) {
    final controller = _effectiveController;
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
      requestFocus: requestFocus,
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
          if (!mounted || controller != _effectiveController) return;
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
          if (!mounted || controller != _effectiveController) return;
          if (data?.text != null) {
            // טקסט שהועתק מ-Notepad/Word מגיע עם \r\n אמיתי; מנקים לפני
            // שהוא נכנס ל-controller ה"נקי" (ראו rtl_hard_break_workaround.dart).
            final pasted = _hardBreakWorkaroundActive
                ? collapseHardBreaks(data!.text!)
                : data!.text!;
            final newText =
                currentText.substring(0, currentSelection.start) +
                pasted +
                currentText.substring(currentSelection.end);
            controller.text = newText;
            controller.selection = TextSelection.collapsed(
              offset: currentSelection.start + pasted.length,
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
          ),
        ],
      ),
    );
  }
}
