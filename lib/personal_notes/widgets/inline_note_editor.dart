import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';
import 'package:otzaria/personal_notes/widgets/note_draft_decision_dialog.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/core/messages/text_book_messages.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

class InlineNoteEditor extends StatefulWidget {
  final PersonalNote? note;
  final String? referenceText;
  final String bookId;
  final int? categoryId;
  final String initialContent;
  final PersonalNoteContentFormat initialFormat;
  final int? draftLineNumber;
  final PdfNoteAnchor? pdfAnchor;
  final String? draftNoteId;
  final List<PersonalNote> linkableNotes;
  final PersonalNoteSaveCallback onSave;

  /// השלמה לוגית לאחר כתיבה וניקוי הטיוטה; עשויה להגיע אחרי הסרת העורך.
  final VoidCallback? onSaved;
  final VoidCallback onCancel;
  final ValueListenable<int>? cancelRequest;

  const InlineNoteEditor({
    super.key,
    this.note,
    this.referenceText,
    required this.bookId,
    this.categoryId,
    this.initialContent = '',
    this.initialFormat = PersonalNoteContentFormat.plain,
    this.draftLineNumber,
    this.pdfAnchor,
    this.draftNoteId,
    required this.linkableNotes,
    required this.onSave,
    this.onSaved,
    required this.onCancel,
    this.cancelRequest,
  });

  @override
  State<InlineNoteEditor> createState() => _InlineNoteEditorState();
}

class _InlineNoteEditorState extends State<InlineNoteEditor> {
  late final PersonalNoteEditorController _controller;
  late final PersonalNoteEditorResult _initialResult;
  late PersonalNoteEditorResult _draftResult;
  late final StreamSubscription<quill.DocChange> _documentChanges;
  final GlobalKey<quill.EditorState> _editorKey = GlobalKey();
  final FocusNode _focusNode = FocusNode(debugLabel: 'InlineNoteEditor');
  final ScrollController _scrollController = ScrollController();
  final PersonalNoteDraftService _draftService = PersonalNoteDraftService();
  Object? _draftVersion;
  Timer? _draftSaveTimer;
  Timer? _focusRetryTimer;
  bool _isDone = false; // מונע שמירת טיוטה אחרי שמירה/ביטול
  bool _isSaving = false;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _draftVersion = _currentDraftVersion();
    _controller = buildPersonalNoteEditorController(
      initialContent: widget.initialContent.isNotEmpty
          ? widget.initialContent
          : (widget.note?.content ?? ''),
      initialFormat: widget.initialContent.isNotEmpty
          ? widget.initialFormat
          : (widget.note?.contentFormat ?? PersonalNoteContentFormat.plain),
    );
    _draftResult = _controller.buildResult();
    // _initialResult מייצג את המצב ה"נקי" לפני עריכה — לא תוכן הטיוטה.
    // כך _persistDraft לא ימחק את הטיוטה כשה-Quill מפעיל notifyListeners בהתחלה.
    final originalController = buildPersonalNoteEditorController(
      initialContent: widget.note?.content ?? '',
      initialFormat:
          widget.note?.contentFormat ?? PersonalNoteContentFormat.plain,
    );
    try {
      _initialResult = originalController.buildResult();
    } finally {
      originalController.dispose();
    }
    _documentChanges = _controller.quillController.changes.listen(
      (_) => _scheduleDraftSave(),
    );
    widget.cancelRequest?.addListener(_handleCancelRequest);
    // autoFocus לא תמיד תופס בפאנל שנפתח דינמית: ה-post-frame עלול לקדום לסוף
    // אנימציית הפתיחה, ולכן ניסיון נוסף אחרי שהיא מסתיימת.
    _scheduleFocusAfterLayout();
    _focusRetryTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      if (!_focusNode.hasFocus) _scheduleFocusAfterLayout();
    });
  }

  void _scheduleFocusAfterLayout({bool retry = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isSaving || _isDone) return;
      final editor = _editorKey.currentState?.renderEditor;
      if (editor != null && editor.attached && editor.hasSize) {
        _focusNode.requestFocus();
      } else if (retry) {
        // חשיפת פריט ברשימה וירטואלית נפרסת רק בפריים שאחרי jumpTo.
        _scheduleFocusAfterLayout(retry: false);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didUpdateWidget(covariant InlineNoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cancelRequest != widget.cancelRequest) {
      oldWidget.cancelRequest?.removeListener(_handleCancelRequest);
      widget.cancelRequest?.addListener(_handleCancelRequest);
    }
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    _focusRetryTimer?.cancel();
    unawaited(_documentChanges.cancel());
    widget.cancelRequest?.removeListener(_handleCancelRequest);
    // _persistDraft אוסף את התוכן לפני ה-await הראשון, גם לפני ה-debounce.
    _persistDraftInBackground();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_isDone || _isSaving || _isClosing) return;
    final result = _controller.buildResult();
    final onSave = widget.onSave;
    final onSaved = widget.onSaved;
    if (result.contentPlain.trim().isEmpty) {
      UiSnack.showError(NotesMessages.emptyNoteNotSaved);
      return;
    }
    setState(() {
      _isSaving = true;
      _controller.quillController.readOnly = true;
    });
    try {
      if (!await verifySaferModePassword(context) || !mounted) return;
      await onSave(result);
      _isDone = true;
      _draftSaveTimer?.cancel();
      var clearedDraft = true;
      try {
        await _clearDraft();
      } catch (_) {
        clearedDraft = false;
      }
      if (mounted) {
        if (clearedDraft) {
          UiSnack.showSuccess(
            widget.note == null
                ? NotesMessages.noteSaved
                : NotesMessages.noteUpdated,
          );
        } else {
          UiSnack.showWarning(NotesMessages.noteSavedDraftCleanupFailed);
        }
      }
      onSaved?.call();
    } catch (error) {
      if (mounted) UiSnack.showError(TextBookMessages.noteSaveError(error));
    } finally {
      if (mounted && !_isDone) {
        setState(() {
          _isSaving = false;
          _controller.quillController.readOnly = false;
        });
        _scheduleFocusAfterLayout();
      }
    }
  }

  void _scheduleDraftSave() {
    if (_isDone) return;
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(
      const Duration(milliseconds: 250),
      _persistDraftInBackground,
    );
  }

  void _persistDraftInBackground() {
    unawaited(
      _persistDraft().catchError((Object error) {
        debugPrint('Personal note draft autosave failed: $error');
      }),
    );
  }

  Future<void> _persistDraft() async {
    if (_isDone) return;
    final result = _controller.buildResult();
    // עורך ששוחזר בזמן כתיבה עשוי להיסגר לאחר שהמקור כבר נשמר ונוקה.
    // תוכן חדש שלא הספיק ל-debounce עדיין נשמר, אך צילום ישן אינו מוחזר.
    if (!identical(_draftVersion, _currentDraftVersion()) &&
        _matchesResult(_draftResult, result)) {
      return;
    }
    if (_matchesInitial(result) || result.contentPlain.trim().isEmpty) {
      final clearedVersion = _draftVersion;
      _draftResult = result;
      await _clearDraft();
      if (identical(_draftVersion, clearedVersion)) {
        if (_currentDraftVersion() == null) _draftVersion = null;
      }
      return;
    }

    final write = _draftService.saveDraft(
      bookId: widget.bookId,
      categoryId: widget.categoryId,
      lineNumber: widget.draftLineNumber,
      noteId: widget.draftNoteId,
      draft: PersonalNoteDraft(
        content: result.content,
        contentPlain: result.contentPlain,
        contentFormat: result.contentFormat,
        updatedAt: DateTime.now(),
        lineNumber: widget.draftLineNumber,
        noteId: widget.draftNoteId,
        referenceText: widget.referenceText ?? widget.note?.displayTitle,
        pdfAnchor: widget.pdfAnchor ?? widget.note?.pdfAnchor,
      ),
    );
    // saveDraft קובע את הגרסה לפני ה-await הראשון, גם כשכתיבת Hive ממתינה.
    _draftVersion = _currentDraftVersion();
    _draftResult = result;
    await write;
  }

  bool _matchesInitial(PersonalNoteEditorResult result) =>
      _matchesResult(_initialResult, result);

  bool _matchesResult(
    PersonalNoteEditorResult first,
    PersonalNoteEditorResult second,
  ) {
    return first.content.trimRight() == second.content.trimRight() &&
        first.contentPlain.trim() == second.contentPlain.trim() &&
        first.contentFormat == second.contentFormat;
  }

  Future<void> _clearDraft() {
    return _draftService.clearDraft(
      bookId: widget.bookId,
      categoryId: widget.categoryId,
      lineNumber: widget.draftLineNumber,
      noteId: widget.draftNoteId,
      pdfAnchor: widget.pdfAnchor ?? widget.note?.pdfAnchor,
      expectedVersion: _draftVersion,
    );
  }

  Object? _currentDraftVersion() => _draftService.draftVersion(
    bookId: widget.bookId,
    categoryId: widget.categoryId,
    lineNumber: widget.draftLineNumber,
    noteId: widget.draftNoteId,
    pdfAnchor: widget.pdfAnchor ?? widget.note?.pdfAnchor,
  );

  Future<void> _handleCancel() async {
    if (_isDone || _isSaving || _isClosing) return;
    _isClosing = true;
    try {
      if (_hasUnsavedChanges()) {
        final decision = await showNoteDraftDecisionDialog(context);
        if (!mounted ||
            decision == null ||
            decision == NoteDraftDecision.cancel) {
          return;
        }
        if (decision == NoteDraftDecision.saveDraft) {
          await _persistDraft();
          if (!mounted) return;
          _isDone = true;
          widget.onCancel();
          return;
        }
      }
      await _clearDraft();
      _isDone = true;
      if (mounted) widget.onCancel();
    } catch (error) {
      if (mounted) UiSnack.showError(NotesMessages.noteDraftUpdateError(error));
    } finally {
      _isClosing = false;
    }
  }

  bool _hasUnsavedChanges() {
    final current = _controller.buildResult();
    return current.contentPlain.trim().isNotEmpty && !_matchesInitial(current);
  }

  void _handleCancelRequest() {
    unawaited(_handleCancel());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeFocus(
          excluding: _isSaving,
          child: AbsorbPointer(
            absorbing: _isSaving,
            child: PersonalNoteEditorBody(
              controller: _controller,
              editorKey: _editorKey,
              focusNode: _focusNode,
              scrollController: _scrollController,
              autofocus: false,
              referenceText: widget.referenceText,
              bookId: widget.bookId,
              linkableNotes: widget.linkableNotes,
              onSaveShortcut: _handleSave,
            ),
          ),
        ),
        const SizedBox(height: AppTokens.spaceSM),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ActionButton.ghost(
              text: 'ביטול',
              onPressed: _isSaving ? null : _handleCancel,
            ),
            const SizedBox(width: AppTokens.spaceSM),
            ActionButton.recommended(
              text: 'שמור',
              onPressed: _isSaving ? null : _handleSave,
            ),
          ],
        ),
      ],
    );
  }
}

/// מסגרת עורך הערה בתוך הרשימה: כותרת עם אייקון וכפתור ביטול מעל [editor].
class InlineNoteEditorCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onCancelPressed;
  final InlineNoteEditor editor;

  const InlineNoteEditorCard({
    super.key,
    required this.icon,
    required this.title,
    required this.onCancelPressed,
    required this.editor,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppSurfaces.noteEditorBackground(context),
        borderRadius: AppTokens.borderRadiusAll,
        border: Border.all(color: primary, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.bold, color: primary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'ביטול',
                icon: const Icon(FluentIcons.dismiss_24_regular),
                onPressed: onCancelPressed,
                iconSize: 20,
              ),
            ],
          ),
          const SizedBox(height: 8),
          editor,
        ],
      ),
    );
  }
}
