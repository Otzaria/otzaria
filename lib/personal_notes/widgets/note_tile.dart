import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:otzaria/personal_notes/models/personal_note.dart';
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
  final List<PersonalNote> linkableNotes;
  final Widget? extraAction;
  final Color? backgroundColor;
  final Widget? subtitle;

  const NoteTile({
    super.key,
    required this.note,
    this.onTap,
    required this.onSave,
    required this.onDelete,
    required this.onLinkTap,
    required this.defaultExpanded,
    required this.bookId,
    required this.linkableNotes,
    this.extraAction,
    this.backgroundColor,
    this.subtitle,
  });

  @override
  State<NoteTile> createState() => _NoteTileState();
}

class _NoteTileState extends State<NoteTile> {
  late bool _isExpanded;
  bool _isInlineEditing = false;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.defaultExpanded;
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

  void _handleSave(PersonalNoteEditorResult result) {
    widget.onSave(result);
    _cancelInlineEdit();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor =
        widget.backgroundColor ?? Theme.of(context).colorScheme.surface;

    return Column(
      children: [
        InkWell(
          onTap: widget.onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            color: bgColor,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.note.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
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
                      child: _isInlineEditing
                          ? InlineNoteEditor(
                              note: widget.note,
                              referenceText: widget.note.displayTitle,
                              bookId: widget.bookId,
                              linkableNotes: widget.linkableNotes,
                              onSave: _handleSave,
                              onCancel: _cancelInlineEdit,
                            )
                          : PersonalNoteContentView(
                              note: widget.note,
                              textStyle: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(height: 1.5),
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
        if (extraAction != null) extraAction!,
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
