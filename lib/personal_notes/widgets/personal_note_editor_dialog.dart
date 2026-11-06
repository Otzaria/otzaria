import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/core/messages/text_book_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';
import 'package:otzaria/personal_notes/widgets/note_draft_decision_dialog.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';

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
  final String? draftNoteId;
  final PdfNoteAnchor? pdfAnchor;
  final Future<void> Function(PersonalNoteEditorResult)? onSave;

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
    this.draftNoteId,
    this.pdfAnchor,
    this.onSave,
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
  Object? _draftVersion;
  bool _isSaving = false;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _draftVersion = _currentDraftVersion();
    _scrollController = ScrollController();
    _editorController = buildPersonalNoteEditorController(
      initialContent: widget.initialContent,
      initialFormat: widget.initialContentFormat,
    );
    _initialResult = _editorController.buildResult();
    registerDialogFocusRestorer(_textFieldFocusNode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _textFieldFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _editorController.dispose();
    _textFieldFocusNode.dispose();
    _cancelFocusNode.dispose();
    _saveFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<bool> _confirmClose() async {
    final current = _editorController.buildResult();
    if (current.content == _initialResult.content ||
        current.contentPlain.trim().isEmpty) {
      return true;
    }

    final result = await showNoteDraftDecisionDialog(context);
    if (!mounted) return false;

    if (result == NoteDraftDecision.saveDraft) {
      await _saveDraftIfPossible();
      return true;
    }

    if (result == NoteDraftDecision.discard) {
      await _clearDraftIfPossible();
      return true;
    }

    return false;
  }

  Future<void> _handleCancel() async {
    if (_isSaving || _isClosing) return;
    _isClosing = true;
    try {
      if (await _confirmClose() && mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) UiSnack.showError(NotesMessages.noteDraftUpdateError(error));
    } finally {
      _isClosing = false;
    }
  }

  Future<void> _submit() async {
    if (_isSaving || _isClosing) return;
    final result = _editorController.buildResult();
    if (result.contentPlain.trim().isEmpty) return;
    setState(() {
      _isSaving = true;
      _editorController.quillController.readOnly = true;
    });
    var completed = false;
    try {
      if (!await verifySaferModePassword(context) || !mounted) return;
      await widget.onSave?.call(result);
      if (widget.onSave == null) {
        await _clearDraftIfPossible();
      } else {
        // ההערה כבר נכתבה. כשל בניקוי טיוטה אינו כשל שמירה, ואסור
        // להשאיר כפתור שמירה פעיל שייצור עותק נוסף של אותה הערה.
        try {
          await _clearDraftIfPossible();
          if (mounted) UiSnack.showSuccess(NotesMessages.noteSaved);
        } catch (_) {
          if (mounted) {
            UiSnack.showWarning(NotesMessages.noteSavedDraftCleanupFailed);
          }
        }
      }
      completed = true;
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (mounted) {
        UiSnack.showError(TextBookMessages.noteSaveError(error));
      }
    } finally {
      if (mounted && !completed) {
        setState(() {
          _isSaving = false;
          _editorController.quillController.readOnly = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _textFieldFocusNode.requestFocus();
        });
      }
    }
  }

  Future<void> _saveDraftIfPossible() async {
    final bookId = widget.bookId;
    final noteId = widget.draftNoteId;
    final lineNumber = noteId == null ? widget.draftLineNumber : null;
    if (bookId == null || (lineNumber == null && noteId == null)) return;
    final result = _editorController.buildResult();
    if (result.contentPlain.trim().isEmpty) return;
    final write = _draftService.saveDraft(
      bookId: bookId,
      categoryId: widget.categoryId,
      lineNumber: lineNumber,
      noteId: noteId,
      draft: PersonalNoteDraft(
        content: result.content,
        contentPlain: result.contentPlain,
        contentFormat: result.contentFormat,
        updatedAt: DateTime.now(),
        referenceText: widget.referenceText,
        pdfAnchor: widget.pdfAnchor,
      ),
    );
    _draftVersion = _currentDraftVersion();
    await write;
  }

  Future<void> _clearDraftIfPossible() async {
    final bookId = widget.bookId;
    final noteId = widget.draftNoteId;
    final lineNumber = noteId == null ? widget.draftLineNumber : null;
    if (bookId == null || (lineNumber == null && noteId == null)) return;
    await _draftService.clearDraft(
      bookId: bookId,
      categoryId: widget.categoryId,
      lineNumber: lineNumber,
      noteId: noteId,
      pdfAnchor: widget.pdfAnchor,
      expectedVersion: _draftVersion,
    );
  }

  Object? _currentDraftVersion() {
    final bookId = widget.bookId;
    final noteId = widget.draftNoteId;
    final lineNumber = noteId == null ? widget.draftLineNumber : null;
    if (bookId == null || (lineNumber == null && noteId == null)) return null;
    return _draftService.draftVersion(
      bookId: bookId,
      categoryId: widget.categoryId,
      lineNumber: lineNumber,
      noteId: noteId,
      pdfAnchor: widget.pdfAnchor,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }

        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _handleCancel();
          return KeyEventResult.handled;
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

        return KeyEventResult.ignored;
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await _handleCancel();
        },
        child: Dialog(
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            // minWidth קשיח חורג מרוחב טלפון וגורם חיתוך — מצמידים לרוחב
            // המסך בפועל (בניכוי שולי הדיאלוג).
            constraints: BoxConstraints(
              maxWidth: _maxWidth,
              minWidth: (MediaQuery.sizeOf(context).width - 80).clamp(
                0.0,
                _maxWidth,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppDialogHeader(
                  icon: widget.icon ?? FluentIcons.note_edit_24_regular,
                  title: widget.title,
                  compact: true,
                  onClose: _handleCancel,
                  closeEnabled: !_isSaving,
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppTokens.spaceLG,
                      AppTokens.spaceMD,
                      AppTokens.spaceLG,
                      0,
                    ),
                    child: ExcludeFocus(
                      excluding: _isSaving,
                      child: AbsorbPointer(
                        absorbing: _isSaving,
                        child: PersonalNoteEditorBody(
                          controller: _editorController,
                          focusNode: _textFieldFocusNode,
                          scrollController: _scrollController,
                          autofocus: true,
                          referenceText: widget.referenceText,
                          bookId: widget.bookId,
                          linkableNotes: widget.linkableNotes,
                          onSaveShortcut: _submit,
                          onCancelShortcut: _handleCancel,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceMD),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ActionButton.neutral(
                        focusNode: _cancelFocusNode,
                        text: 'ביטול',
                        onPressed: _isSaving ? null : _handleCancel,
                      ),
                      const SizedBox(width: AppTokens.spaceSM),
                      ActionButton.recommended(
                        focusNode: _saveFocusNode,
                        text: 'שמור',
                        onPressed: _isSaving ? null : _submit,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// רוחב הדיאלוג: גוף העורך (480) ועוד ריפוד אופקי.
  static const double _maxWidth = 480 + AppTokens.spaceLG * 2;
}
