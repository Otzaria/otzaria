import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';

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
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(_DraftDecision.cancel),
            child: const Text('ביטול'),
          ),
          FilledButton.tonal(
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
          scrollable: true,
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
            // minWidth קשיח של 450 חורג מרוחב טלפון וגורם חיתוך — מצמידים
            // לרוחב המסך בפועל (בניכוי שולי הדיאלוג).
            constraints: BoxConstraints(
              maxWidth: 480,
              minWidth: (MediaQuery.sizeOf(context).width - 96).clamp(
                0.0,
                450.0,
              ),
            ),
            child: PersonalNoteEditorBody(
              controller: _editorController,
              focusNode: _textFieldFocusNode,
              scrollController: _scrollController,
              autofocus: true,
              referenceText: widget.referenceText,
              bookId: widget.bookId,
              linkableNotes: widget.linkableNotes,
              onSaveShortcut: _submit,
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
    final cs = Theme.of(context).colorScheme;
    final showHover = isFocused && !_textFieldFocusNode.hasFocus;

    if (isConfirm) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: showHover
              ? cs.primary.withValues(alpha: 0.9)
              : cs.primary,
          foregroundColor: cs.onPrimary,
        ),
        child: Text(text),
      );
    } else {
      return FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: showHover
              ? cs.secondaryContainer.withValues(alpha: 0.9)
              : cs.secondaryContainer,
          foregroundColor: cs.onSecondaryContainer,
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
