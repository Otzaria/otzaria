import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/utils/note_link_detection.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_content_view.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

typedef PersonalNoteLookup = Future<PersonalNote?> Function(String noteId);

/// קישור שאינו להערה, מתוך תוכן ההערה [source].
typedef PersonalNoteLinkHandler =
    void Function(PersonalNote source, String url);

/// מציג את [note] לקריאה בלבד. קישור להערה אחרת מחליף את התצוגה בהערת היעד.
///
/// [onEdit] ו-[onOpenInBook] נקראים אחרי סגירת החלון; [onLinkTap] מקבל
/// קישורים שאינם להערה.
Future<void> showPersonalNoteViewDialog(
  BuildContext context,
  PersonalNote note, {
  String? Function(PersonalNote note)? subtitleFor,
  void Function(PersonalNote note)? onEdit,
  void Function(PersonalNote note)? onOpenInBook,
  PersonalNoteLinkHandler? onLinkTap,
  PersonalNoteLookup? findNote,
}) async {
  PersonalNote? current = note;
  while (current != null && context.mounted) {
    final shown = current;
    current = await showDialogUntilTornDown<PersonalNote>(
      context: context,
      builder: (_) => PersonalNoteViewDialog(
        note: shown,
        subtitle: subtitleFor?.call(shown),
        onEdit: onEdit,
        onOpenInBook: onOpenInBook,
        onLinkTap: onLinkTap,
        findNote: findNote,
      ),
    );
  }
}

/// פותח את ההערה [noteId] מקישור, או מודיע שנמחקה.
Future<void> openLinkedPersonalNote(
  BuildContext context,
  String noteId, {
  PersonalNoteLinkHandler? onLinkTap,
  PersonalNoteLookup? findNote,
}) async {
  final target = await (findNote ?? _storedNote)(noteId);
  if (!context.mounted) return;
  if (target == null) {
    UiSnack.show(NotesMessages.linkedNoteDeleted);
    return;
  }
  await showPersonalNoteViewDialog(
    context,
    target,
    onLinkTap: onLinkTap,
    findNote: findNote,
  );
}

Future<PersonalNote?> _storedNote(String noteId) =>
    PersonalNotesDatabase.instance.getNote(noteId);

class PersonalNoteViewDialog extends StatelessWidget {
  final PersonalNote note;
  final String? subtitle;
  final void Function(PersonalNote note)? onEdit;
  final void Function(PersonalNote note)? onOpenInBook;
  final PersonalNoteLinkHandler? onLinkTap;
  final PersonalNoteLookup? findNote;

  const PersonalNoteViewDialog({
    super.key,
    required this.note,
    this.subtitle,
    this.onEdit,
    this.onOpenInBook,
    this.onLinkTap,
    this.findNote,
  });

  String get _title {
    if (note.isGeneralNote) return 'הערה כללית';
    if (note.isBookNote) return 'הערה על הספר';
    if (!note.hasLocation) return 'הערה ללא מיקום';
    final title = note.title.trim();
    return title.isEmpty ? 'הערה אישית' : title;
  }

  Future<void> _followLink(BuildContext context, String url) async {
    final targetId = personalNoteLinkTarget(url);
    if (targetId == null) {
      onLinkTap?.call(note, url);
      return;
    }
    final target = await (findNote ?? _storedNote)(targetId);
    if (!context.mounted || ModalRoute.of(context)?.isCurrent != true) return;
    if (target == null) {
      UiSnack.show(NotesMessages.linkedNoteDeleted);
      return;
    }
    Navigator.of(context).pop(target);
  }

  void _closeThen(
    BuildContext context,
    void Function(PersonalNote note) action,
  ) {
    Navigator.of(context).pop();
    action(note);
  }

  @override
  Widget build(BuildContext context) {
    final edit = onEdit;
    final openInBook = note.hasLocation && !note.isGeneralNote
        ? onOpenInBook
        : null;
    final content = PersonalNoteContentView(
      note: note,
      onLinkTap: (url) => unawaited(_followLink(context, url)),
    );
    return AppDialogFrame(
      title: _title,
      titleMaxLines: 2,
      subtitle: subtitle,
      icon: FluentIcons.note_24_regular,
      size: AppDialogSize.medium,
      scrollable: true,
      actions: [
        if (openInBook != null)
          ActionButton.neutral(
            text: 'פתח בספר',
            icon: OtzariaIcons.otzaria_icon_2_page_24_regular,
            onPressed: () => _closeThen(context, openInBook),
          ),
        if (edit != null)
          ActionButton.neutral(
            text: 'עריכה',
            icon: FluentIcons.edit_24_regular,
            onPressed: () => _closeThen(context, edit),
          ),
        ActionButton.recommended(
          text: 'סגור',
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      child: note.contentFormat == PersonalNoteContentFormat.plain
          ? AppSelectionArea(child: content)
          : content,
    );
  }
}
