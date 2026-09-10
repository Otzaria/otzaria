part of 'tikkun_korim_bloc.dart';

class TikkunKorimState extends Equatable {
  final TikkunNavState nav;
  final TikkunSettings settings;

  /// העמודים (טורים) של התצוגה הנוכחית. בהפטרה/קריאה יש עמוד יחיד.
  final List<TikkunPage> pages;

  /// מיפוי פרק → אינדקס שורה בעמוד — רק בנביאים/כתובים.
  final Map<int, int> chapterToLineIdx;

  final bool isLoading;
  final String? error;
  final String? headerTitle;
  final String? headerSubtitle;

  /// העליה הנבחרת בבורר; `null` = "כל הפרשה".
  final int? aliyaIdx;

  /// שורה בתוך העמוד שיש לגלול אליה. [scrollRequestId] מבדיל בין בקשות
  /// חוזרות לאותה שורה.
  final int? scrollToLine;
  final int scrollRequestId;

  /// הצצה זמנית לטור המוסתר (לחצן ההחלפה המהירה).
  final bool peekSecondColumn;

  const TikkunKorimState({
    this.nav = const TikkunNavState(),
    this.settings = const TikkunSettings(),
    this.pages = const [],
    this.chapterToLineIdx = const {},
    this.isLoading = false,
    this.error,
    this.headerTitle,
    this.headerSubtitle,
    this.aliyaIdx,
    this.scrollToLine,
    this.scrollRequestId = 0,
    this.peekSecondColumn = false,
  });

  int get columnCount => pages.length;

  List<TikkunLine> get currentLines {
    if (pages.isEmpty) return const [];
    final idx = nav.currentColumnIndex.clamp(0, pages.length - 1);
    return pages[idx].lines;
  }

  /// הטור המוסתר בפועל — אחרי ההצצה הזמנית.
  bool get effectiveHideStam => peekSecondColumn && settings.isSingleColumn
      ? settings.hideNikud
      : settings.hideStam;

  bool get effectiveHideNikud => peekSecondColumn && settings.isSingleColumn
      ? settings.hideStam
      : settings.hideNikud;

  TikkunKorimState copyWith({
    TikkunNavState? nav,
    TikkunSettings? settings,
    List<TikkunPage>? pages,
    Map<int, int>? chapterToLineIdx,
    bool? isLoading,
    String? error,
    bool clearError = false,
    String? headerTitle,
    String? headerSubtitle,
    bool clearHeader = false,
    int? aliyaIdx,
    bool clearAliya = false,
    int? scrollToLine,
    int? scrollRequestId,
    bool clearScroll = false,
    bool? peekSecondColumn,
  }) => TikkunKorimState(
    nav: nav ?? this.nav,
    settings: settings ?? this.settings,
    pages: pages ?? this.pages,
    chapterToLineIdx: chapterToLineIdx ?? this.chapterToLineIdx,
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : (error ?? this.error),
    headerTitle: clearHeader ? null : (headerTitle ?? this.headerTitle),
    headerSubtitle: clearHeader
        ? null
        : (headerSubtitle ?? this.headerSubtitle),
    aliyaIdx: clearAliya ? null : (aliyaIdx ?? this.aliyaIdx),
    scrollToLine: clearScroll ? null : (scrollToLine ?? this.scrollToLine),
    scrollRequestId: scrollRequestId ?? this.scrollRequestId,
    peekSecondColumn: peekSecondColumn ?? this.peekSecondColumn,
  );

  @override
  List<Object?> get props => [
    nav,
    settings,
    pages,
    chapterToLineIdx,
    isLoading,
    error,
    headerTitle,
    headerSubtitle,
    aliyaIdx,
    scrollToLine,
    scrollRequestId,
    peekSecondColumn,
  ];
}
