import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';
import 'package:otzaria/personal_notes/widgets/note_draft_decision_dialog.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';

class PersonalNoteEditorDialog extends StatefulWidget {
  final String initialContent;
  final PersonalNoteContentFormat initialContentFormat;
  final String title;
  final String? referenceText;
  final IconData? icon;
  final String? bookId;
  final int? categoryId;
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
    this.categoryId,
    this.linkableNotes = const [],
    this.draftLineNumber,
  });

  @override
  State<PersonalNoteEditorDialog> createState() =>
      _PersonalNoteEditorDialogState();
}

class _PersonalNoteEditorDialogState extends State<PersonalNoteEditorDialog>
    with DialogFocusRestorerMixin<PersonalNoteEditorDialog> {
  final FocusNode _textFieldFocusNode = FocusNode();
  final FocusNode _cancelFocusNode = FocusNode();
  final FocusNode _saveFocusNode = FocusNode();
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
    registerDialogFocusRestorer(_textFieldFocusNode);
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
    _cancelFocusNode.dispose();
    _saveFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<bool> _confirmClose() async {
    if (!_hasUnsavedChanges) {
      return true;
    }

    final result = await showNoteDraftDecisionDialog(context);

    if (result == NoteDraftDecision.saveDraft) {
      await _saveDraftIfPossible();
      return true;
    }

    if (result == NoteDraftDecision.discard) {
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

  void _submit() async {
    // במצב סייפר, נדרוש סיסמה לפני שמירה
    if (!await verifySaferModePassword(context) || !mounted) {
      return;
    }

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
      categoryId: widget.categoryId,
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
    await _draftService.clearDraft(
      bookId: bookId,
      categoryId: widget.categoryId,
      lineNumber: lineNumber,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }

        // Ctrl+Enter (במק Cmd+Enter) / Alt+Enter (תאימות לאחור) -
        // שליחת הטופס מכל מקום
        if (ShortcutHelper.matchesShortcut(event, 'ctrl+enter') ||
            (event.logicalKey == LogicalKeyboardKey.enter &&
                HardwareKeyboard.instance.isAltPressed)) {
          _submit();
          return KeyEventResult.handled;
        }

        // אם הפוקוס בשדה הטקסט, אנטר רגיל עושה ירידת שורה
        if (_textFieldFocusNode.hasFocus) {
          return KeyEventResult.ignored;
        }

        // חיצים ואנטר שייכים לכפתור שבפוקוס, לא לפקדי הכותרת והעורך.
        if (_saveFocusNode.hasFocus || _cancelFocusNode.hasFocus) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowRight) {
            (_saveFocusNode.hasFocus ? _cancelFocusNode : _saveFocusNode)
                .requestFocus();
            return KeyEventResult.handled;
          }

          if (event.logicalKey == LogicalKeyboardKey.enter) {
            if (_saveFocusNode.hasFocus) {
              _submit();
            } else {
              _handleCancel();
            }
            return KeyEventResult.handled;
          }
        }

        // Escape - ביטול
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _handleCancel();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      // היציאה שואלת על טיוטה ב-_handleCancel, לא בשאלת הסגירה הכללית.
      child: AppDialogFrame(
        size: AppDialogSize.medium,
        icon: widget.icon ?? FluentIcons.note_edit_24_regular,
        title: widget.title,
        scrollable: true,
        onDismissRequest: _handleCancel,
        actions: [
          ActionButton.neutral(
            focusNode: _cancelFocusNode,
            text: 'ביטול',
            onPressed: _handleCancel,
          ),
          ActionButton.recommended(
            focusNode: _saveFocusNode,
            text: 'שמור',
            onPressed: _submit,
          ),
        ],
        child: PersonalNoteEditorBody(
          controller: _editorController,
          focusNode: _textFieldFocusNode,
          scrollController: _scrollController,
          autofocus: true,
          referenceText: widget.referenceText,
          bookId: widget.bookId,
          linkableNotes: widget.linkableNotes,
          onSaveShortcut: _submit,
          escapeDismisses: true,
        ),
      ),
    );
  }
}
