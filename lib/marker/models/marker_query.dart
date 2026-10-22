import 'package:equatable/equatable.dart';

enum MarkerSort { newest, oldest, book, color, favorites }

/// הקיבוץ קובע גם את מפתח המיון הראשי, כדי שכל קבוצה תהיה רציפה ברשימה
/// שנטענת בעמודים.
enum MarkerGroup { none, book, color, date }

/// ספר ברשימת הספרים של המרקר: ספר PDF וספר טקסט באותה כותרת נפרדים.
typedef MarkerBookCount = ({String title, bool pdf, int count});

/// שם הספר כפי שהוא מוצג ברשימה.
String markerBookLabel(String title, {required bool pdf}) =>
    pdf ? '$title (PDF)' : title;

/// מסנן מצב: כל הסימונים, מועדפים, עם הערה, עם תגית, או כאלה שעוגנם אבד.
enum MarkerStatusFilter { all, favorites, noted, tagged, needsRepair }

class MarkerQuery extends Equatable {
  final String search;
  final String? bookTitle;

  /// עם [bookTitle]: ספר ה-PDF שבכותרת הזו, ולא ספר הטקסט.
  final bool bookPdf;
  final String? colorId;
  final String? tag;
  final MarkerStatusFilter status;
  final MarkerSort sort;
  final MarkerGroup group;

  const MarkerQuery({
    this.search = '',
    this.bookTitle,
    this.bookPdf = false,
    this.colorId,
    this.tag,
    this.status = MarkerStatusFilter.all,
    this.sort = MarkerSort.newest,
    this.group = MarkerGroup.none,
  });

  bool get hasFilters =>
      search.trim().isNotEmpty ||
      bookTitle != null ||
      colorId != null ||
      tag != null ||
      status != MarkerStatusFilter.all;

  MarkerQuery copyWith({
    String? search,
    String? Function()? bookTitle,
    bool? bookPdf,
    String? Function()? colorId,
    String? Function()? tag,
    MarkerStatusFilter? status,
    MarkerSort? sort,
    MarkerGroup? group,
  }) => MarkerQuery(
    search: search ?? this.search,
    bookTitle: bookTitle != null ? bookTitle() : this.bookTitle,
    bookPdf: bookPdf ?? this.bookPdf,
    colorId: colorId != null ? colorId() : this.colorId,
    tag: tag != null ? tag() : this.tag,
    status: status ?? this.status,
    sort: sort ?? this.sort,
    group: group ?? this.group,
  );

  @override
  List<Object?> get props => [
    search,
    bookTitle,
    bookPdf,
    colorId,
    tag,
    status,
    sort,
    group,
  ];
}

/// ספירות למסנני המהירות, מחושבות בתוך החיפוש הנוכחי.
class MarkerCounts extends Equatable {
  final int total;
  final int matching;
  final int favorites;
  final int noted;
  final int tagged;
  final int needsRepair;
  final Map<String, int> byColor;

  const MarkerCounts({
    this.total = 0,
    this.matching = 0,
    this.favorites = 0,
    this.noted = 0,
    this.tagged = 0,
    this.needsRepair = 0,
    this.byColor = const {},
  });

  @override
  List<Object?> get props => [
    total,
    matching,
    favorites,
    noted,
    tagged,
    needsRepair,
    byColor,
  ];
}
