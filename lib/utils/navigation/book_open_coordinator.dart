import 'package:collection/collection.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/utils/ui/reading_left_pane_policy.dart';

class BookOpenCoordinator {
  final TabsBloc tabsBloc;
  final HistoryBloc historyBloc;
  final NavigationBloc navigationBloc;

  const BookOpenCoordinator({
    required this.tabsBloc,
    required this.historyBloc,
    required this.navigationBloc,
  });

  void openBook(
    Book book,
    int index,
    String searchQuery, {
    bool ignoreHistory = false,
    bool requiresStableLayout = false,
    String? pinpointHighlight,
    bool markSection = false,
    String? markText,
    bool insertAdjacent = false,
    List<String>? initialCommentators,
    bool navigateToPositionIfReused = false,
  }) {
    final tabsState = tabsBloc.state;
    if (tabsState.hasOpenTabs) {
      historyBloc.add(CaptureStateForHistory(tabsState.currentTab!));
    }

    final tab = buildTab(
      book,
      index,
      searchQuery,
      ignoreHistory: ignoreHistory,
      requiresStableLayout: requiresStableLayout,
      pinpointHighlight: pinpointHighlight,
      markSection: markSection,
      markText: markText,
      initialCommentators: initialCommentators,
    );
    tabsBloc.add(
      OpenOrFocusTab(
        tab,
        insertAdjacent: insertAdjacent,
        navigateToPositionIfReused: navigateToPositionIfReused,
      ),
    );
    navigationBloc.add(const NavigateToScreen(Screen.reading));
  }

  /// בונה את הטאב עם אותה סמנטיקת פתיחה של [openBook] (שחזור מיקום ומפרשים
  /// מההיסטוריה, צורת-דף שמורה) — למסלולים שמוסיפים את הטאב בעצמם.
  OpenedTab buildTab(
    Book book,
    int index,
    String searchQuery, {
    bool ignoreHistory = false,
    bool requiresStableLayout = false,
    String? pinpointHighlight,
    bool markSection = false,
    String? markText,
    List<String>? initialCommentators,
    String? dedupeKey,
  }) {
    // deep link עם הדגשה ממוקדת מציין במפורש סעיף יעד; חייבים לכבד אותו במדויק
    // (גם כש‑index=0) ולא ליפול חזרה להיסטוריית קריאה — אחרת ההדגשה תופיע במקום
    // הלא נכון ביחס לסעיף שהמשתמש ביקש.
    final hasPinpoint =
        pinpointHighlight != null && pinpointHighlight.isNotEmpty;
    final hasMarkText = markText != null && markText.isNotEmpty;
    final hasAnyHighlight = hasPinpoint || hasMarkText || markSection;

    final historyState = historyBloc.state;
    // התאמה לפי זהות יציבה ([bookIdentity]) ולא לפי כותרת בלבד: שני קובצי PDF
    // שונים עם אותה כותרת (id/נתיב שונה) מקבלים זהויות נפרדות, כך שפתיחת אחד
    // לא תקפוץ למיקום שנשמר עבור השני.
    final bookKey = bookIdentity(book);
    final lastOpened = (ignoreHistory || hasAnyHighlight)
        ? null
        : historyState.history.firstWhereOrNull(
            (b) => bookIdentity(b.book) == bookKey,
          );
    // ערך המיקום ההתחלתי ה"דיפולטי" תלוי בסוג הספר: בטקסט האינדקס מבוסס-0
    // (0 = "ללא מיקום ספציפי"), אבל ב-PDF העמודים מבוססי-1 (1 = העמוד הראשון).
    // הספרייה מעבירה את הדיפולט הזה. רק כשהמתקשר מעביר ערך שונה מהדיפולט מדובר
    // במיקום מפורש שיש לכבד; אחרת נופלים לשחזור המיקום מההיסטוריה.
    final int defaultIndex = book is PdfBook ? 1 : 0;
    final initialIndex =
        (ignoreHistory || hasAnyHighlight || index != defaultIndex)
        ? index
        : (lastOpened?.index ?? defaultIndex);
    // סמנטיקה של [initialCommentators]:
    //   null   → ברירת מחדל: נופלים להיסטוריה (commentatorsToShow).
    //   []     → bypass מפורש: פתיחה בלי מפרשים, גם אם בעבר נשמרו ב-history.
    //   [...]  → רשימה מפורשת מהקורא (למשל FindRef → "פתח עם רש"י").
    final resolvedCommentators =
        initialCommentators ?? lastOpened?.commentatorsToShow;

    final shouldOpenLeftPane = shouldAutoOpenReadingLeftPane();
    final savedViewMode = PageShapeSettingsManager.getViewModePreference(
      book.title,
    );

    // חישוב highlightText ו-permanentHighlightLine לפי סדר עדיפות:
    // markText > markSection > pinpointHighlight
    final String effectiveHighlightText;
    if (hasMarkText) {
      effectiveHighlightText = markText;
    } else if (hasPinpoint) {
      effectiveHighlightText = pinpointHighlight;
    } else {
      effectiveHighlightText = '';
    }
    final int? effectivePermanentHighlightLine =
        (hasMarkText || markSection || hasPinpoint) ? initialIndex : null;
    final String? effectivePinpoint =
        hasPinpoint && !hasMarkText && !markSection ? pinpointHighlight : null;

    return OpenedTab.fromBook(
      book,
      initialIndex,
      searchText: searchQuery,
      highlightText: effectiveHighlightText,
      permanentHighlightLine: effectivePermanentHighlightLine,
      commentators: resolvedCommentators,
      openLeftPane: shouldOpenLeftPane,
      showPageShapeView: savedViewMode,
      requiresStableLayout: requiresStableLayout,
      pinpointHighlight: effectivePinpoint,
      pinpointHighlightSectionIndex: effectivePinpoint != null
          ? initialIndex
          : null,
      dedupeKey: dedupeKey,
    );
  }
}
