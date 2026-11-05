import 'package:otzaria/models/books.dart';
import 'package:otzaria/bookmarks/utils/search_history_key.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/utils/file/hive_utils.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:otzaria/text_book/utils/reading_position.dart';

/// מחזירה מזהה יציב לספר לצורך השוואה בין סימניות/טאבים.
///
/// מועדף לפי החזק ביותר: db id → externalLibraryId → נתיב קובץ → filePath →
/// categoryId+title → title בלבד. שתי מהדורות של אותו ספר (אותה כותרת אבל
/// id/נתיב שונים) יקבלו זהויות שונות, כך שאפשר לסמן בהן סימניות נפרדות באותו
/// אינדקס בלי שתידחה סימניה.
String bookIdentity(Book book) {
  final base = '${_baseBookIdentity(book)}${book.sourceIdentitySuffix}';
  // מהדורה חלופית (book_version) חולקת את אותו db id עם הנוסח הממוזג —
  // בלי הסיומת סימניות והיסטוריית מיקום היו מתערבבות בין המהדורות.
  final versionTitle = book is TextBook ? book.versionTitle : null;
  return versionTitle == null ? base : '$base|version:$versionTitle';
}

String _baseBookIdentity(Book book) {
  if (book.id != null) {
    // PDF של מסכת בבלי נבנה עם ה-id של מהדורת הטקסט; בלי הסיומת אינדקס שורה
    // בטקסט היה משוחזר כמספר עמוד ב-PDF.
    return book is PdfBook ? 'id:${book.id}|pdf' : 'id:${book.id}';
  }
  final externalId = book.externalLibraryId;
  if (externalId != null && externalId.isNotEmpty) {
    return 'external:$externalId';
  }
  if (book is FileBook && book.path.isNotEmpty) {
    return 'file:${book.path}';
  }
  final filePath = book.filePath;
  if (filePath != null && filePath.isNotEmpty) {
    return 'filePath:$filePath';
  }
  if (book.categoryId != null) {
    return 'category:${book.categoryId}|title:${book.title}|type:${book.fileType ?? ''}';
  }
  return 'title:${book.title}';
}

enum BookmarkTargetKind {
  book,
  commentators,
}

/// Represents a bookmark in the application.
class Bookmark {
  final String ref;
  final Book book;
  final List<String> commentatorsToShow;
  final int index;
  final bool isSearch;
  final Map<String, Map<String, bool>>? searchOptions;
  final Map<int, List<String>>? alternativeWords;
  final Map<String, String>? spacingValues;
  final String? negativeSearchText;
  final Map<String, Map<String, bool>>? negativeSearchOptions;
  final Map<int, List<String>>? negativeAlternativeWords;
  final Map<String, String>? negativeSpacingValues;
  final String? workspaceName;
  final List<String>? searchScopeFacets;

  /// הסינון בתוך התחום; נשמר רק כששונה ממנו, בלי לשכפל אלפי facets.
  /// null משחזר את כל התחום, ורשימה ריקה משחזרת בחירה ריקה.
  final List<String>? searchFilterFacets;
  final SearchMode? searchMode;

  /// המרווח (slop) בין מילות החיפוש. null בפריטים שנשמרו לפני הוספת השדה.
  final int? distance;

  /// טווח הקרבה בין מילות החיפוש (מרווח מילים / פסקה / כותרת).
  /// null בפריטים שנשמרו לפני הוספת השדה — מתפרש כמרווח מילים.
  final SearchScope? proximityScope;

  /// [SearchConfiguration.toMap] המלא של החיפוש — כולל הגדרות שאין להן שדה
  /// ייעודי (מיון, איחוד תוצאות, התאמת מילים, רגקס). null בפריטים ישנים,
  /// ואז השחזור נופל לשדות הבודדים.
  final Map<String, dynamic>? searchConfiguration;
  final BookmarkTargetKind targetKind;

  /// טקסט תיאור שהמשתמש רואה ויכול לערוך. בעת יצירה מאותחל למילים הראשונות
  /// של הקטע המסומן. null = להציג את מיקום ברירת המחדל (ref).
  final String? label;

  /// מועד יצירת הסימניה — משמש למיון "לפי תאריך הוספה".
  /// null בסימניות ישנות שנשמרו לפני הוספת השדה.
  final DateTime? createdAt;
  final ReadingAnchor? readingAnchor;

  /// [OpenedTab.historySlot] של הטאב שממנו נלכדה רשומת ההיסטוריה.
  final String? historySlot;

  /// זהות מקום קריאה: סוג יעד, זהות ספר ו-slot; חיפוש לפי שאילתה וסינון.
  /// זהות הספר חייבת להתאים לשחזור המיקום, כדי לא לדרוס ספר אחר.
  String get historyKey => isSearch
      ? searchHistoryKey(
          query: ref,
          scopeFacets: searchScopeFacets,
          filterFacets: searchFilterFacets,
        )
      : '${targetKind.name}:${bookIdentity(book)}'
            '${historySlot == null ? '' : '#$historySlot'}';

  /// מזהה יציב של סימנייה בתוך רשימת הסימניות.
  ///
  /// ⚠️ אינדקס ברשימה **אינו** מזהה: חלון אחר יכול להוסיף סימנייה ולהזיז
  /// את כל מה שאחריה, ואז מחיקה לפי אינדקס מוחקת את הסימנייה הלא נכונה.
  /// ההרכב כאן הוא בדיוק מה ש-`addBookmark` מונע כפילות עליו — זיהוי הספר,
  /// המיקום וסוג היעד — ולכן שתי סימניות אינן יכולות לחלוק אותו.
  String get bookmarkIdentity =>
      '${bookIdentity(book)}|$index|${targetKind.name}';

  // searchConfiguration נשמר בלי ה-facets: השחזור לוקח אותם מהשדות הייעודיים,
  // ועם אלפי ספרים אישיים שני עותקים נוספים משלשים כל רשומת חיפוש (#3380).
  Bookmark({
    required this.ref,
    required this.book,
    required this.index,
    this.commentatorsToShow = const [],
    this.isSearch = false,
    this.searchOptions,
    this.alternativeWords,
    this.spacingValues,
    this.negativeSearchText,
    this.negativeSearchOptions,
    this.negativeAlternativeWords,
    this.negativeSpacingValues,
    this.workspaceName,
    this.searchScopeFacets,
    this.searchFilterFacets,
    this.searchMode,
    this.distance,
    this.proximityScope,
    Map<String, dynamic>? searchConfiguration,
    this.targetKind = BookmarkTargetKind.book,
    this.label,
    this.createdAt,
    this.readingAnchor,
    this.historySlot,
  }) : searchConfiguration = searchConfiguration == null
           ? null
           : (Map.of(searchConfiguration)
               ..remove('currentFacets')
               ..remove('searchScopeFacets'));

  /// מחזיר עותק עם שדות מעודכנים. [clearLabel] מאפס את [label] ל-null
  /// (חזרה להצגת המיקום) — נחוץ כי null כערך פירושו "ללא שינוי".
  Bookmark copyWith({
    String? label,
    bool clearLabel = false,
    String? historySlot,
  }) {
    return Bookmark(
      ref: ref,
      book: book,
      index: index,
      commentatorsToShow: commentatorsToShow,
      isSearch: isSearch,
      searchOptions: searchOptions,
      alternativeWords: alternativeWords,
      spacingValues: spacingValues,
      negativeSearchText: negativeSearchText,
      negativeSearchOptions: negativeSearchOptions,
      negativeAlternativeWords: negativeAlternativeWords,
      negativeSpacingValues: negativeSpacingValues,
      workspaceName: workspaceName,
      searchScopeFacets: searchScopeFacets,
      searchFilterFacets: searchFilterFacets,
      searchMode: searchMode,
      distance: distance,
      proximityScope: proximityScope,
      searchConfiguration: searchConfiguration,
      targetKind: targetKind,
      label: clearLabel ? null : (label ?? this.label),
      createdAt: createdAt,
      readingAnchor: readingAnchor,
      historySlot: historySlot ?? this.historySlot,
    );
  }

  factory Bookmark.fromJson(Map<String, dynamic> json) {
    final rawCommentators = json['commentatorsToShow'] as List<dynamic>?;
    return Bookmark(
      ref: json['ref'] as String,
      index: json['index'] as int,
      readingAnchor: ReadingAnchor.tryFromJson(json['readingAnchor']),
      book: Book.fromJson(castMap(json['book'])),
      commentatorsToShow: (rawCommentators ?? [])
          .map((e) => e.toString())
          .toList(),
      isSearch: json['isSearch'] ?? false,
      searchOptions: json['searchOptions'] != null
          ? castMap(json['searchOptions']).map(
              (key, value) => MapEntry(
                key,
                (castMap(value)).map((k, v) => MapEntry(k, v as bool)),
              ),
            )
          : null,
      alternativeWords: json['alternativeWords'] != null
          ? castMap(json['alternativeWords']).map(
              (key, value) => MapEntry(
                int.parse(key),
                (value as List<dynamic>).map((e) => e.toString()).toList(),
              ),
            )
          : null,
      spacingValues: json['spacingValues'] != null
          ? castMap(
              json['spacingValues'],
            ).map((key, value) => MapEntry(key, value.toString()))
          : null,
      negativeSearchText: json['negativeSearchText'] as String?,
      negativeSearchOptions: json['negativeSearchOptions'] != null
          ? castMap(json['negativeSearchOptions']).map(
              (key, value) => MapEntry(
                key,
                (castMap(value)).map((k, v) => MapEntry(k, v as bool)),
              ),
            )
          : null,
      negativeAlternativeWords: json['negativeAlternativeWords'] != null
          ? castMap(json['negativeAlternativeWords']).map(
              (key, value) => MapEntry(
                int.parse(key),
                (value as List<dynamic>).map((e) => e.toString()).toList(),
              ),
            )
          : null,
      negativeSpacingValues: json['negativeSpacingValues'] != null
          ? castMap(
              json['negativeSpacingValues'],
            ).map((key, value) => MapEntry(key, value.toString()))
          : null,
      workspaceName: json['workspaceName'] as String?,
      searchScopeFacets: json['searchScopeFacets'] != null
          ? List<String>.from(json['searchScopeFacets'] as List)
          : null,
      searchFilterFacets: json['searchFilterFacets'] != null
          ? List<String>.from(json['searchFilterFacets'] as List)
          : null,
      searchMode: json['searchMode'] != null
          ? _trySearchModeFromName(json['searchMode'] as String)
          : null,
      distance: json['distance'] as int?,
      searchConfiguration: json['searchConfiguration'] != null
          ? castMap(json['searchConfiguration'])
          : null,
      proximityScope: json['proximityScope'] != null
          ? _tryProximityScopeFromName(json['proximityScope'] as String)
          : null,
      targetKind: json['targetKind'] != null
          ? BookmarkTargetKind.values.firstWhere(
              (kind) => kind.name == json['targetKind'],
              orElse: () => BookmarkTargetKind.book,
            )
          : BookmarkTargetKind.book,
      label: json['label'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      historySlot: json['historySlot'] as String?,
    );
  }

  static SearchMode? _trySearchModeFromName(String rawMode) {
    for (final mode in SearchMode.values) {
      if (mode.name == rawMode) {
        return mode;
      }
    }

    return null;
  }

  static SearchScope? _tryProximityScopeFromName(String rawScope) {
    for (final scope in SearchScope.values) {
      if (scope.name == rawScope) {
        return scope;
      }
    }

    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'ref': ref,
      'book': book.toJson(),
      'index': index,
      if (readingAnchor != null) 'readingAnchor': readingAnchor!.toJson(),
      'commentatorsToShow': commentatorsToShow,
      'isSearch': isSearch,
      'searchOptions': searchOptions,
      'alternativeWords': alternativeWords?.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
      'spacingValues': spacingValues,
      'negativeSearchText': negativeSearchText,
      'negativeSearchOptions': negativeSearchOptions,
      'negativeAlternativeWords': negativeAlternativeWords?.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
      'negativeSpacingValues': negativeSpacingValues,
      'workspaceName': workspaceName,
      'searchScopeFacets': searchScopeFacets,
      'searchFilterFacets': ?searchFilterFacets,
      'searchMode': searchMode?.name,
      'distance': distance,
      'searchConfiguration': searchConfiguration,
      'proximityScope': proximityScope?.name,
      'targetKind': targetKind.name,
      'label': label,
      'createdAt': createdAt?.toIso8601String(),
      'historySlot': ?historySlot,
    };
  }
}
