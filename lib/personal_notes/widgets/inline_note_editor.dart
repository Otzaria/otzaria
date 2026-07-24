import 'dart:async';

import 'package:flutter/material.dart';

import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/notes_messages.dart';

class InlineNoteEditor extends StatefulWidget {
  final PersonalNote? note;
  final String? referenceText;
  final String bookId;
  final int? categoryId;
  final String initialContent;
  final PersonalNoteContentFormat initialFormat;
  final int? draftLineNumber;
  final String? draftNoteId;
  final List<PersonalNote> linkableNotes;
  final ValueChanged<PersonalNoteEditorResult> onSave;
  final VoidCallback onCancel;

  const InlineNoteEditor({
    super.key,
    this.note,
    this.referenceText,
    required this.bookId,
    this.categoryId,
    this.initialContent = '',
    this.initialFormat = PersonalNoteContentFormat.plain,
    this.draftLineNumber,
    this.draftNoteId,
    required this.linkableNotes,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<InlineNoteEditor> createState() => _InlineNoteEditorState();
}

class _InlineNoteEditorState extends State<InlineNoteEditor> {
  late final PersonalNoteEditorController _controller;
  late final PersonalNoteEditorResult _initialResult;
  final FocusNode _focusNode = FocusNode(debugLabel: 'InlineNoteEditor');
  final ScrollController _scrollController = ScrollController();
  final PersonalNoteDraftService _draftService = PersonalNoteDraftService();
  Timer? _draftSaveTimer;
  Timer? _focusRetryTimer;
  bool _isDone = false; // מונע שמירת טיוטה אחרי שמירה/ביטול

  @override
  void initState() {
    super.initState();
    _controller = buildPersonalNoteEditorController(
      initialContent: widget.initialContent.isNotEmpty
          ? widget.initialContent
          : (widget.note?.content ?? ''),
      initialFormat: widget.initialContent.isNotEmpty
          ? widget.initialFormat
          : (widget.note?.contentFormat ?? PersonalNoteContentFormat.plain),
    );
    // _initialResult מייצג את המצב ה"נקי" לפני עריכה — לא תוכן הטיוטה.
    // כך _persistDraft לא ימחק את הטיוטה כשה-Quill מפעיל notifyListeners בהתחלה.
    final originalController = buildPersonalNoteEditorController(
      initialContent: widget.note?.content ?? '',
      initialFormat:
          widget.note?.contentFormat ?? PersonalNoteContentFormat.plain,
    );
    _initialResult = originalController.buildResult();
    originalController.quillController.dispose();
    _controller.quillController.addListener(_scheduleDraftSave);
    // QuillEditor.autoFocus לא תמיד תופס פוקוס כשהעורך נפתח בתוך פאנל
    // שנפתח דינמית. ה-post-frame הראשון יורה לפני שאנימציית פתיחת הפאנל
    // הסתיימה, ולפעמים ה-FocusNode עוד לא מחובר. ה-Timer מנסה שוב
    // אחרי אורך אנימציה טיפוסי של Material (300ms).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
    _focusRetryTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      if (!_focusNode.hasFocus) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    _focusRetryTimer?.cancel();
    _controller.quillController.removeListener(_scheduleDraftSave);
    unawaited(_persistDraft());
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    // במצב סייפר, נדרוש סיסמה לפני שמירה
    if (!await verifySaferModePassword(context) || !mounted) {
      return;
    }

    final result = _controller.buildResult();
    if (result.contentPlain.trim().isEmpty) {
      UiSnack.showError(NotesMessages.emptyNoteNotSaved);
      return;
    }
    _isDone = true;
    await _clearDraft();
    widget.onSave(result);
  }

  void _scheduleDraftSave() {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_persistDraft()),
    );
  }

  Future<void> _persistDraft() async {
    if (_isDone) return;
    final result = _controller.buildResult();
    final normalizedInitialContent = _initialResult.content.trimRight();
    final normalizedCurrentContent = result.content.trimRight();
    final normalizedInitialPlain = _initialResult.contentPlain.trim();
    final normalizedCurrentPlain = result.contentPlain.trim();

    final matchesInitial =
        normalizedInitialContent == normalizedCurrentContent &&
        normalizedInitialPlain == normalizedCurrentPlain &&
        _initialResult.contentFormat == result.contentFormat;

    if (matchesInitial || normalizedCurrentPlain.isEmpty) {
      await _clearDraft();
      return;
    }

    await _draftService.saveDraft(
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
      ),
    );
  }

  Future<void> _clearDraft() {
    return _draftService.clearDraft(
      bookId: widget.bookId,
      categoryId: widget.categoryId,
      lineNumber: widget.draftLineNumber,
      noteId: widget.draftNoteId,
    );
  }

  Future<void> _handleCancel() async {
    _isDone = true;
    await _clearDraft();
    widget.onCancel();
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
          onSaveShortcut: _handleSave,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _handleCancel,
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
