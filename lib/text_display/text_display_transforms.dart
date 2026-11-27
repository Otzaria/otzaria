import 'package:otzaria/text_book/utils/inline_notes_utils.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

/// מחיל פרופיל תצוגה על טקסט גולמי (HTML או פשוט) — לערוצי ההעתקה, הייצוא
/// וההדפסה. אותו סדר כמו `TextRendererService.processText`: טעמים/ניקוד →
/// פיסוק → שם הוי"ה. אינו נוגע בציוני המפרשים (הם מוזרקים לתצוגה בלבד).
String applyTextDisplayProfile(String text, TextDisplayProfile profile) {
  if (text.isEmpty) return text;
  var result = utils.removeMarks(
    profile.hideFootnoteMarkers ? removeFootnoteMarkers(text) : text,
    nikud: profile.removeNikud,
    teamim: profile.removeTeamim,
  );
  if (profile.removePunctuation) {
    result = utils.removePunctuation(result);
  }
  if (profile.replaceHolyNames) {
    result = utils.replaceHolyNames(result, style: profile.holyNameStyle);
  }
  return result;
}
