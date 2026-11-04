import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_content_view.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/personal_notes/widgets/inline_note_editor.dart';
import 'package:otzaria/theme/app_motion.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/controls/app_icon_button.dart';

class NoteTile extends StatefulWidget {
  final PersonalNote note;
  final VoidCallback? onTap;
  final PersonalNoteSaveCallback onSave;
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

  Future<void> _startInlineEdit() async {
    final draft = await _draftService.loadDraft(
      bookId: widget.bookId,
      categoryId: widget.categoryId,
      noteId: widget.note.id,
    );
    if (!mounted) return;
    setState(() {
      _draftContent = draft?.content;
      _draftFormat = draft?.contentFormat;
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

  void _finishSave() {
    if (!mounted) return;
    setState(() {
      _draftContent = null;
      _draftFormat = null;
      _isInlineEditing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isInlineEditing) {
      final titleText =
          widget.note.displayTitle != null &&
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
          onSave: widget.onSave,
          onSaved: _finishSave,
          onCancel: _cancelInlineEdit,
          cancelRequest: _cancelRequest,
        ),
      );
    }

    // כרטיס מעוגל, מוזח פנימה מקצות החלונית, ברקע [backgroundColor] (בלעדיו
    // שקוף); כותרת ותוכן הם יחידה אחת, והריחוף והלחיצה נצבעים עליו. בין
    // כרטיסים אין קו: הריפוד האנכי (spaceXS מכל צד) נותן רווח של spaceSM.
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceSM,
        vertical: AppTokens.spaceXS,
      ),
      // Material לכל שורה ולא Ink: ה-ink נצבע על ה-Material הקרוב, ובחלונית
      // זה ה-Material שמחוץ לרשימה, שלא נצבע מחדש כשהשורה זזה.
      child: Material(
        type: widget.backgroundColor == null
            ? MaterialType.transparency
            : MaterialType.canvas,
        color: widget.backgroundColor,
        borderRadius: AppTokens.borderRadiusAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: AppTokens.borderRadiusAll,
          child: Column(
            children: [
              _buildHeader(context),
              AnimatedSize(
                duration: AppMotion.duration(
                  context,
                  AppTokens.animPanelOpacity,
                ),
                curve: Curves.easeInOut,
                child: _isExpanded
                    ? Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          AppTokens.spaceSM,
                          0,
                          AppTokens.spaceSM,
                          AppTokens.spaceSM,
                        ),
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
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppTokens.spaceSM),
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
        AppIconButton(
          size: AppIconButtonSize.small,
          tooltip: 'עריכה',
          icon: const Icon(FluentIcons.edit_24_regular),
          onPressed: onEdit,
        ),
        ?extraAction,
        AppIconButton(
          size: AppIconButtonSize.small,
          tooltip: 'מחיקה',
          icon: const Icon(FluentIcons.delete_24_regular),
          onPressed: onDelete,
        ),
        AppIconButton(
          size: AppIconButtonSize.small,
          tooltip: isExpanded ? 'סגור' : 'פתח',
          icon: AnimatedRotation(
            turns: isExpanded ? 0.5 : 0.0,
            duration: AppMotion.duration(context, AppTokens.animPanelOpacity),
            child: const Icon(FluentIcons.chevron_down_24_regular),
          ),
          onPressed: onToggleExpansion,
        ),
      ],
    );
  }
}
