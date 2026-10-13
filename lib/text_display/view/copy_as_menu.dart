import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

/// תת-תפריט "העתק כ..." — תיבות סימון שמרכיבות טיוטה מ-[base], ואחריהן
/// "העתק" (הטיוטה) ו"כמו בתצוגה". סימון תיבה לא סוגר את התפריט.
List<AppContextMenuEntry> buildCopyAsMenuEntries({
  required TextDisplayProfile base,
  required TextDisplayProfile draft,
  required bool hasSelection,
  required void Function(TextDisplayProfile draft) onDraftChanged,
  required void Function(TextDisplayProfile profile) onCopy,
}) {
  AppContextMenuEntry checkbox(
    String label, {
    required bool checked,
    required TextDisplayProfile Function(bool checked) toggled,
  }) => AppContextMenuEntry(
    label: label,
    enabled: hasSelection,
    isSelected: checked,
    keepOpen: true,
    onTap: () => onDraftChanged(toggled(!checked)),
  );

  return [
    checkbox(
      'ניקוד',
      checked: !draft.removeNikud,
      // טעמים שנגררים אחרי הניקוד ננעלים על מצבם הנוכחי — כל תיבה עצמאית.
      toggled: (checked) => draft.copyWith(
        nikud: checked ? MarkVisibility.show : MarkVisibility.hide,
        teamim: draft.removeTeamim
            ? TeamimVisibility.hide
            : TeamimVisibility.show,
      ),
    ),
    checkbox(
      'טעמים',
      checked: !draft.removeTeamim,
      toggled: (checked) => draft.copyWith(
        teamim: checked ? TeamimVisibility.show : TeamimVisibility.hide,
      ),
    ),
    checkbox(
      'פיסוק',
      checked: !draft.removePunctuation,
      toggled: (checked) => draft.copyWith(
        punctuation: checked ? MarkVisibility.show : MarkVisibility.hide,
      ),
    ),
    checkbox(
      'שם הוי"ה ככתבו',
      checked: !draft.replaceHolyNames,
      toggled: (checked) => draft.copyWith(
        holyName: checked
            ? HolyNameDisplay.asIs
            : base.replaceHolyNames
            ? base.holyName
            : HolyNameDisplay.kufKuf,
      ),
    ),
    // העתקה רק מסירה ציונים; כשהם כבר מוסתרים אין מה לבחור.
    if (base.showAnchorMarkers)
      checkbox(
        'ציוני המפרשים',
        checked: draft.showAnchorMarkers,
        toggled: (checked) => draft.copyWith(
          anchorMarkers: checked ? MarkVisibility.show : MarkVisibility.hide,
        ),
      ),
    const AppContextMenuEntry.divider(),
    AppContextMenuEntry(
      label: 'העתק',
      icon: OtzariaIcons.alef_copy_24_filled,
      enabled: hasSelection,
      onTap: () => onCopy(draft),
    ),
    AppContextMenuEntry(
      label: 'כמו בתצוגה',
      icon: OtzariaIcons.alef_eye_24_filled,
      enabled: hasSelection,
      onTap: () => onCopy(base),
    ),
  ];
}

/// The "העתק כ..." entry for [selectedText]; disabled without a selection.
/// The draft lives as long as this entry, so each opening starts from [base].
AppContextMenuEntry buildCopyAsMenuEntry({
  required TextDisplayProfile base,
  required String? selectedText,
  required void Function(TextDisplayProfile profile) onCopy,
}) {
  final hasSelection = selectedText != null && selectedText.trim().isNotEmpty;
  var draft = base;
  return AppContextMenuEntry(
    label: 'העתק כ...',
    icon: OtzariaIcons.alef_copy_24_filled,
    enabled: hasSelection,
    childrenBuilder: () => buildCopyAsMenuEntries(
      base: base,
      draft: draft,
      hasSelection: hasSelection,
      onDraftChanged: (next) => draft = next,
      onCopy: onCopy,
    ),
  );
}
