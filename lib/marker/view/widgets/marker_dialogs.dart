import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/messages/marker_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/models/marker_text.dart';
import 'package:otzaria/marker/repository/marker_repository.dart';
import 'package:otzaria/marker/services/marker_actions.dart';
import 'package:otzaria/marker/services/marker_note_requests.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor_dialog.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

String markerQuote(String text, [int max = 60]) {
  final cut = truncateGraphemes(text, max);
  return cut == text ? text : '$cut…';
}

/// עורך את ההערה של [mark] בעורך ההערות האישיות. כשהקורא מציג חלונית
/// הערות ([openNotes]), העורך נפתח בה, כמו הערה אישית על הספר; אחרת — בחלון
/// קופץ, כמו הערה על מפרש. טיוטה שלא נשמרה נטענת מחדש, ועריכה שנעשתה
/// בינתיים בחלון אחר אינה נדרסת בלי אישור.
Future<void> editMarkerNote(
  BuildContext context,
  MarkerHighlight mark, {
  VoidCallback? openNotes,
}) async {
  if (openNotes != null) {
    MarkerNoteRequests.open(mark.id);
    openNotes();
    // חלונית שלא הציגה את העורך (למשל כשהרשימה בה גלולה הרחק מראשה) — העורך
    // נפתח בחלון קופץ, ולא נעלם בשקט.
    await Future<void>.delayed(const Duration(seconds: 1));
    if (MarkerNoteRequests.isShown(mark.id) ||
        !MarkerNoteRequests.editing.value.contains(mark.id)) {
      return;
    }
    MarkerNoteRequests.close(mark.id);
    if (!context.mounted) return;
  }
  final drafts = PersonalNoteDraftService();
  final draftId = markerNoteDraftId(mark);
  final draft = await drafts.loadDraft(
    bookId: mark.bookTitle,
    noteId: draftId,
  );
  if (!context.mounted) return;
  if (draft != null) UiSnack.showQuick(MarkerMessages.draftRestored);
  final result = await showDialog<PersonalNoteEditorResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PersonalNoteEditorDialog(
      title: mark.hasNote ? 'עריכת הערה לסימון' : 'הערה לסימון',
      icon: FluentIcons.note_edit_24_regular,
      initialContent: draft?.content ?? mark.note?.content ?? '',
      initialContentFormat:
          draft?.contentFormat ??
          mark.note?.format ??
          PersonalNoteContentFormat.plain,
      referenceText: markerQuote(mark.text),
      bookId: mark.bookTitle,
      draftNoteId: draftId,
    ),
  );
  // השמירה אינה תלויה במסך: הדיאלוג כבר מחק את הטיוטה.
  if (result == null) return;
  await saveMarkerNote(context.mounted ? context : null, mark, result);
}

/// מזהה הטיוטה של ההערה, משותף לחלון הקופץ ולעורך שבחלונית.
String markerNoteDraftId(MarkerHighlight mark) => 'marker:${mark.id}';

/// שומר את ההערה מהעורך. כשהסימון השתנה בחלון אחר שואל אם לדרוס; כשלא
/// נשמר — ההערה נשארת טיוטה. מחזיר אם נשמרה.
Future<bool> saveMarkerNote(
  BuildContext? context,
  MarkerHighlight mark,
  PersonalNoteEditorResult result,
) async {
  final drafts = PersonalNoteDraftService();
  final draftId = markerNoteDraftId(mark);
  final note = MarkerNote(
    content: result.content,
    plain: result.contentPlain,
    format: result.contentFormat,
  );
  final actions = MarkerActions.instance;
  try {
    MarkerHighlight? saved;
    try {
      saved = await actions.writeNote(
        mark.id,
        note,
        expectedVersion: mark.version,
      );
    } on MarkerConflictException {
      if (context == null || !context.mounted) {
        await _keepAsDraft(drafts, mark, draftId, result);
        UiSnack.show(MarkerMessages.changedElsewhere);
        return false;
      }
      final overwrite = await showTwoActionsDialog(
        context: context,
        title: 'הסימון השתנה',
        content:
            '${MarkerMessages.changedElsewhere} לשמור את ההערה הזו במקום '
            'מה שנשמר שם?',
        confirmText: 'שמירה בכל זאת',
      );
      if (overwrite != true) {
        await _keepAsDraft(drafts, mark, draftId, result);
        return false;
      }
      saved = await actions.writeNote(mark.id, note);
    }
    if (saved == null) {
      // ביטול המחיקה מחזיר את הסימון באותו מזהה, ואיתו את הטיוטה.
      await _keepAsDraft(drafts, mark, draftId, result);
      UiSnack.show(MarkerMessages.deletedElsewhere);
      return false;
    }
    UiSnack.showQuick(MarkerMessages.noteSaved);
    return true;
  } catch (error) {
    debugPrint('Marker note save failed: $error');
    await _keepAsDraft(drafts, mark, draftId, result);
    UiSnack.showError(MarkerMessages.saveFailed);
    return false;
  }
}

/// הדיאלוג מוחק את הטיוטה כשהוא נסגר בשמירה; שמירה שלא הושלמה מחזירה אותה.
Future<void> _keepAsDraft(
  PersonalNoteDraftService drafts,
  MarkerHighlight mark,
  String draftId,
  PersonalNoteEditorResult result,
) => drafts.saveDraft(
  bookId: mark.bookTitle,
  noteId: draftId,
  draft: PersonalNoteDraft(
    content: result.content,
    contentPlain: result.contentPlain,
    contentFormat: result.contentFormat,
    updatedAt: DateTime.now(),
  ),
);

Future<void> deleteMarkerNote(
  BuildContext context,
  MarkerHighlight mark,
) async {
  final confirmed = await confirmMarkerAction(
    context,
    title: 'מחיקת הערה',
    content: 'למחוק את ההערה של הסימון? הסימון עצמו יישאר.',
    confirmText: 'מחיקה',
  );
  if (!confirmed) return;
  try {
    await MarkerActions.instance.writeNote(
      mark.id,
      null,
      expectedVersion: mark.version,
    );
    UiSnack.showQuick(MarkerMessages.noteDeleted);
  } on MarkerConflictException {
    UiSnack.show(MarkerMessages.changedElsewhere);
  } catch (error) {
    debugPrint('Marker note delete failed: $error');
    UiSnack.showError(MarkerMessages.saveFailed);
  }
}

/// תגיות מופרדות בפסיקים. מחזיר null בביטול.
Future<List<String>?> askMarkerTags(
  BuildContext context, {
  List<String> initial = const [],
  String title = 'תגיות',
}) async {
  final controller = TextEditingController(text: initial.join(', '));
  try {
    final confirmed = await showTwoActionsDialog(
      context: context,
      title: title,
      content: '',
      confirmText: 'שמירה',
      customContent: RtlTextField(
        controller: controller,
        autofocus: true,
        inputFormatters: [LengthLimitingTextInputFormatter(500)],
        decoration: const InputDecoration(
          hintText: 'לעיון, הלכה',
          helperText: 'הפרידו בין התגיות בפסיק',
        ),
      ),
    );
    if (confirmed != true) return null;
    return MarkerHighlight.normalizeTags([controller.text]);
  } finally {
    controller.dispose();
  }
}

Future<void> editMarkerTags(BuildContext context, MarkerHighlight mark) async {
  final tags = await askMarkerTags(context, initial: mark.tags);
  if (tags == null) return;
  await MarkerActions.instance.setTags(mark.id, tags);
}

/// אישור לפני מחיקה.
Future<bool> confirmMarkerAction(
  BuildContext context, {
  required String title,
  required String content,
  required String confirmText,
}) async =>
    await showWarningDialog(
      context: context,
      title: title,
      content: content,
      confirmText: confirmText,
    ) ==
    true;
