import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';

class PersonalNoteEditorDialog extends StatefulWidget {
  final String initialContent;
  final PersonalNoteContentFormat initialContentFormat;
  final String title;
  final String? referenceText;
  final IconData? icon;
  final String? bookId;
  final List<PersonalNote> linkableNotes;
  final int? draftLineNumber;

  const PersonalNoteEditorDialog({
    super.key,
    this.initialContent = '',
    this.initialContentFormat = PersonalNoteContentFormat.plain,
    this.title = 'הערה חדשה',
    this.referenceText,
    this.icon,
    this.bookId,
    this.linkableNotes = const [],
    this.draftLineNumber,
  });

  @override
  State<PersonalNoteEditorDialog> createState() =>
      _PersonalNoteEditorDialogState();
}

class _PersonalNoteEditorDialogState extends State<PersonalNoteEditorDialog> {
  int _focusedButtonIndex = 1; // 0 = ביטול, 1 = שמור (ברירת מחדל)
  final FocusNode _textFieldFocusNode = FocusNode();
  late final PersonalNoteEditorController _editorController;
  late final ScrollController _scrollController;
  late final PersonalNoteEditorResult _initialResult;
  final PersonalNoteDraftService _draftService = PersonalNoteDraftService();
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _editorController = buildPersonalNoteEditorController(
      initialContent: widget.initialContent,
      initialFormat: widget.initialContentFormat,
    );
    _initialResult = _editorController.buildResult();
    _editorController.quillController.addListener(_checkForChanges);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _textFieldFocusNode.requestFocus();
    });
  }

  void _checkForChanges() {
    final current = _editorController.buildResult();
    final hasChanges =
        current.contentPlain.trim() != _initialResult.contentPlain.trim() &&
            current.contentPlain.trim().isNotEmpty;
    if (hasChanges != _hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = hasChanges;
      });
    }
  }

  @override
  void dispose() {
    _editorController.quillController.removeListener(_checkForChanges);
    _textFieldFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<bool> _confirmClose() async {
    if (!_hasUnsavedChanges) {
      return true;
    }

    final result = await showDialog<_DraftDecision>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('אזהרה'),
        content: const Text('ההערה לא נשמרה. לשמור טיוטה?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_DraftDecision.cancel),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_DraftDecision.discard),
            child: const Text('סגור בלי לשמור'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_DraftDecision.saveDraft),
            child: const Text('שמור טיוטה'),
          ),
        ],
      ),
    );

    if (result == _DraftDecision.saveDraft) {
      await _saveDraftIfPossible();
      return true;
    }

    if (result == _DraftDecision.discard) {
      return true;
    }

    return false;
  }

  Future<void> _handleCancel() async {
    if (await _confirmClose()) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _submit() {
    final result = _editorController.buildResult();
    if (result.contentPlain.trim().isEmpty) {
      return;
    }
    _clearDraftIfPossible();
    Navigator.of(context).pop(result);
  }

  Future<void> _saveDraftIfPossible() async {
    final bookId = widget.bookId;
    final lineNumber = widget.draftLineNumber;
    if (bookId == null || lineNumber == null) return;
    final result = _editorController.buildResult();
    if (result.contentPlain.trim().isEmpty) return;
    await _draftService.saveDraft(
      bookId: bookId,
      lineNumber: lineNumber,
      draft: PersonalNoteDraft(
        content: result.content,
        contentPlain: result.contentPlain,
        contentFormat: result.contentFormat,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _clearDraftIfPossible() async {
    final bookId = widget.bookId;
    final lineNumber = widget.draftLineNumber;
    if (bookId == null || lineNumber == null) return;
    await _draftService.clearDraft(bookId: bookId, lineNumber: lineNumber);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }

        // Alt + Enter - שליחת הטופס מכל מקום
        if (event.logicalKey == LogicalKeyboardKey.enter &&
            HardwareKeyboard.instance.isAltPressed) {
          _submit();
          return KeyEventResult.handled;
        }

        // אם הפוקוס בשדה הטקסט, אנטר רגיל עושה ירידת שורה
        if (_textFieldFocusNode.hasFocus) {
          return KeyEventResult.ignored;
        }

        // אם הפוקוס בכפתורים - חיצים ואנטר
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.arrowRight) {
          setState(() {
            _focusedButtonIndex = _focusedButtonIndex == 0 ? 1 : 0;
          });
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.enter) {
          if (_focusedButtonIndex == 1) {
            _submit();
          } else {
            _handleCancel();
          }
          return KeyEventResult.handled;
        }

        // Escape - ביטול
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _handleCancel();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await _handleCancel();
        },
        child: AlertDialog(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                widget.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 480,
              minWidth: 450,
            ),
            child: PersonalNoteEditorBody(
              controller: _editorController,
              focusNode: _textFieldFocusNode,
              scrollController: _scrollController,
              autofocus: true,
              referenceText: widget.referenceText,
              bookId: widget.bookId,
              linkableNotes: widget.linkableNotes,
            ),
          ),
          actions: [
            _buildButton(
              text: 'ביטול',
              isFocused: _focusedButtonIndex == 0,
              onPressed: _handleCancel,
            ),
            _buildButton(
              text: 'שמור',
              isFocused: _focusedButtonIndex == 1,
              isConfirm: true,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton({
    required String text,
    required bool isFocused,
    required VoidCallback onPressed,
    bool isConfirm = false,
  }) {
    final showHover = isFocused && !_textFieldFocusNode.hasFocus;

    if (isConfirm) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: showHover
              ? Theme.of(context).primaryColor.withValues(alpha: 0.9)
              : null,
        ),
        child: Text(text),
      );
    } else {
      return TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: showHover
              ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
              : null,
        ),
        child: Text(text),
      );
    }
  }
}

enum _DraftDecision {
  saveDraft,
  discard,
  cancel,
}
