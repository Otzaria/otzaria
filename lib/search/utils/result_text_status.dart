import 'package:otzaria_search_engine/otzaria_search_engine.dart';

/// מוצג במקום טקסט תוצאה שהמנוע לא הצליח לקרוא ממסד הספרייה (למשל בזמן
/// עדכון ספרייה) — שורה ריקה נראית כמו תקלה.
const String unavailableResultText = 'טקסט השורה אינו זמין כעת';

/// האם אין לתוצאה טקסט להציג: המנוע לא קרא אותו, או ששורתה כבר אינה במסד.
bool isResultTextUnavailable(SearchResult result) =>
    switch (result.textStatus) {
      TextStatus.ok => false,
      TextStatus.stale => result.text.isEmpty,
      TextStatus.unavailable => true,
    };

/// האם יש בתוצאה טקסט שאפשר להעתיק.
bool hasCopyableResultText(SearchResult result) =>
    !isResultTextUnavailable(result) && result.text.isNotEmpty;
