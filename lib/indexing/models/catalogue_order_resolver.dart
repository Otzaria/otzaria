/// מוסר את הסדר הקטלוגי של ספר — המספר שנצרב לחצי העליון של מזהה המסמך
/// באינדקס (`IndexingRepository.buildCatalogueDocumentId`).
///
/// כל ספר שנשלח לאינדוקס חייב להופיע במפת הספרייה. סדר חלופי אינו בטוח:
/// טווח 32 סיביות אינו יכול למפות מפתחות שרירותיים בלי התנגשויות.
class CatalogueOrderResolver {
  CatalogueOrderResolver(this._orderByKey, {this.maxOrder = maxCatalogueOrder});

  /// [positions] — מקום כל ספר ברצף הקטלוג. ספר אישי (`uid:<id>`) מקבל
  /// [personalOrderBase] + id: ספר אישי שנוסף אינו מקבל מזהים של ספר שכבר
  /// באינדקס. מקומו ברצף נשאר ריק, כך שסדר שאר הספרים אינו משתנה.
  factory CatalogueOrderResolver.fromPositions(Map<String, int> positions) {
    final orders = <String, int>{};
    positions.forEach((key, position) {
      if (position >= personalOrderBase) {
        throw StateError('רצף הקטלוג חורג לטווח הספרים האישיים: $key');
      }
      final personalId = _personalBookId(key);
      orders[key] = personalId == null
          ? position
          : personalOrderBase + personalId;
    });
    return CatalogueOrderResolver(orders, maxOrder: maxSortableOrder);
  }

  /// הסדר הגבוה ביותר שניתן לצרוב: `buildCatalogueDocumentId` מוסיף 1 לפני
  /// ההזזה ב-32 סיביות, וערך גבוה יותר חורג מ-u64 ונחתך בגשר ל-Rust.
  static const int maxCatalogueOrder = 0xFFFFFFFE;

  /// מיון לפי דור במנוע שומר רק 56 סיביות מהמזהה, כלומר 24 סיביות לסדר+1.
  static const int maxSortableOrder = (1 << 24) - 2;

  /// תחילת טווח הספרים האישיים; הספרייה והמסדים המצורפים תמיד מתחתיו.
  static const int personalOrderBase = 1 << 23;

  final Map<String, int> _orderByKey;

  /// התקרה ש-[orderFor] אוכף.
  final int maxOrder;

  /// מחזיר את הסדר של [key]. זורק אם המפתח אינו בקטלוג או חורג מ-[maxOrder].
  int orderFor(String key) {
    final order = _orderByKey[key];
    if (order == null) {
      throw StateError('ספר שנשלח לאינדוקס אינו נמצא במפת הקטלוג: $key');
    }
    if (order < 0 || order > maxOrder) {
      throw RangeError.range(order, 0, maxOrder, 'catalogueOrder');
    }
    return order;
  }

  static int? _personalBookId(String key) {
    if (!key.startsWith('uid:')) return null;
    final id = int.tryParse(key.substring(4));
    return id != null && id >= 0 && 'uid:$id' == key ? id : null;
  }
}
