import 'package:flutter/foundation.dart';

/// שומר את הקלט שכבר סונכרן לתוספים עבור כל קטע נקרא.
///
/// בלעדיו כל פריים גלילה משלם ניקוי-HTML וגיבוב sha256 לכל שורה נראית, גם
/// כשהטקסט זהה לפריים הקודם — כלומר כמעט תמיד.
class ReaderSectionSyncGate {
  /// חייב להישאר קטן מ-`ReaderSectionContentTracker.maxSnapshots`: אם הטראקר
  /// יאבד קו-בסיס בעוד השער עוד מסמן "מסונכרן", השינוי האמיתי הבא ייבלע.
  static const int defaultMaxEntries = 1024;

  /// סך התווים (מקור + מעובד) שנשמרים; בשורות ארוכות 1024 קטעים הם עשרות MB.
  static const int defaultMaxChars = 512 * 1024;

  static final ReaderSectionSyncGate instance = ReaderSectionSyncGate._();

  ReaderSectionSyncGate._()
    : maxEntries = defaultMaxEntries,
      maxChars = defaultMaxChars;

  @visibleForTesting
  ReaderSectionSyncGate.forTesting({
    this.maxEntries = defaultMaxEntries,
    this.maxChars = defaultMaxChars,
  }) : assert(maxEntries > 0);

  final int maxEntries;
  final int maxChars;
  final Map<_SectionKey, _SyncedInputs> _synced = {};
  int _chars = 0;

  @visibleForTesting
  int get trackedSections => _synced.length;

  @visibleForTesting
  int get trackedChars => _chars;

  static int _charsOf(_SyncedInputs inputs) =>
      inputs.rawSourceHtml.length + inputs.processedHtml.length;

  /// compare-and-set: מחזיר `true` כשהקטע צריך סנכרון, ואז **מסמן** את הקלט
  /// הנוכחי כמסונכרן. קריאה חוזרת עם אותו קלט תחזיר `false`.
  ///
  /// [highlightsRevision] הוא `PluginHighlightRegistry.revision` — בלעדיו
  /// highlight חדש שנוסף לקטע לא היה מקבל עיגון מחדש.
  bool claimSync({
    required String bookId,
    int? bookDbId,
    String? bookType,
    String? bookSource,
    required int sectionIndex,
    required String rawSourceHtml,
    required String processedHtml,
    required Object renderingSignature,
    required int highlightsRevision,
  }) {
    final key = (
      bookId: bookId,
      bookDbId: bookDbId,
      bookType: bookType,
      bookSource: bookSource,
      sectionIndex: sectionIndex,
    );
    final previous = _synced[key];
    // מסודר מהזול ליקר; השוואת המחרוזות נופלת בדרך כלל על מסלול הזהות של
    // `String ==`, כי גם הטקסט הגולמי וגם התוצר המעובד ממוחזרים בין פריימים.
    if (previous != null &&
        previous.highlightsRevision == highlightsRevision &&
        previous.rawSourceHtml == rawSourceHtml &&
        previous.processedHtml == processedHtml &&
        previous.renderingSignature == renderingSignature) {
      // LRU: פגיעה מקדמת את הקטע, כדי שפסקה ארוכה לא תפנה את עצמה בכל בנייה.
      _synced[key] = _synced.remove(key)!;
      return false;
    }
    if (previous != null) _chars -= _charsOf(_synced.remove(key)!);
    _synced[key] = (
      rawSourceHtml: rawSourceHtml,
      processedHtml: processedHtml,
      renderingSignature: renderingSignature,
      highlightsRevision: highlightsRevision,
    );
    _chars += _charsOf(_synced[key]!);
    while (_synced.length > maxEntries ||
        (_chars > maxChars && _synced.length > 1)) {
      _chars -= _charsOf(_synced.remove(_synced.keys.first)!);
    }
    return true;
  }

  /// מבטל סימון של קטע בודד, כך שהבנייה הבאה תסנכרן אותו שוב.
  void forget({required String bookId, required int sectionIndex}) {
    _synced.removeWhere(
      (key, _) => key.bookId == bookId && key.sectionIndex == sectionIndex,
    );
    _recountChars();
  }

  void forgetBook(String bookId) {
    _synced.removeWhere((key, _) => key.bookId == bookId);
    _recountChars();
  }

  void clear() {
    _synced.clear();
    _chars = 0;
  }

  void _recountChars() =>
      _chars = _synced.values.fold(0, (sum, inputs) => sum + _charsOf(inputs));
}

typedef _SectionKey = ({
  String bookId,
  int? bookDbId,
  String? bookType,
  String? bookSource,
  int sectionIndex,
});
typedef _SyncedInputs = ({
  String rawSourceHtml,
  String processedHtml,
  Object renderingSignature,
  int highlightsRevision,
});
