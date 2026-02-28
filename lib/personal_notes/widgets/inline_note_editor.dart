import 'package:flutter/material.dart';

import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/settings/safer_mode/protected_settings_wrapper.dart';
import 'package:otzaria/core/scaffold_messenger.dart';

class InlineNoteEditor extends StatefulWidget {
  final PersonalNote? note;
  final String? referenceText;
  final String bookId;
  final List<PersonalNote> linkableNotes;
  final ValueChanged<PersonalNoteEditorResult> onSave;
  final VoidCallback onCancel;

  const InlineNoteEditor({
    super.key,
    this.note,
    this.referenceText,
    required this.bookId,
    required this.linkableNotes,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<InlineNoteEditor> createState() => _InlineNoteEditorState();
}

class _InlineNoteEditorState extends State<InlineNoteEditor> {
  late final PersonalNoteEditorController _controller;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = buildPersonalNoteEditorController(
      initialContent: widget.note?.content ?? '',
      initialFormat:
          widget.note?.contentFormat ?? PersonalNoteContentFormat.plain,
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleSave() async {
    // במצב מוגן, נדרוש סיסמה לפני שמירה
    if (!await verifyPasswordForAction(context) || !mounted) {
      return;
    }

    final result = _controller.buildResult();
    if (result.contentPlain.trim().isEmpty) {
      UiSnack.showError('ההערה ריקה, לא נשמרה');
      return;
    }
    widget.onSave(result);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PersonalNoteEditorBody(
          controller: _controller,
          focusNode: _focusNode,
          scrollController: _scrollController,
          autofocus: true,
          referenceText: widget.referenceText,
          bookId: widget.bookId,
          linkableNotes: widget.linkableNotes,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: widget.onCancel,
              child: const Text('ביטול'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _handleSave,
              child: const Text('שמור'),
            ),
          ],
        ),
      ],
    );
  }
}
