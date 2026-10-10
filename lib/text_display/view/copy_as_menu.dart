import 'package:flutter/widgets.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

/// תת-תפריט "העתק כ..." — וריאציות העתקה שנגזרות מפרופיל ערוץ ההעתקה
/// [base]: מה שהתצוגה נותנת, עם/בלי ניקוד וטעמים, בלי פיסוק. אותה רשימה
/// בגוף, במפרשים ובצורת הדף, כדי שהמשתמש יראה אותן אפשרויות בכל מקום.
List<AppContextMenuEntry> buildCopyAsMenuEntries({
  required TextDisplayProfile base,
  required bool hasSelection,
  required void Function(TextDisplayProfile profile) onCopy,
}) {
  // כל וריאציה נושאת את האות שהיא מייצרת. אף אייקון אינו מבטיח סימן שהוא
  // רק *יורש* מ-base — הפיסוק כאן יורש, ולכן אין לו אייקון משלו.
  final variants =
      <({String label, IconData icon, TextDisplayProfile profile})>[
        (
          label: 'כמו בתצוגה',
          icon: OtzariaIcons.alef_eye_24_filled,
          profile: base,
        ),
        (
          label: 'עם ניקוד וטעמים',
          icon: OtzariaIcons.alef_niqqud_taamim_24_filled,
          profile: base.copyWith(
            nikud: MarkVisibility.show,
            teamim: TeamimVisibility.show,
          ),
        ),
        (
          label: 'עם ניקוד, בלי טעמים',
          icon: OtzariaIcons.alef_niqqud_24_filled,
          profile: base.copyWith(
            nikud: MarkVisibility.show,
            teamim: TeamimVisibility.hide,
          ),
        ),
        (
          label: 'בלי ניקוד וטעמים',
          icon: OtzariaIcons.alef_delete_24_filled,
          profile: base.copyWith(
            nikud: MarkVisibility.hide,
            teamim: TeamimVisibility.hide,
          ),
        ),
        (
          label: 'בלי ניקוד, טעמים ופיסוק',
          icon: OtzariaIcons.alef_eraser_24_filled,
          profile: base.copyWith(
            nikud: MarkVisibility.hide,
            teamim: TeamimVisibility.hide,
            punctuation: MarkVisibility.hide,
          ),
        ),
        (
          label: base.replaceHolyNames ? 'שם הוי"ה ככתבו' : 'שם הוי"ה כיקוק',
          icon: OtzariaIcons.alef_lock_24_filled,
          profile: base.copyWith(
            holyName: base.replaceHolyNames
                ? HolyNameDisplay.asIs
                : HolyNameDisplay.kufKuf,
          ),
        ),
      ];
  // וריאציה שזהה לבסיס (למעט הראשונה) מיותרת — לא מציגים אותה פעמיים.
  final seen = <TextDisplayProfile>{};
  return [
    for (final variant in variants)
      if (seen.add(variant.profile))
        AppContextMenuEntry(
          label: variant.label,
          icon: variant.icon,
          enabled: hasSelection,
          onTap: () => onCopy(variant.profile),
        ),
  ];
}

/// The "העתק כ..." entry of a reader context menu for [selectedText], with
/// the variants of [buildCopyAsMenuEntries]. It is disabled without a
/// selection.
AppContextMenuEntry buildCopyAsMenuEntry({
  required TextDisplayProfile base,
  required String? selectedText,
  required void Function(TextDisplayProfile profile) onCopy,
}) {
  final hasSelection = selectedText != null && selectedText.trim().isNotEmpty;
  return AppContextMenuEntry(
    label: 'העתק כ...',
    icon: OtzariaIcons.alef_copy_24_filled,
    enabled: hasSelection,
    children: buildCopyAsMenuEntries(
      base: base,
      hasSelection: hasSelection,
      onCopy: onCopy,
    ),
  );
}
