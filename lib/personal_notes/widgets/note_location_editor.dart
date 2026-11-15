import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/book_common/range_edit/text_range_editor.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/utils/note_location_edit.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';

/// חלון "מיקום ההערה". מחזיר את [edit] כשנשמר שינוי, אחרת null.
Future<NoteLocationEdit?> showNoteLocationEditor(
  BuildContext context, {
  required NoteLocationEdit edit,
  String Function(String source) display = _same,
  String Function(int lineIndex)? lineLabel,
  int? selectedLine,
}) async {
  final confirmed = await showTwoActionsDialog(
    context: context,
    title: 'מיקום ההערה',
    icon: FluentIcons.location_24_regular,
    confirmText: 'שמירה',
    size: AppDialogSize.medium,
    scrollable: true,
    customContent: NoteLocationEditor(
      edit: edit,
      display: display,
      lineLabel: lineLabel,
      selectedLine: selectedLine,
    ),
  );
  return confirmed == true && edit.changed ? edit : null;
}

String _same(String text) => text;

class NoteLocationEditor extends StatefulWidget {
  final NoteLocationEdit edit;
  final String Function(String source) display;

  /// שם השורה (0-based) לתצוגה, למשל כתובתה בספר.
  final String Function(int lineIndex)? lineLabel;

  /// השורה (1-based) שנבחרה בקורא, להעברה מהירה אליה.
  final int? selectedLine;

  const NoteLocationEditor({
    super.key,
    required this.edit,
    this.display = _same,
    this.lineLabel,
    this.selectedLine,
  });

  @override
  State<NoteLocationEditor> createState() => _NoteLocationEditorState();
}

class _NoteLocationEditorState extends State<NoteLocationEditor> {
  NoteLocationEdit get _edit => widget.edit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = _edit.scope;
    final selected = widget.selectedLine;
    final canJump =
        selected != null &&
        scope != PersonalNoteScope.book &&
        selected >= 1 &&
        selected <= _edit.range.paragraphCount &&
        !(_edit.range.isSingleParagraph &&
            _edit.range.start.paragraph == selected - 1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSegmentedControl<PersonalNoteScope>(
          expandToFillWidth: true,
          currentValue: scope,
          onChanged: (value) => setState(() => _edit.scope = value),
          options: const [
            SegmentOption(
              value: PersonalNoteScope.words,
              label: 'מילים',
              icon: FluentIcons.text_underline_24_regular,
            ),
            SegmentOption(
              value: PersonalNoteScope.lines,
              label: 'שורות',
              icon: FluentIcons.text_paragraph_24_regular,
            ),
            SegmentOption(
              value: PersonalNoteScope.book,
              label: 'כל הספר',
              icon: FluentIcons.book_open_24_regular,
            ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceMD),
        if (scope == PersonalNoteScope.book)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceLG),
            child: Text(
              'ההערה תחול על הספר כולו ותופיע בראש רשימת ההערות שלו, בלי '
              'סימון בטקסט.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          TextRangeEditor(
            // מפתח לפי הסוג: מעבר בין מילים לשורות בונה את העורך מחדש.
            key: ValueKey(scope),
            edit: _edit.range,
            display: widget.display,
            paragraphName: 'שורה',
            paragraphsName: 'שורות',
            paragraphLabel: widget.lineLabel,
            showReset: false,
            onChanged: () => setState(() {}),
          ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          children: [
            if (canJump)
              ActionButton.ghost(
                text: 'העברה לשורה שנבחרה בספר',
                icon: FluentIcons.location_arrow_24_regular,
                onPressed: () => setState(
                  () => _edit.range.goToParagraph(selected - 1),
                ),
              )
            else
              const SizedBox.shrink(),
            ActionButton.ghost(
              text: 'חזרה למה שנשמר',
              icon: FluentIcons.arrow_reset_24_regular,
              onPressed: _edit.differs ? () => setState(_edit.reset) : null,
            ),
          ],
        ),
      ],
    );
  }
}
