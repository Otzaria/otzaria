import 'dart:async';
import 'dart:convert';
import 'package:otzaria/theme/app_tokens.dart';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_link_dialog.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_styles.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

// LEFT/RIGHT swapped (flutter_quill doesn't flip them for RTL). UP/DOWN use
// Quill's adjacentLineAction: Windows input can't find lines across blocks.
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

/// ההשלמה מציינת שהכתיבה הצליחה; כשל משאיר את העורך פתוח עם הטיוטה.
typedef PersonalNoteSaveCallback =
    FutureOr<void> Function(PersonalNoteEditorResult result);

/// בעל בקר Quill והמסמך שלו; יוצר העורך משחרר אותם ב-[dispose].
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

  void dispose() => quillController.dispose();
}

class PersonalNoteEditorBody extends StatefulWidget {
  final PersonalNoteEditorController controller;
  final GlobalKey<quill.EditorState>? editorKey;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final bool autofocus;
  final String? referenceText;
  final String? hintText;
  final List<PersonalNote> linkableNotes;
  final String? bookId;
  final VoidCallback? onSaveShortcut;
  final VoidCallback? onCancelShortcut;

  const PersonalNoteEditorBody({
    super.key,
    required this.controller,
    this.editorKey,
    required this.focusNode,
    required this.scrollController,
    required this.autofocus,
    required this.linkableNotes,
    this.referenceText,
    this.hintText,
    this.bookId,
    this.onSaveShortcut,
    this.onCancelShortcut,
  });

  @override
  State<PersonalNoteEditorBody> createState() => _PersonalNoteEditorBodyState();
}

class _PersonalNoteEditorBodyState extends State<PersonalNoteEditorBody> {
  final _editMenuKey = GlobalKey<AppContextMenuRegionState>();
  PointerDeviceKind? _lastPointerKind;

  // עוטף את אזור הכתיבה כדי לגלול אותו לתוך התצוגה כשהוא יורד מתחת לחלון.
  final GlobalKey _editorAreaKey = GlobalKey();
  Timer? _settleTimer;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant PersonalNoteEditorBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChange);
      widget.focusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    widget.focusNode.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() {
    if (!widget.focusNode.hasFocus) return;
    // הפוקוס קודם לסוף אנימציית פתיחת הכרטיס והגלילה: גלילה ב-post-frame,
    // ושוב אחרי שהאנימציה (~200ms) מתייצבת, כדי לתפוס את המיקום הסופי.
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
      // keepVisibleAtEnd גולל רק כשתחתית אזור הכתיבה מוסתרת; רק הרשימה העוטפת,
      // לא ה-PageView של כרטיסייה מוסתרת.
      Scrollable.maybeOf(ctx)?.position.ensureVisible(
        ctx.findRenderObject()!,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  KeyEventResult? _handleEmptyLineBackspace(KeyEvent event, quill.Node? node) {
    final controller = widget.controller.quillController;
    if (controller.readOnly ||
        !controller.selection.isCollapsed ||
        node is! quill.Line ||
        node.length != 1) {
      return null;
    }
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.windows &&
        const SingleActivator(
          LogicalKeyboardKey.backspace,
          alt: true,
        ).accepts(event, HardwareKeyboard.instance)) {
      // מחיקה עד תחילת שורה ריקה היא טווח ריק. Quill מנסה לקרוא תיבת
      // טקסט שאינה קיימת; בתחילת המסמך נשמר ניקוי עיצוב הבלוק שלו.
      if (controller.selection.start == 0) {
        final style = controller.document.collectStyle(0, 0);
        final blockAttributes = controller
            .getSelectionStyle()
            .values
            .where((attribute) => attribute.scope == quill.AttributeScope.block)
            .toList();
        for (final attribute in blockAttributes) {
          controller.formatSelection(quill.Attribute.clone(attribute, null));
          style.attributes.remove(attribute.key);
        }
        controller.forceToggledStyle(style);
      }
      return KeyEventResult.handled;
    }
    if (!const SingleActivator(
      LogicalKeyboardKey.backspace,
    ).accepts(event, HardwareKeyboard.instance)) {
      return null;
    }
    final attributes = node.toDelta().last.attributes;
    if (attributes?[quill.Attribute.list.key] == null) return null;
    final indent = attributes?[quill.Attribute.indent.key] as int? ?? 0;
    if (indent > 0) {
      controller.indentSelection(false);
    } else {
      controller.formatSelection(
        quill.Attribute.clone(quill.Attribute.list, null),
      );
    }
    return KeyEventResult.handled;
  }

  /// Quill מבקש תפריט גם בסיום גרירה בעכבר, ושם לא מציגים כלום; לחיצה ימנית
  /// פותחת את התפריט מהאזור.
  Widget _touchContextMenu(
    BuildContext context,
    quill.QuillRawEditorState editorState,
  ) {
    if (_lastPointerKind
        case PointerDeviceKind.touch ||
            PointerDeviceKind.stylus ||
            PointerDeviceKind.invertedStylus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        editorState.hideToolbar(false);
        _editMenuKey.currentState?.openMenuAt(
          editorState.contextMenuAnchors.primaryAnchor,
        );
      });
    }
    return const SizedBox.shrink();
  }

  List<AppContextMenuEntry> _buildEditMenu() {
    final controller = widget.controller.quillController;
    final hasSelection = !controller.selection.isCollapsed;
    final hasText = controller.document.length > 1;
    return [
      AppContextMenuEntry(
        label: 'גזור',
        icon: FluentIcons.cut_24_regular,
        enabled: hasSelection,
        // ignore: experimental_member_use
        onTap: () => controller.clipboardSelection(false),
      ),
      AppContextMenuEntry(
        label: 'העתק',
        icon: FluentIcons.copy_24_regular,
        enabled: hasSelection,
        // ignore: experimental_member_use
        onTap: () => controller.clipboardSelection(true),
      ),
      AppContextMenuEntry(
        label: 'הדבק',
        icon: FluentIcons.clipboard_paste_24_regular,
        // ignore: experimental_member_use
        onTap: controller.clipboardPaste,
      ),
      AppContextMenuEntry(
        label: 'בחר הכל',
        icon: FluentIcons.select_all_on_24_regular,
        enabled: hasText,
        onTap: () => controller.updateSelection(
          TextSelection(
            baseOffset: 0,
            extentOffset: controller.document.length - 1,
          ),
          quill.ChangeSource.local,
        ),
      ),
    ];
  }

  Future<void> _insertLink() async {
    final result = await showDialog<PersonalNoteLinkTarget>(
      context: context,
      builder: (context) => PersonalNoteLinkDialog(
        bookId: widget.bookId,
        notes: widget.linkableNotes,
      ),
    );
    if (!mounted || result == null) return;

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
                // במסך נמוך או עם מקלדת פתוחה 220px קבועים דוחקים את כפתור
                // השמירה מחוץ לתצוגה — מצמצמים לפי הגובה הפנוי בפועל.
                height: () {
                  final media = MediaQuery.of(context);
                  final available = media.size.height - media.viewInsets.bottom;
                  return (available * 0.35).clamp(120.0, 220.0);
                }(),
                // תופס גרירה אנכית לפני ה-ListView של הפאנל, שאחרת גובר
                // על גרירת הסימון של Quill; הגלגלת (PointerSignal) עדיין גוללת.
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
                        // Ctrl+Enter (במק Cmd+Enter) — קיצור השמירה המומלץ.
                        ShortcutHelper.activatorFromShortcut('ctrl+enter')!:
                            widget.onSaveShortcut!,
                        // Alt+Enter — לתאימות לאחור.
                        const SingleActivator(
                          LogicalKeyboardKey.enter,
                          alt: true,
                        ): widget.onSaveShortcut!,
                      },
                    },
                    child: AppContextMenuRegion(
                      key: _editMenuKey,
                      // לחיצה ארוכה של Quill גוברת על זו של האזור; במגע התפריט
                      // נפתח מ-contextMenuBuilder.
                      openOnLongPress: false,
                      menuBuilder: (_, _) => _buildEditMenu(),
                      child: Listener(
                        onPointerDown: (event) => _lastPointerKind = event.kind,
                        // Quill לא מבקש פוקוס בגרירת בחירה בעכבר, ובלעדיו
                        // מחיקה והעתקה של הבחירה לא מגיעות לעורך.
                        onPointerUp: (event) {
                          if (event.kind == PointerDeviceKind.mouse &&
                              !widget.focusNode.hasFocus) {
                            widget.focusNode.requestFocus();
                          }
                        },
                        child: quill.QuillEditor(
                          controller: widget.controller.quillController,
                          focusNode: widget.focusNode,
                          scrollController: widget.scrollController,
                          config: quill.QuillEditorConfig(
                            editorKey: widget.editorKey,
                            customStyles: personalNoteStyles(context),
                            autoFocus: widget.autofocus,
                            expands: false,
                            padding: const EdgeInsets.all(12),
                            placeholder:
                                widget.hintText ??
                                'כתוב כאן... (${ShortcutHelper.formatShortcutForDisplay('ctrl+enter')} לשמירה)',
                            customShortcuts: widget.onCancelShortcut == null
                                ? _rtlArrowShortcuts
                                : {
                                    ..._rtlArrowShortcuts,
                                    // Quill דורס התאמת SingleActivator בקיצור המובנה.
                                    // LogicalKeySet משמר את קדימות קיצור הסגירה.
                                    LogicalKeySet(
                                      LogicalKeyboardKey.escape,
                                    ): VoidCallbackIntent(
                                      widget.onCancelShortcut!,
                                    ),
                                  },
                            // ignore: experimental_member_use
                            onKeyPressed: _handleEmptyLineBackspace,
                            contextMenuBuilder: _touchContextMenu,
                          ),
                        ),
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

// בלי ביטול הדבקת Rich-Text, ה-HTML שהעתקת אוצריא שמה בלוח גורר את עיצוב
// הספר לתוך ההערה ולטקסט שיוקלד אחריו.
// ignore: experimental_member_use
const _noteClipboardConfig = quill.QuillClipboardConfig(
  // ignore: experimental_member_use
  enableExternalRichPaste: false,
);
const _noteControllerConfig = quill.QuillControllerConfig(
  // ignore: experimental_member_use
  clipboardConfig: _noteClipboardConfig,
);

class _PersonalNoteQuillController extends quill.QuillController {
  _PersonalNoteQuillController(quill.Document document)
    : super(
        document: document,
        selection: const TextSelection.collapsed(offset: 0),
        config: _noteControllerConfig,
      ) {
    // קריאת הלוח יכולה להסתיים אחרי סגירת העורך והמסמך שלו.
    onReplaceText = (_, _, _) => !_disposed;
  }

  bool _disposed = false;

  @override
  Future<bool> clipboardPaste({VoidCallback? updateEditor}) async {
    if (_disposed) return false;
    // ignore: experimental_member_use
    final handled = await super.clipboardPaste(
      updateEditor: () {
        if (!_disposed) updateEditor?.call();
      },
    );
    return !_disposed && handled;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

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
        quillController: _PersonalNoteQuillController(document),
      );
    } catch (_) {}
  }

  final document = quill.Document()
    ..insert(0, initialContent.trimRight().isEmpty ? '' : '$initialContent\n');
  return PersonalNoteEditorController(
    quillController: _PersonalNoteQuillController(document),
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
    // הכפתור גוזל את הפוקוס, ו-Quill בדסקטופ אינו מחזיר אותו; בלעדיו הסמן
    // נעלם וטקסט שיוקלד לא יקבל את ה-toggledStyle.
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
          icon: const Icon(OtzariaIcons.text_bullet_list_24_regular, size: 18),
          onPressed: () => _toggleAttribute(quill.Attribute.ul),
        ),
        IconButton(
          tooltip: 'רשימה ממוספרת',
          icon: const Icon(
            OtzariaIcons.text_number_list_24_regular,
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
          icon: const Icon(OtzariaIcons.link_24_regular, size: 18),
          onPressed: onInsertLink,
        ),
      ],
    );
  }
}
