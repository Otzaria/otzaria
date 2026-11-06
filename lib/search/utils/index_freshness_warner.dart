import 'package:otzaria/data/book_identity.dart';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

/// אזהרה לא-חוסמת על דריפט תוכן בין ספר לאינדקס החיפוש.
///
/// תוצאת חיפוש נפתחת תמיד (הזהות כבר אומתה במסלול הפתיחה); אם חתימת
/// הטקסט באינדקס אינה תואמת את תוכן הספר, מוצגת הצעה לעדכן את האינדקס —
/// בלי לחסום דבר. ההשוואה היא מול חתימת הטקסט-בלבד (`textHash`), שאינה
/// נפסלת משינויי metadata כמו הסדר הקטלוגי (issue #828).
///
/// החתימה נקראת פר-ספר (`getBookTextFingerprint` — TermQuery על filePath),
/// ולא כמפת קורפוס מלאה: בדיקה של ספר אחד אינה משלמת O(כל המסמכים).
class IndexFreshnessWarner {
  IndexFreshnessWarner._();

  static final IndexFreshnessWarner instance = IndexFreshnessWarner._();

  /// הספק שמולו רצים — מוחלף בבדיקות בספק מזויף.
  @visibleForTesting
  TantivyDataProvider Function() providerResolver = () =>
      TantivyDataProvider.instance;

  /// השוואת ספר-מול-חתימה, מוזרקת בבדיקות שאין להן DB חי לטעינת הטקסט.
  /// מסלול קריאת החתימה, ה-revision והמטמון נשאר אמיתי גם אז.
  @visibleForTesting
  Future<bool> Function(Book book, BigInt indexHash)? debugBookVerifier;

  /// הצגת האזהרה, מוזרקת בבדיקות. null = UiSnack.
  @visibleForTesting
  void Function(String message)? debugNotifier;

  /// הבדיקה האחרונה לכל מפתח, כולל דריפט שטרם נמסר למנהל האינדוקס.
  final Map<String, _CheckedRevision> _checkedRevisionByKey = {};

  /// בדיקות שכבר רצות, לפי מפתח+revision+דור — שתי פתיחות של אותו ספר
  /// חולקות ריצה אחת במקום לגבב אותו פעמיים ולהזהיר פעמיים.
  final Map<String, Future<void>> _inFlightByKey = {};
  ValueNotifier<bool>? _hookedIsIndexing;
  Future<SearchEngine>? _engineGeneration;
  Future<Library>? _libraryGeneration;

  /// מונה שעולה בכל פסילת מטמון. זהויות ה-Future אינן מספיקות: מעבר
  /// isIndexing מאפס את המטמון בלי לשנות אף אחת מהן.
  int _invalidationToken = 0;

  @visibleForTesting
  void resetForTesting() {
    _checkedRevisionByKey.clear();
    _inFlightByKey.clear();
    _hookedIsIndexing?.removeListener(_invalidate);
    _hookedIsIndexing = null;
    _engineGeneration = null;
    _libraryGeneration = null;
    _invalidationToken = 0;
    providerResolver = () => TantivyDataProvider.instance;
    debugBookVerifier = null;
    debugNotifier = null;
  }

  void _invalidate() {
    _invalidationToken++;
    _checkedRevisionByKey.clear();
  }

  /// reopen מחליף את `provider.engine`, ורענון ספרייה את
  /// `DataRepository.instance.library` — התחלפות של אחד מהם פוסלת את כל
  /// מה שנבדק מול הדור הקודם.
  void _invalidateOnGenerationChange(
    Future<SearchEngine> engineGeneration,
    Future<Library> libraryGeneration,
  ) {
    if (identical(engineGeneration, _engineGeneration) &&
        identical(libraryGeneration, _libraryGeneration)) {
      return;
    }
    _engineGeneration = engineGeneration;
    _libraryGeneration = libraryGeneration;
    _invalidate();
  }

  /// בודק ספר פעם אחת לכל שילוב של מפתח-אינדקס ו-revision של המקור,
  /// ומזהיר על אי-התאמה ודאית. לעולם אינו זורק — כשל אימות אינו מפריע
  /// לפתיחת התוצאה, ואינו נצרב כדי שהבדיקה תנוסה שוב בפתיחה הבאה.
  /// עם [indexingBloc], אי־התאמה גם נשמרת להחלפה ומרעננת את החיווי בלי
  /// להתחיל אינדוקס.
  Future<void> warnIfContentDrifted(
    Book book, {
    IndexingBloc? indexingBloc,
  }) async {
    final provider = providerResolver();
    _hookIndexingInvalidation(provider);
    // אינדקס שנמצא באמצע בנייה אינו בסיס להשוואה: חלק מהמסמכים כבר
    // הוחלפו וחלק לא. אין בדיקה ואין כתיבה למטמון — הפתיחה הבאה, אחרי
    // סיום האינדוקס, תבדוק מחדש.
    if (provider.isIndexing.value) return;

    // צילום הדור *לפני* כל await: אינדקס שנפתח מחדש, ספרייה שהתרעננה או
    // ריצת אינדוקס בזמן ההמתנה הופכים את התוצאה הזו ללא-רלוונטית, גם אם
    // שום בדיקה אחרת לא נכנסה בינתיים כדי להבחין בכך.
    final engineGeneration = provider.engine;
    final libraryGeneration = DataRepository.instance.library;
    _invalidateOnGenerationChange(engineGeneration, libraryGeneration);
    final token = _invalidationToken;

    final key = BookIdentity.indexedFilePath(book);
    try {
      // ה-revision מזהה שינוי בקובץ המקור עצמו: ספר file-backed נקרא
      // ישירות מהדיסק, ואין רענון ספרייה שיסמן עריכה חיצונית שלו.
      final revision = await _sourceRevision(book);
      if (_checkedRevisionByKey[key]?.revision != revision) {
        final runKey = '$key|$revision|$token';
        final running = _inFlightByKey[runKey];
        if (running != null) {
          // גם הקורא המצטרף ממתין בתוך ה-try, כדי שכשל בריצה המשותפת
          // יטופל כאן ולא יהפוך לשגיאה אסינכרונית לא מטופלת.
          await running;
        } else {
          final run = _checkAndWarn(
            book: book,
            key: key,
            revision: revision,
            token: token,
            provider: provider,
            engineGeneration: engineGeneration,
            libraryGeneration: libraryGeneration,
          );
          _inFlightByKey[runKey] = run;
          try {
            await run;
          } finally {
            if (identical(_inFlightByKey[runKey], run)) {
              _inFlightByKey.remove(runKey);
            }
          }
        }
      }

      await _deferIfNeeded(
        book: book,
        key: key,
        revision: revision,
        token: token,
        provider: provider,
        engineGeneration: engineGeneration,
        libraryGeneration: libraryGeneration,
        indexingBloc: indexingBloc,
      );
    } catch (error) {
      debugPrint('אימות טריות האינדקס נכשל עבור "${book.title}": $error');
    }
  }

  Future<void> _checkAndWarn({
    required Book book,
    required String key,
    required String revision,
    required int token,
    required TantivyDataProvider provider,
    required Future<SearchEngine> engineGeneration,
    required Future<Library> libraryGeneration,
  }) async {
    final engine = await engineGeneration;
    final indexHash = await engine.getBookTextFingerprint(filePath: key);
    final matches = await (debugBookVerifier ?? _bookMatches)(book, indexHash);

    // קובץ מקור שנערך בזמן האימות: התוצאה שייכת לתוכן שכבר איננו — לא
    // נצרבת ולא מוצגת; הפתיחה הבאה תבדוק את ה-revision החדש.
    if (await _sourceRevision(book) != revision) return;

    // אין await בין הבדיקה הזו לבין ההצגה/הכתיבה למטמון.
    if (!_generationUnchanged(
      provider,
      token,
      engineGeneration,
      libraryGeneration,
    )) {
      return;
    }
    _checkedRevisionByKey[key] = _CheckedRevision(
      revision,
      needsReindex: !matches,
    );
    if (!matches) {
      (debugNotifier ?? UiSnack.show)(
        LibraryMessages.searchResultContentDrifted,
      );
    }
  }

  Future<void> _deferIfNeeded({
    required Book book,
    required String key,
    required String revision,
    required int token,
    required TantivyDataProvider provider,
    required Future<SearchEngine> engineGeneration,
    required Future<Library> libraryGeneration,
    required IndexingBloc? indexingBloc,
  }) async {
    if (indexingBloc == null || indexingBloc.isClosed) return;
    final checked = _checkedRevisionByKey[key];
    if (checked == null ||
        checked.revision != revision ||
        !checked.needsReindex) {
      return;
    }

    final library = await libraryGeneration;
    if (await _sourceRevision(book) != revision) return;
    if (!_generationUnchanged(
          provider,
          token,
          engineGeneration,
          libraryGeneration,
        ) ||
        indexingBloc.isClosed ||
        !identical(_checkedRevisionByKey[key], checked) ||
        !checked.needsReindex) {
      return;
    }

    // בלי await בין המסירה לסימונה: קורא אחר לא ישלח אותה שוב.
    indexingBloc.add(DeferIndexing(library, changedBooks: [book]));
    checked.needsReindex = false;
  }

  /// חתימת המקור של הספר: נתיב + זמן שינוי + גודל, כשיש קובץ מקור.
  /// מחרוזת ריקה לספר שכל תוכנו ב-DB — שינוי בו מגיע דרך רענון ספרייה,
  /// שממילא מאפס את המטמון.
  Future<String> _sourceRevision(Book book) async {
    final path = book is TextBook
        ? book.filePath
        : (book is FileBook ? book.path : null);
    if (path == null || path.isEmpty) return '';
    try {
      final stat = await File(path).stat();
      if (stat.type == FileSystemEntityType.notFound) return '';
      return '$path|${stat.modified.millisecondsSinceEpoch}|${stat.size}';
    } on FileSystemException {
      return '';
    }
  }

  bool _generationUnchanged(
    TantivyDataProvider provider,
    int token,
    Future<SearchEngine> engineGeneration,
    Future<Library> libraryGeneration,
  ) =>
      token == _invalidationToken &&
      // אינדוקס שהתחיל בזמן ההמתנה אינו מנפיק מעבר שה-token יתפוס אם הוא
      // עדיין פעיל — הערך עצמו הוא התנאי.
      !provider.isIndexing.value &&
      identical(provider.engine, engineGeneration) &&
      identical(DataRepository.instance.library, libraryGeneration);

  /// סוף ריצת אינדוקס משנה את תוכן האינדקס; המאזין מאפס על כל מעבר, כך
  /// שגם ספר "לא ניתן לאימות" נבדק מחדש אחרי בנייה חדשה.
  void _hookIndexingInvalidation(TantivyDataProvider provider) {
    if (identical(_hookedIsIndexing, provider.isIndexing)) return;
    _hookedIsIndexing?.removeListener(_invalidate);
    _hookedIsIndexing = provider.isIndexing..addListener(_invalidate);
  }

  Future<bool> _bookMatches(Book book, BigInt indexHash) => IndexingRepository(
    providerResolver(),
  ).textBookContentMatchesIndex(book, indexHash);
}

class _CheckedRevision {
  _CheckedRevision(this.revision, {required this.needsReindex});

  final String revision;
  bool needsReindex;
}
