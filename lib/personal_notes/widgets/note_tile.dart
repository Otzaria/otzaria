import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_content_view.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/personal_notes/widgets/inline_note_editor.dart';

class NoteTile extends StatefulWidget {
  final PersonalNote note;
  final VoidCallback? onTap;
  final ValueChanged<PersonalNoteEditorResult> onSave;
  final VoidCallback onDelete;
  final ValueChanged<String> onLinkTap;
  final bool defaultExpanded;
  final String bookId;
  final int? categoryId;
  final List<PersonalNote> linkableNotes;
  final Widget? extraAction;
  final Color? backgroundColor;
  final Widget? subtitle;

  /// טוקן בקשת הרחבה. כשמשתנה לערך לא-null (לחיצה על סימון inline של שורה זו)
  /// ההערה נפתחת גם אם [defaultExpanded] הוא false.
  final int? expandToken;

  const NoteTile({
    super.key,
    required this.note,
    this.onTap,
    required this.onSave,
    required this.onDelete,
    required this.onLinkTap,
    required this.defaultExpanded,
    required this.bookId,
    this.categoryId,
    required this.linkableNotes,
    this.extraAction,
    this.backgroundColor,
    this.subtitle,
    this.expandToken,
  });

  @override
  State<NoteTile> createState() => _NoteTileState();
}

class _NoteTileState extends State<NoteTile> {
  late bool _isExpanded;
  bool _isInlineEditing = false;
  String? _draftContent;
  PersonalNoteContentFormat? _draftFormat;
  final PersonalNoteDraftService _draftService = PersonalNoteDraftService();
  final ValueNotifier<int> _cancelRequest = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    // נפתח לפי ברירת המחדל, או בכפייה אם הגענו דרך לחיצה על סימון inline.
    _isExpanded = widget.defaultExpanded || widget.expandToken != null;
    _restoreDraftIfExists();
  }

  @override
  void didUpdateWidget(covariant NoteTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // בקשת הרחבה חדשה (לחיצה על סימון inline) — פותחים את ההערה.
    if (widget.expandToken != null &&
        widget.expandToken != oldWidget.expandToken &&
        !_isExpanded) {
      setState(() => _isExpanded = true);
    }
    if (oldWidget.note.id != widget.note.id ||
        oldWidget.bookId != widget.bookId ||
        oldWidget.note.updatedAt != widget.note.updatedAt) {
      _draftContent = null;
      _draftFormat = null;
      _restoreDraftIfExists();
    }
  }

  Future<void> _restoreDraftIfExists() async {
    final draft = await _draftService.loadDraft(
      bookId: widget.bookId,
      categoryId: widget.categoryId,
      noteId: widget.note.id,
    );
    if (!mounted || draft == null) {
      return;
    }

    setState(() {
      _draftContent = draft.content;
      _draftFormat = draft.contentFormat;
      _isExpanded = true;
      _isInlineEditing = true;
    });
  }

  void _startInlineEdit() {
    setState(() {
      _isExpanded = true;
      _isInlineEditing = true;
    });
  }

  void _cancelInlineEdit() {
    setState(() {
      _isInlineEditing = false;
    });
  }

  void _requestInlineEditCancellation() {
    _cancelRequest.value++;
  }

  void _handleSave(PersonalNoteEditorResult result) {
    widget.onSave(result);
    _cancelInlineEdit();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInlineEditing) {
      final titleText = widget.note.displayTitle != null &&
              widget.note.displayTitle!.isNotEmpty
          ? 'עריכת הערה - ${widget.note.displayTitle}'
          : (widget.note.lineNumber != null
              ? 'עריכת הערה - שורה ${widget.note.lineNumber}'
              : 'עריכת הערה');

      return InlineNoteEditorCard(
        icon: FluentIcons.note_edit_24_regular,
        title: titleText,
        onCancelPressed: _requestInlineEditCancellation,
        editor: InlineNoteEditor(
          note: widget.note,
          referenceText: widget.note.displayTitle,
          bookId: widget.bookId,
          categoryId: widget.categoryId,
          initialContent: _draftContent ?? widget.note.content,
          initialFormat: _draftFormat ?? widget.note.contentFormat,
          draftNoteId: widget.note.id,
          linkableNotes: widget.linkableNotes,
          onSave: _handleSave,
          onCancel: _cancelInlineEdit,
          cancelRequest: _cancelRequest,
        ),
      );
    }

    final bgColor =
        widget.backgroundColor ?? Theme.of(context).colorScheme.surface;

    return Column(
      children: [
        InkWell(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
            color: bgColor,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.note.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 4),
                        widget.subtitle!,
                      ],
                    ],
                  ),
                ),
                _NoteActions(
                  onEdit: _startInlineEdit,
                  onDelete: widget.onDelete,
                  isExpanded: _isExpanded,
                  onToggleExpansion: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                  extraAction: widget.extraAction,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _isExpanded
              ? InkWell(
                  onTap: widget.onTap,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 12.0),
                    color: bgColor,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: PersonalNoteContentView(
                        note: widget.note,
                        textStyle: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(height: 1.5),
                        onLinkTap: widget.onLinkTap,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Divider(
          height: 1,
          thickness: 0.5,
          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _cancelRequest.dispose();
    super.dispose();
  }
}

class _NoteActions extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool isExpanded;
  final VoidCallback onToggleExpansion;
  final Widget? extraAction;

  const _NoteActions({
    required this.onEdit,
    required this.onDelete,
    required this.isExpanded,
    required this.onToggleExpansion,
    this.extraAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'עריכה',
          icon: const Icon(FluentIcons.edit_24_regular, size: 18),
          iconSize: 18,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(
            minWidth: 32,
            minHeight: 32,
          ),
          onPressed: onEdit,
        ),
        ?extraAction,
        IconButton(
          tooltip: 'מחיקה',
          icon: const Icon(FluentIcons.delete_24_regular, size: 18),
          iconSize: 18,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(
            minWidth: 32,
            minHeight: 32,
          ),
          onPressed: onDelete,
        ),
        IconButton(
          tooltip: isExpanded ? 'סגור' : 'פתח',
          icon: AnimatedRotation(
            turns: isExpanded ? 0.5 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(
              FluentIcons.chevron_down_24_regular,
              size: 18,
            ),
          ),
          iconSize: 18,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(
            minWidth: 32,
            minHeight: 32,
          ),
          onPressed: onToggleExpansion,
        ),
      ],
    );
  }
}
