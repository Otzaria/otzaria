import 'package:flutter/foundation.dart';

/// שומר את הקלט שכבר סונכרן לתוספים עבור כל קטע נקרא.
///
/// בלעדיו כל פריים גלילה משלם ניקוי-HTML וגיבוב sha256 לכל שורה נראית, גם
/// כשהטקסט זהה לפריים הקודם — כלומר כמעט תמיד.
class ReaderSectionSyncGate {
  /// חייב להישאר קטן מ-`ReaderSectionContentTracker.maxSnapshots`: אם הטראקר
  /// יאבד קו-בסיס בעוד השער עוד מסמן "מסונכרן", השינוי האמיתי הבא ייבלע.
  static const int defaultMaxEntries = 256;

  static final ReaderSectionSyncGate instance = ReaderSectionSyncGate._();

  ReaderSectionSyncGate._() : maxEntries = defaultMaxEntries;

  @visibleForTesting
  ReaderSectionSyncGate.forTesting({this.maxEntries = defaultMaxEntries})
    : assert(maxEntries > 0);

  final int maxEntries;
  final Map<_SectionKey, _SyncedInputs> _synced = {};

  @visibleForTesting
  int get trackedSections => _synced.length;

  /// compare-and-set: מחזיר `true` כשהקטע צריך סנכרון, ואז **מסמן** את הקלט
  /// הנוכחי כמסונכרן. קריאה חוזרת עם אותו קלט תחזיר `false`.
  ///
  /// [highlightsRevision] הוא `PluginHighlightRegistry.revision` — בלעדיו
  /// highlight חדש שנוסף לקטע לא היה מקבל עיגון מחדש.
  bool claimSync({
    required String bookId,
    required int sectionIndex,
    required String rawSourceHtml,
    required String processedHtml,
    required Object renderingSignature,
    required int highlightsRevision,
  }) {
    final key = (bookId: bookId, sectionIndex: sectionIndex);
    final previous = _synced[key];
    // מסודר מהזול ליקר; השוואת המחרוזות נופלת בדרך כלל על מסלול הזהות של
    // `String ==`, כי גם הטקסט הגולמי וגם התוצר המעובד ממוחזרים בין פריימים.
    if (previous != null &&
        previous.highlightsRevision == highlightsRevision &&
        previous.rawSourceHtml == rawSourceHtml &&
        previous.processedHtml == processedHtml &&
        previous.renderingSignature == renderingSignature) {
      return false;
    }
    _synced.remove(key);
    _synced[key] = (
      rawSourceHtml: rawSourceHtml,
      processedHtml: processedHtml,
      renderingSignature: renderingSignature,
      highlightsRevision: highlightsRevision,
    );
    while (_synced.length > maxEntries) {
      _synced.remove(_synced.keys.first);
    }
    return true;
  }

  /// מבטל סימון של קטע בודד, כך שהבנייה הבאה תסנכרן אותו שוב.
  void forget({required String bookId, required int sectionIndex}) {
    _synced.remove((bookId: bookId, sectionIndex: sectionIndex));
  }

  void forgetBook(String bookId) {
    _synced.removeWhere((key, _) => key.bookId == bookId);
  }

  void clear() => _synced.clear();
}

typedef _SectionKey = ({String bookId, int sectionIndex});
typedef _SyncedInputs = ({
  String rawSourceHtml,
  String processedHtml,
  Object renderingSignature,
  int highlightsRevision,
});
