import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/plugin_messages.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/view/plugin_correction_controller.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// עריכה מקומית בפסקת מקור, ללא היסטים או עוגנים של נוסח אחר.
class PluginCorrectionParagraph extends StatefulWidget {
  final String tabId;
  final int sectionIndex;
  final String sourceText;
  final RenderSettings settings;
  final Widget original;
  final PluginCorrectionSessionService? service;
  final bool sessionActive;

  const PluginCorrectionParagraph({
    super.key,
    required this.tabId,
    required this.sectionIndex,
    required this.sourceText,
    required this.settings,
    required this.original,
    this.service,
    this.sessionActive = false,
  });

  @override
  State<PluginCorrectionParagraph> createState() =>
      _PluginCorrectionParagraphState();
}

/// העמודה האופקית של הסמן במעבר בחצים בין פסקאות; הפסקה שמקבלת מיקוד מנחיתה
/// בה את הסמן. null כשאין מעבר בתהליך.
class _CaretHandoff {
  final double dx;
  final bool movedDown;
  const _CaretHandoff(this.dx, this.movedDown);
}

class _PluginCorrectionParagraphState extends State<PluginCorrectionParagraph> {
  static _CaretHandoff? _handoff;

  /// הפסקה היחידה שפתוחה לעריכה בלי שתוקנה. איבוד פוקוס אינו סוגר אותה, כי
  /// אזור הבחירה של הקורא לוקח פוקוס באמצע לחיצה.
  static _PluginCorrectionParagraphState? _active;
  Timer? _tapTimer;
  Offset? _lastTapUp;
  PointerDownEvent? _tapDown;

  /// השורה שנלחצה כבר גלויה, ולכן מיד אחרי הפעלה בעכבר השדה אינו גולל את
  /// עצמו כדי לחשוף את הסמן, והדף אינו זז מתחת לעכבר.
  Timer? _revealTimer;
  bool _suppressReveal = false;
  bool _editable = false;
  bool _corrected = false;
  bool _showEditor = false;
  PluginCorrectionController? _controller;
  FocusNode? _focus;
  FocusNode? _activationFocus;
  Offset? _editPosition;
  final GlobalKey _originalKey = GlobalKey();

  /// גובה הפסקה הרגילה והרוחב שבו נמדד: העורך אינו נמוך ממנו, כדי שהחלפת
  /// התצוגה לא תזיז את הגלילה. הנעילה פגה בשינוי רוחב, הגדרות או תיקון.
  double? _lockedHeight;
  double? _lockedWidth;
  String? _lastRejection;
  DateTime _lastRejectionAt = DateTime.fromMillisecondsSinceEpoch(0);
  PluginCorrectionSessionService get _registry =>
      widget.service ?? PluginCorrectionSessionService.instance;

  @override
  void initState() {
    super.initState();
    if (widget.sessionActive) _activate();
  }

  @override
  void didUpdateWidget(PluginCorrectionParagraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    final serviceChanged = oldWidget.service != widget.service;
    if (oldWidget.sessionActive && (!widget.sessionActive || serviceChanged)) {
      (oldWidget.service ?? PluginCorrectionSessionService.instance)
          .removeListener(_changed);
      if (!widget.sessionActive || serviceChanged) _disposeEditor();
    }
    if (widget.sessionActive && (!oldWidget.sessionActive || serviceChanged)) {
      _activate();
    }
    if (oldWidget.settings != widget.settings) _lockedHeight = null;
    if (widget.sessionActive) _syncText();
  }

  void _activate() {
    _registry.addListener(_changed);
    _syncText();
  }

  void _disposeEditor() {
    _cancelTimers();
    if (_active == this) _active = null;
    _controller?.dispose();
    _focus?.dispose();
    _activationFocus?.dispose();
    _controller = null;
    _focus = null;
    _activationFocus = null;
    _editable = false;
    _corrected = false;
    _showEditor = false;
  }

  void _claimActive() {
    if (_active == this) return;
    _active?._stopEditing();
    _active = this;
  }

  void _cancelTimers() {
    _tapDown = null;
    _clearTap();
    _revealTimer?.cancel();
    _revealTimer = null;
    _suppressReveal = false;
  }

  void _clearTap() {
    _tapTimer?.cancel();
    _tapTimer = null;
    _lastTapUp = null;
  }

  /// סוגר עורך של פסקה שלא תוקנה; פסקה שתוקנה נשארת עורך.
  void _stopEditing({bool refocusReader = false}) {
    _clearTap();
    if (_active == this) _active = null;
    if (!_showEditor) return;
    if (!mounted) {
      _showEditor = false;
      return;
    }
    setState(() => _showEditor = false);
    if (!refocusReader) return;
    // המיקוד חוזר לקורא ולא לפסקה, כדי שחצים וגלילה ימשיכו לעבוד.
    final reader = Focus.maybeOf(context, createDependency: false);
    if (reader == null || reader is FocusScopeNode) {
      _focus?.unfocus(disposition: UnfocusDisposition.scope);
    } else {
      reader.requestFocus();
    }
  }

  void _editorPointerDown(PointerDownEvent event) {
    _tapDown = !_corrected && event.buttons == kPrimaryButton ? event : null;
  }

  bool _outsideTapSlop(PointerDownEvent down, PointerEvent event) =>
      (event.position - down.position).distance >
      computeHitSlop(down.kind, MediaQuery.maybeGestureSettingsOf(context));

  void _editorPointerMove(PointerMoveEvent event) {
    final down = _tapDown;
    if (down != null &&
        event.pointer == down.pointer &&
        _outsideTapSlop(down, event)) {
      _tapDown = null;
      _clearTap();
    }
  }

  void _editorPointerUp(PointerUpEvent event) {
    final down = _tapDown;
    _tapDown = null;
    final last = _lastTapUp;
    _clearTap();
    if (_corrected ||
        down == null ||
        event.pointer != down.pointer ||
        _outsideTapSlop(down, event) ||
        event.timeStamp - down.timeStamp >= kLongPressTimeout) {
      return;
    }
    if (last != null && (down.position - last).distance <= kDoubleTapSlop) {
      _stopEditing(refocusReader: true);
      return;
    }
    _lastTapUp = event.position;
    _tapTimer = Timer(kDoubleTapTimeout, _clearTap);
  }

  void _focusChanged() {
    if (!mounted) return;
    if (_focus!.hasFocus) _claimActive();
    final handoff = _handoff;
    if (!_focus!.hasFocus || handoff == null) return;
    _handoff = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final editor = _focus?.context
          ?.findAncestorStateOfType<EditableTextState>();
      if (!mounted || editor == null) return;
      final render = editor.renderEditable;
      final half = render.preferredLineHeight / 2;
      final y = handoff.movedDown ? half : render.size.height - half;
      final top = render.localToGlobal(Offset(0, y));
      editor.widget.controller.selection = TextSelection.fromPosition(
        render.getPositionForPoint(Offset(handoff.dx, top.dy)),
      );
    });
  }

  /// Escape יוצא מהעריכה והתיקון נשאר. חץ מעלה/מטה בשורה הראשונה/האחרונה
  /// עובר לפסקה הסמוכה, ובאמצע פסקה מזיז את הסמן בין השורות.
  KeyEventResult _onEditorKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_showEditor) {
        _stopEditing(refocusReader: true);
        if (!_corrected) return KeyEventResult.handled;
      }
      // המיקוד חוזר לקורא, כדי שחצים וגלילה ימשיכו לעבוד.
      final reader = Focus.maybeOf(context, createDependency: false);
      if (reader == null || reader is FocusScopeNode) {
        node.unfocus(disposition: UnfocusDisposition.scope);
      } else {
        reader.requestFocus();
      }
      return KeyEventResult.handled;
    }
    final up = key == LogicalKeyboardKey.arrowUp;
    if (!up && key != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final editor = node.context?.findAncestorStateOfType<EditableTextState>();
    if (editor == null ||
        keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    // הטקסט והבחירה נלקחים מהשדה עצמו: בו ירידות השורה מורחבות, והיסטי
    // הבקר החיצוני אינם תואמים.
    final value = editor.textEditingValue;
    if (!value.selection.isValid || !value.selection.isCollapsed) {
      return KeyEventResult.ignored;
    }
    final render = editor.renderEditable;
    final extent = value.selection.extent;
    final line = render.getLineAtOffset(extent);
    final caret = render.getLocalRectForCaret(extent);
    if (up ? line.start > 0 : line.end < value.text.length) {
      final step = render.preferredLineHeight * (up ? -1 : 1);
      editor.userUpdateTextEditingValue(
        value.copyWith(
          selection: TextSelection.fromPosition(
            render.getPositionForPoint(
              render.localToGlobal(
                Offset(caret.center.dx, caret.center.dy + step),
              ),
            ),
          ),
        ),
        SelectionChangedCause.keyboard,
      );
      return KeyEventResult.handled;
    }
    _handoff = _CaretHandoff(render.localToGlobal(caret.center).dx, !up);
    final moved = FocusScope.of(node.context!).focusInDirection(
      up ? TraversalDirection.up : TraversalDirection.down,
    );
    // מיקוד שנחת ברכיב שאינו פסקה לא משאיר מעבר תלוי לפסקה אחרת.
    scheduleMicrotask(() {
      final target = FocusManager.instance.primaryFocus?.context;
      if (target?.findAncestorStateOfType<_PluginCorrectionParagraphState>() ==
          null) {
        _handoff = null;
      }
    });
    return moved ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  void _activationFocusChanged() {
    if (_activationFocus!.hasPrimaryFocus) _startEditing();
  }

  void _lockOriginalHeight() {
    final size = _originalKey.currentContext?.size;
    final box = context.findRenderObject();
    if (size == null ||
        box is! RenderBox ||
        !size.height.isFinite ||
        size.height <= 0) {
      return;
    }
    _lockedHeight = size.height;
    _lockedWidth = box.constraints.maxWidth;
  }

  void _startEditing({Offset? position}) {
    _claimActive();
    if (position != null) {
      _suppressReveal = true;
      _revealTimer?.cancel();
      _revealTimer = Timer(const Duration(milliseconds: 300), () {
        _suppressReveal = false;
      });
    }
    _lockOriginalHeight();
    setState(() => _showEditor = true);
    _focus!.requestFocus();
    if (position == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _controller == null) return;
      final editor = _focus!.context
          ?.findAncestorStateOfType<EditableTextState>();
      if (editor == null) return;
      _controller!.selection = TextSelection.fromPosition(
        editor.renderEditable.getPositionForPoint(position),
      );
    });
  }

  bool _syncText() {
    if (!_registry.canEditParagraph(widget.tabId, widget.sourceText)) {
      return false;
    }
    if (_controller == null) {
      _controller = PluginCorrectionController(widget.sourceText);
      _focus = FocusNode(onKeyEvent: _onEditorKey)..addListener(_focusChanged);
      _activationFocus = FocusNode()..addListener(_activationFocusChanged);
    }
    final controller = _controller!;
    controller.formatParentheses = widget.settings.formatParentheses;
    controller.setSource(widget.sourceText);
    final canonical = _registry.editableText(
      widget.tabId,
      widget.sectionIndex,
      widget.sourceText,
    );
    if (controller.forService(controller.text) == canonical) return false;
    final text = controller.forEditor(canonical);
    if (controller.text == text) return false;
    final selection = controller.selection;
    controller.restoreDraftValue(
      TextEditingValue(
        text: text,
        selection: selection.isValid
            ? selection.copyWith(
                baseOffset: selection.baseOffset.clamp(0, text.length),
                extentOffset: selection.extentOffset.clamp(0, text.length),
              )
            : TextSelection.collapsed(offset: text.length),
      ),
    );
    return true;
  }

  bool get _isCorrected => _registry.isCorrected(
    widget.tabId,
    widget.sectionIndex,
    widget.sourceText,
  );

  void _changed() {
    if (!mounted) return;
    final textChanged = _syncText();
    final editable = _registry.canEditParagraph(
      widget.tabId,
      widget.sourceText,
    );
    final corrected = _isCorrected;
    if (!textChanged && editable == _editable && corrected == _corrected) {
      return;
    }
    _editable = editable;
    _corrected = corrected;
    setState(() {});
  }

  /// מקש שנדחה שוב ושוב (למשל בגבול הגודל) לא מציף הודעה ורטט בכל הקשה.
  void _showRejection(PluginCorrectionException error) {
    final now = DateTime.now();
    if (_lastRejection == error.message &&
        now.difference(_lastRejectionAt) < const Duration(seconds: 3)) {
      return;
    }
    _lastRejection = error.message;
    _lastRejectionAt = now;
    UiSnack.showError(PluginMessages.correctionEditRejected(error.message));
  }

  TextEditingValue _validate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    try {
      _registry.validateNativeEdit(
        widget.tabId,
        widget.sectionIndex,
        widget.sourceText,
        _controller!.forService(newValue.text),
      );
      return newValue;
    } on PluginCorrectionException catch (error) {
      _showRejection(error);
      return oldValue;
    }
  }

  void _applyText(String text) {
    try {
      _registry.editParagraph(
        widget.tabId,
        widget.sectionIndex,
        widget.sourceText,
        _controller!.forService(text),
      );
    } on PluginCorrectionException catch (error) {
      _showRejection(error);
      _syncText();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.sessionActive) return widget.original;
    _editable = _registry.canEditParagraph(widget.tabId, widget.sourceText);
    if (!_editable) {
      return widget.original;
    }
    _corrected = _isCorrected;
    if (!_showEditor && !_corrected) {
      return Focus(
        focusNode: _activationFocus,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (details) => _editPosition = details.globalPosition,
          onTap: () => _startEditing(position: _editPosition),
          child: KeyedSubtree(key: _originalKey, child: widget.original),
        ),
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    // העורך נשאר מחובר גם כשהתיקון הראשון מוסיף את סימון הפסקה.
    return DecoratedBox(
      decoration: BoxDecoration(
        border: BorderDirectional(
          start: _corrected
              ? BorderSide(
                  color: AppSurfaces.correctedParagraphMarker(colorScheme),
                  width: 3,
                )
              : BorderSide.none,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: _corrected || _lockedWidth != constraints.maxWidth
                ? 0
                : (_lockedHeight ?? 0),
          ),
          child: Listener(
            onPointerDown: _editorPointerDown,
            onPointerMove: _editorPointerMove,
            onPointerUp: _editorPointerUp,
            onPointerCancel: (_) {
              _tapDown = null;
              _clearTap();
            },
            child: _CaretRoom(
              suppressReveal: () => _suppressReveal,
              child: _buildEditor(),
            ),
          ),
        ),
      ),
    );
  }

  /// שדה טקסט שומר לסמן 2 פיקסלים בקצה השורה; [_CaretRoom] מרחיב את השדה
  /// בגודל הזה, כדי שהשורות יישברו כמו בתצוגה הרגילה.
  static const double _caretMargin = 2.0;

  Widget _buildEditor() {
    final settings = widget.settings;
    final family = AppFonts.taamimSafeFontFamily(
      settings.fontFamily,
      widget.sourceText,
    );
    // שדה טקסט ממזג את bodyLarge (ריווח אותיות 0.5) והקורא יורש את ברירת
    // המחדל; ריווח שונה שובר שורות אחרת, ולכן לוקחים אותו מאותו מקור.
    final inherited = DefaultTextStyle.of(context).style;
    return RtlTextField(
      controller: _controller!,
      focusNode: _focus!,
      maxLines: null,
      minLines: 1,
      textInputAction: TextInputAction.newline,
      textAlign: settings.justifyText ? TextAlign.justify : TextAlign.right,
      decoration: const InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
      style: TextStyle(
        fontSize: settings.fontSize,
        fontFamily: AppFonts.renderFontFamily(family),
        fontWeight: settings.fontWeight,
        fontVariations: AppFonts.boldFontVariations(
          family,
          settings.fontWeight ?? FontWeight.normal,
        ),
        height: settings.lineHeight,
        letterSpacing: inherited.letterSpacing ?? 0,
        wordSpacing: inherited.wordSpacing ?? 0,
      ),
      inputFormatters: [TextInputFormatter.withFunction(_validate)],
      onChanged: _applyText,
    );
  }

  @override
  void dispose() {
    _cancelTimers();
    if (_active == this) _active = null;
    _registry.removeListener(_changed);
    _controller?.dispose();
    _focus?.dispose();
    _activationFocus?.dispose();
    super.dispose();
  }
}

/// מניח את העורך ברוחב ההורה ועוד [_PluginCorrectionParagraphState._caretMargin];
/// התוספת חורגת ימינה, ולכן אזור הטקסט רחב כמו בתצוגה הרגילה.
class _CaretRoom extends SingleChildRenderObjectWidget {
  const _CaretRoom({required this.suppressReveal, required super.child});

  final bool Function() suppressReveal;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCaretRoom(suppressReveal);

  @override
  void updateRenderObject(BuildContext context, _RenderCaretRoom renderObject) {
    renderObject.suppressReveal = suppressReveal;
  }
}

class _RenderCaretRoom extends RenderProxyBox {
  _RenderCaretRoom(this.suppressReveal);

  bool Function() suppressReveal;

  @override
  void showOnScreen({
    RenderObject? descendant,
    Rect? rect,
    Duration duration = Duration.zero,
    Curve curve = Curves.ease,
  }) {
    if (suppressReveal()) return;
    super.showOnScreen(
      descendant: descendant,
      rect: rect,
      duration: duration,
      curve: curve,
    );
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null || !constraints.hasBoundedWidth) {
      super.performLayout();
      return;
    }
    final width =
        constraints.maxWidth + _PluginCorrectionParagraphState._caretMargin;
    child.layout(
      constraints.copyWith(minWidth: width, maxWidth: width),
      parentUsesSize: true,
    );
    size = constraints.constrain(Size(constraints.maxWidth, child.size.height));
  }
}
