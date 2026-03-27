import 'dart:convert';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_link_dialog.dart';

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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.referenceText != null &&
              widget.referenceText!.trim().isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
              ),
              child: Text(
                widget.referenceText!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
              ),
            ),
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.6),
                width: 1.2,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              children: [
                _PersonalNoteToolbar(
                  controller: widget.controller.quillController,
                  onInsertLink: _insertLink,
                ),
                const Divider(height: 1),
                SizedBox(
                  height: 220,
                  child: CallbackShortcuts(
                    bindings: {
                      if (widget.onSaveShortcut != null)
                        const SingleActivator(
                          LogicalKeyboardKey.enter,
                          alt: true,
                        ): widget.onSaveShortcut!,
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
                            widget.hintText ?? 'כתוב כאן... (Alt+Enter לשמירה)',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
        quillController: quill.QuillController(
          document: document,
          selection: const TextSelection.collapsed(offset: 0),
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
    ),
  );
}

class _PersonalNoteToolbar extends StatelessWidget {
  final quill.QuillController controller;
  final VoidCallback onInsertLink;

  const _PersonalNoteToolbar({
    required this.controller,
    required this.onInsertLink,
  });

  void _toggleAttribute(quill.Attribute attribute) {
    final selectedAttributes = controller.getSelectionStyle().attributes;
    final isActive = _isAttributeActive(attribute, selectedAttributes);
    controller
      ..skipRequestKeyboard = !attribute.isInline
      ..formatSelection(
        isActive ? quill.Attribute.clone(attribute, null) : attribute,
      );
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
          tooltip: 'הדגשה',
          icon: const Icon(FluentIcons.circle_highlight_24_regular, size: 18),
          onPressed: () => _toggleAttribute(
            const quill.BackgroundAttribute('#fff59d'),
          ),
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
