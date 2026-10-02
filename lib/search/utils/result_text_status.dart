import 'package:otzaria_search_engine/otzaria_search_engine.dart';

/// מוצג במקום טקסט תוצאה שהמנוע לא הצליח לקרוא ממסד הספרייה (למשל בזמן
/// עדכון ספרייה) — שורה ריקה נראית כמו תקלה.
const String unavailableResultText = 'טקסט השורה אינו זמין כעת';

/// האם המנוע החזיר את התוצאה בלי טקסט ([TextStatus.unavailable]).
bool isResultTextUnavailable(SearchResult result) =>
    result.textStatus == TextStatus.unavailable;
