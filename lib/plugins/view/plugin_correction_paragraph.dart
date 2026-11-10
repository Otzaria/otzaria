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
import 'package:otzaria/widgets/smart_text/inline_html_document.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';
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

/// מיקום אופקי של הסמן בעת מעבר בין פסקאות בחיצים, כדי שהסמן ינחת באותו מקום
/// בשורה הסמוכה ולא בסוף השורה.
class _CaretHandoff {
  final double dx;
  final bool movedDown;
  final DateTime at = DateTime.now();
  _CaretHandoff(this.dx, this.movedDown);
  bool get fresh =>
      DateTime.now().difference(at) < const Duration(milliseconds: 800);
}

class _PluginCorrectionParagraphState extends State<PluginCorrectionParagraph> {
  static _CaretHandoff? _handoff;

  /// הפסקה היחידה שפתוחה כרגע לעריכה בלי שתוקנה. מצב העריכה הוא דגל ולא שיקוף
  /// של הפוקוס: אזור הבחירה של הקורא לוקח פוקוס באמצע כל לחיצה ממושכת, ואילו
  /// העורך היה נסגר איתו אי אפשר היה לסמן טקסט בעכבר, להדביק מתפריט או לחזור
  /// מחלון אחר.
  static _PluginCorrectionParagraphState? _active;
  Timer? _tapTimer;

  /// הפעלה בלחיצת עכבר: השורה שנלחצה כבר גלויה, ולכן השדה אינו גולל את עצמו
  /// "כדי לחשוף את הסמן" (20 פיקסלים מכל קצה) והדף אינו זז מתחת לעכבר.
  Timer? _revealTimer;
  bool _suppressReveal = false;
  Offset? _lastTapUp;
  Offset? _downAt;
  bool _editable = false;
  bool _corrected = false;
  bool _showEditor = false;
  PluginCorrectionController? _controller;
  FocusNode? _focus;
  FocusNode? _activationFocus;
  Offset? _editPosition;
  final GlobalKey _originalKey = GlobalKey();

  /// גובה הפסקה הרגילה ברגע ההפעלה: שדה העריכה אינו נמוך ממנו, כדי שהחלפת
  /// התצוגה לא תשנה את גובה הפסקה ולא תזיז את הגלילה. מתבטל עם התיקון הראשון.
  double? _lockedHeight;
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

  /// סוגר עורך של פסקה שלא תוקנה ומחזיר את התצוגה הרגילה. פסקה שתוקנה נשארת
  /// עורך בכל מקרה.
  void _stopEditing({bool refocusReader = false}) {
    _clearTap();
    if (_active == this) _active = null;
    if (!_showEditor) return;
    if (!mounted) {
      _showEditor = false;
      return;
    }
    setState(() => _showEditor = false);
    if (!refocusReader || _corrected) return;
    // הפוקוס חוזר לקורא (ולא לפסקה), כדי שחצים וגלילה ימשיכו לעבוד.
    final reader = Focus.maybeOf(context, createDependency: false);
    if (reader == null || reader is FocusScopeNode) {
      _focus?.unfocus(disposition: UnfocusDisposition.scope);
    } else {
      reader.requestFocus();
    }
  }

  void _editorPointerDown(PointerDownEvent event) {
    _downAt = null;
    if (_corrected || event.buttons != kPrimaryButton) return;
    final last = _lastTapUp;
    if (_tapTimer?.isActive == true &&
        last != null &&
        (event.position - last).distance <= kDoubleTapSlop) {
      // לחיצה כפולה על פסקה שלא תוקנה יוצאת ממצב העריכה.
      _stopEditing(refocusReader: true);
      return;
    }
    _downAt = event.position;
  }

  void _editorPointerUp(PointerUpEvent event) {
    final down = _downAt;
    _downAt = null;
    _clearTap();
    // גרירה (סימון טקסט) אינה לחיצה.
    if (down == null || (event.position - down).distance > kTouchSlop) return;
    _lastTapUp = event.position;
    _tapTimer = Timer(kDoubleTapTimeout, _clearTap);
  }

  void _focusChanged() {
    if (!mounted) return;
    if (_focus!.hasFocus) _claimActive();
    final handoff = _handoff;
    if (!_focus!.hasFocus || handoff == null) return;
    _handoff = null;
    if (!handoff.fresh) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _focus?.context;
      if (!mounted || _controller == null || context == null) return;
      if (!context.mounted) return;
      final editor = context.findAncestorStateOfType<EditableTextState>();
      if (editor == null) return;
      final render = editor.renderEditable;
      final half = render.preferredLineHeight / 2;
      final y = handoff.movedDown ? half : render.size.height - half;
      final point = render.localToGlobal(Offset(0, y));
      _controller!.selection = TextSelection.fromPosition(
        render.getPositionForPoint(Offset(handoff.dx, point.dy)),
      );
    });
  }

  void _activationFocusChanged() {
    if (_activationFocus!.hasPrimaryFocus) _startEditing();
  }

  void _lockOriginalHeight() {
    final height = _originalKey.currentContext?.size?.height;
    if (height != null && height.isFinite && height > 0) _lockedHeight = height;
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

  /// חץ מעלה/מטה בשורה הראשונה/האחרונה של הפסקה עובר לפסקה הסמוכה, כדי
  /// שאפשר יהיה לנוע בין פסקאות במקלדת ולא רק לצדדים.
  KeyEventResult _onEditorKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final up = key == LogicalKeyboardKey.arrowUp;
    if (!up && key != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final controller = _controller;
    final editor = node.context?.findAncestorStateOfType<EditableTextState>();
    if (controller == null ||
        editor == null ||
        keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed ||
        !editor.textEditingValue.selection.isValid ||
        !editor.textEditingValue.selection.isCollapsed) {
      return KeyEventResult.ignored;
    }
    // הבחירה והטקסט נלקחים מהשדה עצמו (לא מהבקר החיצוני): בשדה רב-שורתי הם
    // כוללים ירידות שורה מורחבות, וההיסטים של הבקר החיצוני אינם תואמים.
    final value = editor.textEditingValue;
    final render = editor.renderEditable;
    final extent = value.selection.extent;
    final line = render.getLineAtOffset(extent);
    // בתוך פסקה של כמה שורות החצים נשארים של שדה הטקסט; רק בשורה הראשונה או
    // האחרונה של הפסקה עוברים לפסקה הסמוכה.
    final atEdge = up ? line.start <= 0 : line.end >= value.text.length;
    final caret = render.getLocalRectForCaret(extent);
    if (!atEdge) {
      // הזזת הסמן לשורה הסמוכה בתוך הפסקה נעשית כאן במפורש, באותו מקום
      // אופקי, ולא נשארת לקיצורי העריכה הגלובליים שאינם מגיעים לשדה.
      final step = render.preferredLineHeight * (up ? -1 : 1);
      final target = render.getPositionForPoint(
        render.localToGlobal(Offset(caret.center.dx, caret.center.dy + step)),
      );
      editor.userUpdateTextEditingValue(
        value.copyWith(selection: TextSelection.fromPosition(target)),
        SelectionChangedCause.keyboard,
      );
      return KeyEventResult.handled;
    }
    final point = render.localToGlobal(caret.center);
    _handoff = _CaretHandoff(point.dx, !up);
    final moved = FocusScope.of(node.context!).focusInDirection(
      up ? TraversalDirection.up : TraversalDirection.down,
    );
    if (!moved) _handoff = null;
    return moved ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  bool _syncText() {
    if (!_registry.canEditParagraph(widget.tabId, widget.sourceText)) {
      return false;
    }
    if (_controller == null) {
      _controller = PluginCorrectionController(
        widget.sourceText,
        hideNikud: widget.settings.removeNikud,
      );
      _focus = FocusNode(onKeyEvent: _onEditorKey)..addListener(_focusChanged);
      _activationFocus = FocusNode()..addListener(_activationFocusChanged);
    }
    final controller = _controller!;
    // ספר שהוגדר ללא ניקוד מוצג כך גם בעורך; הניקוד נשמר במקור.
    controller.hideNikud = widget.settings.removeNikud;
    controller.setSource(widget.sourceText);
    final canonical = _registry.editableText(
      widget.tabId,
      widget.sectionIndex,
      widget.sourceText,
    );
    if (controller.forService(controller.text) == canonical) {
      controller.adopt(canonical);
      return false;
    }
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
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: _corrected ? 0 : (_lockedHeight ?? 0),
        ),
        child: Listener(
          onPointerDown: _editorPointerDown,
          onPointerUp: _editorPointerUp,
          onPointerCancel: (_) => _downAt = null,
          child: _buildEditor(),
        ),
      ),
    );
  }

  /// שדה טקסט שומר לסמן [_caretMargin] פיקסלים בקצה השורה (רווח של 1 ועובי
  /// הסמן של [RtlTextField], 1). בלי פיצוי השורות בעורך צרות מהתצוגה הרגילה,
  /// ובפסקה ארוכה ומיושרת מילים עוברות שורה והטקסט זז מתחת לעין.
  static const double _caretMargin = 2.0;

  Widget _matchReadingWidth(Widget editor) =>
      _CaretRoom(suppressReveal: () => _suppressReveal, child: editor);

  InlineHtmlLine? _readingLine;
  List<TextSpan>? _readingLeaves;

  /// העלים של התצוגה הרגילה (מודגש, סוגריים מוקטנים וכו') כל עוד הטקסט בעורך
  /// זהה לטקסט שלה. כך פסקה שנפתחת לעריכה נשברת לשורות בדיוק כמו קודם, ואינה
  /// קופצת. אחרי שינוי בטקסט העורך חוזר לטקסט פשוט.
  List<TextSpan>? _leavesFor(String text) {
    final line = _readingLine;
    if (line == null || line.document.plainText != text) return null;
    return _readingLeaves ??= [
      for (final run in line.document.runs)
        TextSpan(text: run.text, style: run.style),
    ];
  }

  Widget _buildEditor() {
    final settings = widget.settings;
    // אותו עיבוד, אותו גופן ואותו סגנון שורה כמו ב-SmartTextWidget.
    final html = TextRendererService.processText(widget.sourceText, settings);
    final family = AppFonts.taamimSafeFontFamily(settings.fontFamily, html);
    final textStyle = TextStyle(
      fontSize: settings.fontSize,
      fontFamily: AppFonts.renderFontFamily(family),
      fontWeight: settings.fontWeight,
      fontVariations: AppFonts.boldFontVariations(
        family,
        settings.fontWeight ?? FontWeight.normal,
      ),
      height: settings.lineHeight,
    );
    final line = InlineHtmlDocument.parseLine(html, textStyle);
    if (!identical(line, _readingLine)) {
      _readingLine = line;
      _readingLeaves = null;
    }
    // שדה טקסט ממזג מתחת לסגנון את bodyLarge של ערכת הנושא (ריווח אותיות 0.5),
    // והתצוגה הרגילה יורשת את סגנון ברירת המחדל של הקורא. ריווח שונה מזיז כל
    // מילה ושובר שורות אחרת, ולכן הריווח נלקח במפורש מאותו מקור.
    final inherited = DefaultTextStyle.of(context).style;
    return _matchReadingWidth(
      RtlTextField(
        controller: _controller!,
        focusNode: _focus!,
        highlightText: settings.searchText,
        formattedLeaves: line == null ? null : _leavesFor,
        strutStyle: line?.strutStyle,
        scrollPadding: EdgeInsets.zero,
        maxLines: null,
        minLines: 1,
        textInputAction: TextInputAction.newline,
        textAlign: settings.justifyText ? TextAlign.justify : TextAlign.right,
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        style: (line?.style ?? textStyle).copyWith(
          letterSpacing: inherited.letterSpacing ?? 0,
          wordSpacing: inherited.wordSpacing ?? 0,
        ),
        inputFormatters: [TextInputFormatter.withFunction(_validate)],
        onChanged: _applyText,
      ),
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

/// מניח את העורך ברוחב ההורה ועוד [_PluginCorrectionParagraphState._caretMargin],
/// וגודלו כלפי ההורה נשאר רוחב ההורה. התוספת חורגת ימינה (הטקסט מצויר מקצה
/// שמאל), ולכן אזור הטקסט רוחבו בדיוק כמו בתצוגה הרגילה.
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
