import 'dart:async';
import 'dart:convert';
import 'package:otzaria/theme/app_tokens.dart';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_link_dialog.dart';

// RTL-aware arrow key shortcuts for QuillEditor.
//
// LEFT/RIGHT: flutter_quill doesn't flip forward/backward for RTL, so we swap them.
//
// UP/DOWN: the Windows platform text input handles arrow keys at the OS level,
// but it can't compute vertical line positions in a multi-block rich text editor.
// Adding them here routes them through QuillEditor's own adjacentLineAction,
// which correctly finds the character position on the line above/below.
const _rtlArrowShortcuts = <ShortcutActivator, Intent>{
  // Horizontal navigation (RTL-swapped)
  SingleActivator(LogicalKeyboardKey.arrowRight):
      ExtendSelectionByCharacterIntent(forward: false, collapseSelection: true),
  SingleActivator(LogicalKeyboardKey.arrowLeft):
      ExtendSelectionByCharacterIntent(forward: true, collapseSelection: true),
  SingleActivator(
    LogicalKeyboardKey.arrowRight,
    shift: true,
  ): ExtendSelectionByCharacterIntent(
    forward: false,
    collapseSelection: false,
  ),
  SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
      ExtendSelectionByCharacterIntent(forward: true, collapseSelection: false),
  SingleActivator(
    LogicalKeyboardKey.arrowRight,
    control: true,
  ): ExtendSelectionToNextWordBoundaryIntent(
    forward: false,
    collapseSelection: true,
  ),
  SingleActivator(
    LogicalKeyboardKey.arrowLeft,
    control: true,
  ): ExtendSelectionToNextWordBoundaryIntent(
    forward: true,
    collapseSelection: true,
  ),
  SingleActivator(
    LogicalKeyboardKey.arrowRight,
    control: true,
    shift: true,
  ): ExtendSelectionToNextWordBoundaryIntent(
    forward: false,
    collapseSelection: false,
  ),
  SingleActivator(
    LogicalKeyboardKey.arrowLeft,
    control: true,
    shift: true,
  ): ExtendSelectionToNextWordBoundaryIntent(
    forward: true,
    collapseSelection: false,
  ),
  // Vertical navigation (routed through Quill's adjacentLineAction)
  SingleActivator(
    LogicalKeyboardKey.arrowUp,
  ): ExtendSelectionVerticallyToAdjacentLineIntent(
    forward: false,
    collapseSelection: true,
  ),
  SingleActivator(
    LogicalKeyboardKey.arrowDown,
  ): ExtendSelectionVerticallyToAdjacentLineIntent(
    forward: true,
    collapseSelection: true,
  ),
  SingleActivator(
    LogicalKeyboardKey.arrowUp,
    shift: true,
  ): ExtendSelectionVerticallyToAdjacentLineIntent(
    forward: false,
    collapseSelection: false,
  ),
  SingleActivator(
    LogicalKeyboardKey.arrowDown,
    shift: true,
  ): ExtendSelectionVerticallyToAdjacentLineIntent(
    forward: true,
    collapseSelection: false,
  ),
};

class PersonalNoteEditorResult {
  final String content;
  final String contentPlain;
  final PersonalNoteContentFormat contentFormat;

  const PersonalNoteEditorResult({
    required this.content,
    required this.contentPlain,
    required this.contentFormat,
  });
}

class PersonalNoteEditorController {
  final quill.QuillController quillController;

  PersonalNoteEditorController({required this.quillController});

  PersonalNoteEditorResult buildResult() {
    final deltaJson = jsonEncode(quillController.document.toDelta().toJson());
    final plain = quillController.document.toPlainText().trimRight();
    return PersonalNoteEditorResult(
      content: deltaJson,
      contentPlain: plain,
      contentFormat: PersonalNoteContentFormat.quillDelta,
    );
  }
}

class PersonalNoteEditorBody extends StatefulWidget {
  final PersonalNoteEditorController controller;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final bool autofocus;
  final String? referenceText;
  final String? hintText;
  final List<PersonalNote> linkableNotes;
  final String? bookId;
  final VoidCallback? onSaveShortcut;

  const PersonalNoteEditorBody({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.scrollController,
    required this.autofocus,
    required this.linkableNotes,
    this.referenceText,
    this.hintText,
    this.bookId,
    this.onSaveShortcut,
  });

  @override
  State<PersonalNoteEditorBody> createState() => _PersonalNoteEditorBodyState();
}

class _PersonalNoteEditorBodyState extends State<PersonalNoteEditorBody> {
  // עוטף את אזור הכתיבה כדי לגלול אותו לתוך התצוגה כשהוא יורד מתחת לחלון.
  final GlobalKey _editorAreaKey = GlobalKey();
  Timer? _settleTimer;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    widget.focusNode.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() {
    if (!widget.focusNode.hasFocus) return;
    // ה-QuillEditor מקבל פוקוס לפני שאנימציית פתיחת הכרטיס (AnimatedSize)
    // והגלילה של הפאנל הסתיימו. גלילה ראשונה ב-post-frame, ושנייה אחרי
    // שהאנימציה מתייצבת (animPanel ~200ms) כדי לתפוס את המיקום הסופי הנמוך.
    _scrollEditorIntoView();
    _settleTimer?.cancel();
    _settleTimer = Timer(
      const Duration(milliseconds: 250),
      _scrollEditorIntoView,
    );
  }

  void _scrollEditorIntoView() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _editorAreaKey.currentContext;
      if (ctx == null) return;
      // keepVisibleAtEnd גולל רק אם תחתית אזור הכתיבה מוסתרת מתחת לתצוגה —
      // אם הוא כבר גלוי לא מתבצעת גלילה, כך שאין קפיצות מיותרות.
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  Future<void> _insertLink() async {
    final result = await showDialog<PersonalNoteLinkTarget>(
      context: context,
      builder: (context) => PersonalNoteLinkDialog(
        bookId: widget.bookId,
        notes: widget.linkableNotes,
      ),
    );
    if (result == null) return;

    final controller = widget.controller.quillController;
    final selection = controller.selection;

    if (!selection.isCollapsed) {
      controller.formatSelection(quill.LinkAttribute(result.url));
      return;
    }

    final insertText = result.label.isNotEmpty ? result.label : result.url;
    final index = selection.baseOffset;
    controller.document.insert(index, insertText);
    controller.updateSelection(
      TextSelection.collapsed(offset: index + insertText.length),
      quill.ChangeSource.local,
    );
    controller.formatText(
      index,
      insertText.length,
      quill.LinkAttribute(result.url),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final referenceStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w500,
      color: colorScheme.onSurfaceVariant,
    );
    // מגבילים את טקסט ההקשר ל~3 שורות + גלילה פנימית, כדי שטקסט נבחר ארוך
    // לא ידחוף את אזור הכתיבה מטה ומחוץ למסך. הגובה נגזר מסגנון הטקסט בפועל.
    final referenceMaxHeight =
        (referenceStyle?.fontSize ?? 14) * (referenceStyle?.height ?? 1.4) * 3;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.referenceText != null &&
            widget.referenceText!.trim().isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: AppTokens.borderRadiusAll,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: referenceMaxHeight),
              child: SingleChildScrollView(
                child: Text(
                  widget.referenceText!,
                  style: referenceStyle,
                  textAlign: TextAlign.right,
                ),
              ),
            ),
          ),
        Container(
          key: _editorAreaKey,
          decoration: BoxDecoration(
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.6),
              width: 1.2,
            ),
            borderRadius: AppTokens.borderRadiusAll,
          ),
          child: Column(
            children: [
              _PersonalNoteToolbar(
                controller: widget.controller.quillController,
                editorFocusNode: widget.focusNode,
                onInsertLink: _insertLink,
              ),
              const Divider(height: 1),
              SizedBox(
                height: 220,
                // RawGestureDetector תופס מחוות גרירה אנכית באזור העורך
                // לפני שה-ListView ההורה (פאנל ההערות) רואה אותן.
                // אחרת כשהמשתמש גורר אלכסונית כדי לסמן יותר ממילה,
                // ה-VerticalDragGestureRecognizer של ה-ListView מנצח
                // את ה-HorizontalDragGestureRecognizer של Quill,
                // והסימון בעורך כלל לא נוצר.
                // ה-recognizer כאן לא עושה כלום — רק "תופס" את המחווה
                // כדי לא לתת לאב לגלול. גלילה בגלגלת תמשיך לעבוד
                // (היא PointerSignal, לא GestureRecognizer).
                child: RawGestureDetector(
                  behavior: HitTestBehavior.translucent,
                  gestures: <Type, GestureRecognizerFactory>{
                    VerticalDragGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          VerticalDragGestureRecognizer
                        >(
                          () => VerticalDragGestureRecognizer(
                            supportedDevices: const <PointerDeviceKind>{
                              PointerDeviceKind.mouse,
                            },
                          ),
                          (instance) {},
                        ),
                  },
                  child: CallbackShortcuts(
                    bindings: {
                      if (widget.onSaveShortcut != null) ...{
                        // Ctrl+Enter — קיצור השמירה המומלץ (ללא צליל מערכת).
                        const SingleActivator(
                          LogicalKeyboardKey.enter,
                          control: true,
                        ): widget.onSaveShortcut!,
                        // Alt+Enter — נשמר לתאימות לאחור. ב-Windows מפיק
                        // צליל "דינג" של המערכת (מאפיין של צירופי Alt
                        // ב-Flutter), ולכן Ctrl+Enter עדיף.
                        const SingleActivator(
                          LogicalKeyboardKey.enter,
                          alt: true,
                        ): widget.onSaveShortcut!,
                      },
                    },
                    child: quill.QuillEditor(
                      controller: widget.controller.quillController,
                      focusNode: widget.focusNode,
                      scrollController: widget.scrollController,
                      config: quill.QuillEditorConfig(
                        autoFocus: widget.autofocus,
                        expands: false,
                        padding: const EdgeInsets.all(12),
                        placeholder:
                            widget.hintText ??
                            'כתוב כאן... (Ctrl+Enter לשמירה)',
                        customShortcuts: _rtlArrowShortcuts,
                        // Quill מציגה אוטומטית תפריט סלקציה ב-desktop
                        // בסיום גרירה — בהערות אישיות זה מטריד.
                        // יש לנו טולבר משלנו וניתן להשתמש בקיצורי מקלדת
                        // וב-right-click הסטנדרטי של המערכת.
                        enableSelectionToolbar: false,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// מכבה הדבקת Rich-Text מהלוח החיצוני. בלי זה Quill מזהה HTML שמערכת
// ההעתקה של אוצריא מזריקה ללוח (super_native_extensions) וגוררת את
// העיצוב של הספר לתוך ההערה — וגם משפיע על טקסט עתידי שיוקלד באותו מקום.
// ignore: experimental_member_use
const _noteClipboardConfig = quill.QuillClipboardConfig(
  // ignore: experimental_member_use
  enableExternalRichPaste: false,
);
const _noteControllerConfig = quill.QuillControllerConfig(
  // ignore: experimental_member_use
  clipboardConfig: _noteClipboardConfig,
);

PersonalNoteEditorController buildPersonalNoteEditorController({
  required String initialContent,
  required PersonalNoteContentFormat initialFormat,
}) {
  if (initialFormat == PersonalNoteContentFormat.quillDelta &&
      initialContent.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(initialContent) as List<dynamic>;
      final document = quill.Document.fromJson(decoded);
      return PersonalNoteEditorController(
        quillController: quill.QuillController(
          document: document,
          selection: const TextSelection.collapsed(offset: 0),
          config: _noteControllerConfig,
        ),
      );
    } catch (_) {}
  }

  final document = quill.Document()
    ..insert(0, initialContent.trimRight().isEmpty ? '' : '$initialContent\n');
  return PersonalNoteEditorController(
    quillController: quill.QuillController(
      document: document,
      selection: const TextSelection.collapsed(offset: 0),
      config: _noteControllerConfig,
    ),
  );
}

class _PersonalNoteToolbar extends StatelessWidget {
  final quill.QuillController controller;
  final FocusNode editorFocusNode;
  final VoidCallback onInsertLink;

  const _PersonalNoteToolbar({
    required this.controller,
    required this.editorFocusNode,
    required this.onInsertLink,
  });

  static const double _minFontSize = 12;
  static const double _maxFontSize = 32;
  static const double _defaultFontSize = 16;
  static const double _fontSizeStep = 2;

  void _toggleAttribute(quill.Attribute attribute) {
    final selectedAttributes = controller.getSelectionStyle().attributes;
    final isActive = _isAttributeActive(attribute, selectedAttributes);
    controller
      ..skipRequestKeyboard = !attribute.isInline
      ..formatSelection(
        isActive ? quill.Attribute.clone(attribute, null) : attribute,
      );
    // לחיצה על IconButton גוזלת פוקוס מ-QuillEditor, ובדסקטופ Quill לא
    // מחזיר אותו אוטומטית (_keyboardVisible תמיד true). מחזירים פוקוס
    // ידנית כדי שהסמן יישאר נראה ושטקסט שיוקלד יקבל את ה-toggledStyle.
    editorFocusNode.requestFocus();
  }

  double _currentFontSize() {
    final value = controller
        .getSelectionStyle()
        .attributes[quill.Attribute.size.key]
        ?.value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? _defaultFontSize;
    return _defaultFontSize;
  }

  void _adjustFontSize(double delta) {
    final newSize = (_currentFontSize() + delta).clamp(
      _minFontSize,
      _maxFontSize,
    );
    controller.formatSelection(
      quill.Attribute.fromKeyValue(quill.Attribute.size.key, newSize),
    );
    editorFocusNode.requestFocus();
  }

  bool _isAttributeActive(
    quill.Attribute attribute,
    Map<String, quill.Attribute> selectedAttributes,
  ) {
    if (attribute.key == quill.Attribute.list.key ||
        attribute.key == quill.Attribute.header.key ||
        attribute.key == quill.Attribute.script.key ||
        attribute.key == quill.Attribute.align.key ||
        attribute.key == quill.Attribute.background.key) {
      final selectedAttribute = selectedAttributes[attribute.key];
      return selectedAttribute?.value == attribute.value;
    }

    return selectedAttributes.containsKey(attribute.key);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      children: [
        IconButton(
          tooltip: 'מודגש',
          icon: const Icon(FluentIcons.text_bold_24_regular, size: 18),
          onPressed: () => _toggleAttribute(quill.Attribute.bold),
        ),
        IconButton(
          tooltip: 'נטוי',
          icon: const Icon(FluentIcons.text_italic_24_regular, size: 18),
          onPressed: () => _toggleAttribute(quill.Attribute.italic),
        ),
        IconButton(
          tooltip: 'קו תחתי',
          icon: const Icon(FluentIcons.text_underline_24_regular, size: 18),
          onPressed: () => _toggleAttribute(quill.Attribute.underline),
        ),
        IconButton(
          tooltip: 'קו חוצה',
          icon: const Icon(FluentIcons.text_strikethrough_24_regular, size: 18),
          onPressed: () => _toggleAttribute(quill.Attribute.strikeThrough),
        ),
        IconButton(
          tooltip: 'הדגשה',
          icon: const Icon(FluentIcons.circle_highlight_24_regular, size: 18),
          onPressed: () => _toggleAttribute(
            const quill.BackgroundAttribute('#fff59d'),
          ),
        ),
        IconButton(
          tooltip: 'הגדל כתב',
          icon: const Icon(FluentIcons.font_increase_24_regular, size: 18),
          onPressed: () => _adjustFontSize(_fontSizeStep),
        ),
        IconButton(
          tooltip: 'הקטן כתב',
          icon: const Icon(FluentIcons.font_decrease_24_regular, size: 18),
          onPressed: () => _adjustFontSize(-_fontSizeStep),
        ),
        IconButton(
          tooltip: 'כותרת',
          icon: const Icon(FluentIcons.text_header_2_24_regular, size: 18),
          onPressed: () => _toggleAttribute(quill.Attribute.h2),
        ),
        IconButton(
          tooltip: 'רשימה',
          icon: const Icon(FluentIcons.text_bullet_list_24_regular, size: 18),
          onPressed: () => _toggleAttribute(quill.Attribute.ul),
        ),
        IconButton(
          tooltip: 'רשימה ממוספרת',
          icon: const Icon(
            FluentIcons.text_number_list_rtl_24_regular,
            size: 18,
          ),
          onPressed: () => _toggleAttribute(quill.Attribute.ol),
        ),
        IconButton(
          tooltip: 'ציטוט',
          icon: const Icon(FluentIcons.text_quote_24_regular, size: 18),
          onPressed: () => _toggleAttribute(quill.Attribute.blockQuote),
        ),
        IconButton(
          tooltip: 'הוסף קישור',
          icon: const Icon(FluentIcons.link_24_regular, size: 18),
          onPressed: onInsertLink,
        ),
      ],
    );
  }
}

PersonalNoteEditorResult buildPlainTextResult(String text) {
  return PersonalNoteEditorResult(
    content: text.trimRight(),
    contentPlain: text.trimRight(),
    contentFormat: PersonalNoteContentFormat.plain,
  );
}
