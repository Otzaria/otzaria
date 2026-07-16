import 'package:otzaria/search/utils/snippet_builder.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

/// ספירת התאמות חיפוש בתוכן מפרש.
///
/// הספירה תמיד על טקסט ללא ניקוד — תואמת את ה-regex הגמיש לניקוד של ההדגשה.
int countCommentarySearchMatches({
  required String content,
  required String query,
  required bool removePunctuation,
}) {
  var countText = utils.removeVolwels(content);
  if (removePunctuation) {
    countText = utils.removePunctuation(countText);
  }
  return TextRendererService.countSearchMatches(countText, query);
}

/// קטע תצוגה סביב ההתאמה בתוכן מפרש, משמר את העדפת הניקוד של המשתמש.
String buildCommentarySearchSnippet({
  required String content,
  required String query,
  required bool removeNikud,
  required bool removePunctuation,
}) {
  var text = content;
  if (removeNikud) {
    text = utils.removeVolwels(text);
  }
  if (removePunctuation) {
    text = utils.removePunctuation(text);
  }
  return SnippetBuilder.buildExcerptText(
    fullText: utils.stripHtmlIfNeeded(text),
    query: query,
    maxChars: 220,
  );
}
