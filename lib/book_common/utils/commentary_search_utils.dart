import 'package:otzaria/search/utils/snippet_builder.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

/// ספירת התאמות חיפוש בתוכן מפרש.
///
/// הספירה תמיד על טקסט ללא ניקוד — תואמת את ה-regex הגמיש לניקוד של ההדגשה.
/// [partialWordMatch] חייב לשקף את `partialWordHighlight` שאיתו התוכן
/// מרונדר — אחרת המונה קטן ממספר ההדגשות שנראות בפועל (issue #1055).
int countCommentarySearchMatches({
  required String content,
  required String query,
  required TextDisplayProfile displayProfile,
  required bool partialWordMatch,
}) {
  var countText = utils.removeVolwels(content);
  if (displayProfile.removePunctuation) {
    countText = utils.removePunctuation(countText);
  }
  return TextRendererService.countSearchMatches(
    countText,
    query,
    partialWordMatch: partialWordMatch,
  );
}

/// קטע תצוגה סביב ההתאמה בתוכן מפרש, משמר את פרופיל התצוגה של המפרשים.
String buildCommentarySearchSnippet({
  required String content,
  required String query,
  required TextDisplayProfile displayProfile,
}) {
  var text = utils.removeMarks(
    content,
    nikud: displayProfile.removeNikud,
    teamim: displayProfile.removeTeamim,
  );
  if (displayProfile.removePunctuation) {
    text = utils.removePunctuation(text);
  }
  return SnippetBuilder.buildExcerptText(
    fullText: utils.stripHtmlIfNeeded(text),
    query: query,
    maxChars: 220,
  );
}

/// מייצג תוצאת חיפוש בודדת עם קטע טקסט וכתובת גלובלית לניווט.
///
/// חי כאן ולא בווידג'ט כדי ששני משטחי המפרשים (טקסט ו-PDF) יוכלו לדווח
/// ולצרוך את אותו טיפוס בלי לייבא זה את הווידג'ט של זה.
class CommentarySearchSnippet {
  final String path;
  final String snippet;
  final int globalIndex;

  const CommentarySearchSnippet({
    required this.path,
    required this.snippet,
    required this.globalIndex,
  });
}
