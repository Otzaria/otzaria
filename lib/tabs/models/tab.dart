/* this is a representation of the tabs that could be open in the app.
a tab is either a pdf book or a text book, or a full text search window*/

import 'package:otzaria/tabs/models/external_book_matches.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

abstract class OpenedTab {
  String title;
  bool isPinned;
  final String? dedupeKey;
  OpenedTab(this.title, {this.isPinned = false, this.dedupeKey});

  /// Called when the tab is being disposed.
  /// Override this method to perform cleanup.
  void dispose() {}

  /// Returns a fresh independent copy of this tab.
  ///
  /// מופשטת בכוונה: ברירת מחדל `=> this` החזירה alias במקום עותק, ותת-מחלקה
  /// חדשה קיבלה אותה בשקט. כך שיכפול טאב או מעבר בין שולחנות עבודה יצרו שני
  /// ערכים ברשימה שמצביעים על אותו אובייקט — ו-`dispose` של האחד סגר את
  /// ה-BLoC והבקרים של השני.
  OpenedTab clone();

  factory OpenedTab.from(OpenedTab tab) {
    if (tab is TextBookTab) {
      bool? splitedView;
      bool? showPageShapeView;
      List<String>? commentators = tab.commentators;
      // ערכי ברירת מחדל לוקחים את ה‑pinpoint שאיתו נבנה הטאב המקורי. אם
      // ה‑bloc כבר נטען, נעדיף את הערכים המעודכנים מה‑state — כדי לתפוס שינויים
      // (למשל ניקוי ה‑pinpoint עם חיפוש ידני חדש).
      String? pinpointText = tab.pinpointHighlight;
      int? pinpointSectionIndex = tab.pinpointHighlightSectionIndex;
      // קונפיגורציית החיפוש נלקחת מה-state המעודכן: בלעדיה שכפול ושחזור
      // מחזירים את החיפוש בספר למסלול המחרוזת הרצופה.
      String searchText = tab.searchText;
      var searchOptions = tab.searchOptions;
      var alternativeWords = tab.alternativeWords;
      var spacingValues = tab.spacingValues;
      var searchMode = tab.searchMode;
      var searchDistance = tab.searchDistance;
      var matchPolicy = tab.matchPolicy;
      // שלושת שדות ההדגשה קשורי-המקור: `?mark` deep link (highlightText,
      // permanentHighlightLine) ושורות התוצאה שהחיפוש הגלובלי מצא. בלעדיהם
      // שכפול טאב ומעבר בין שולחנות עבודה מחזירים ספר בלי ההדגשה שהמשתמש
      // רואה — ובלי סימון שורות התוצאה שהמנוע החזיר.
      String highlightText = tab.highlightText;
      int? permanentHighlightLine = tab.permanentHighlightLine;
      Set<int>? searchResultLines = tab.initialSearchResultLines;
      final state = tab.bloc.state;
      if (state is TextBookLoaded) {
        splitedView = state.showSplitView;
        showPageShapeView = state.showPageShapeView;
        commentators = state.activeCommentators;
        pinpointText = state.pinpointHighlightText;
        pinpointSectionIndex = state.pinpointHighlightIndex;
        searchText = state.searchText;
        searchOptions = state.searchOptions;
        alternativeWords = state.alternativeWords;
        spacingValues = state.spacingValues;
        searchMode = state.searchMode;
        searchDistance = state.searchDistance;
        matchPolicy = state.matchPolicy;
        // `_onLoadContent` זורע את שלושת השדות ל-Loaded מכל מסלול (מ-Initial
        // או משימור Loaded קודם), ולכן ה-state סמכותי — קריאה ללא נפילה חזרה
        // לשדות הטאב. נפילה כזו הייתה מחזירה שורות תוצאה שנוקו במפורש
        // (`clearSearchResultLines`) עם חיפוש ידני חדש בתוך הספר.
        highlightText = state.highlightText;
        permanentHighlightLine = state.permanentHighlightLine;
        // ב-Loaded השדה נקרא searchResultLines; ב-Initial אותו נתון עצמו
        // נקרא initialSearchResultLines.
        searchResultLines = state.searchResultLines;
      } else if (state is TextBookInitial) {
        // טאב ששמור בשולחן עבודה לא-פעיל מעולם לא נטען — בלי הענף הזה
        // צורת הדף והתצוגה המפוצלת מתאפסות בכל החלפת שולחן עבודה.
        splitedView = state.splitedView;
        showPageShapeView = state.showPageShapeView;
        searchText = state.searchText;
        searchOptions = state.searchOptions;
        alternativeWords = state.alternativeWords;
        spacingValues = state.spacingValues;
        searchMode = state.searchMode;
        searchDistance = state.searchDistance;
        matchPolicy = state.matchPolicy;
      }
      return TextBookTab(
        index: tab.index,
        book: tab.book,
        searchText: searchText,
        searchOptions: searchOptions,
        alternativeWords: alternativeWords,
        spacingValues: spacingValues,
        searchMode: searchMode,
        searchDistance: searchDistance,
        matchPolicy: matchPolicy,
        highlightText: highlightText,
        permanentHighlightLine: permanentHighlightLine,
        // עותק של ה-Set: בלעדיו המקור והשכפול מצביעים על אותו אוסף,
        // ושינוי באחד היה משנה את השני.
        initialSearchResultLines: searchResultLines == null
            ? null
            : Set<int>.of(searchResultLines),
        commentators: commentators,
        openLeftPane: state.showLeftPane,
        splitedView: splitedView,
        showPageShapeView: showPageShapeView,
        isPinned: tab.isPinned,
        dedupeKey: tab.dedupeKey,
        pinpointHighlight: pinpointText,
        pinpointHighlightSectionIndex: pinpointSectionIndex,
      );
    } else if (tab is PdfBookTab) {
      final copy = PdfBookTab(
        book: tab.book,
        pageNumber: tab.pageNumber,
        openLeftPane: tab.showLeftPane.value,
        // ה-BLoC מסנכרן את שדות החיפוש של הטאב, ולכן הם המצב המעודכן.
        searchText: tab.searchText,
        searchOptions: tab.searchOptions,
        alternativeWords: tab.alternativeWords,
        spacingValues: tab.spacingValues,
        searchMode: tab.searchMode,
        searchDistance: tab.searchDistance,
        matchPolicy: tab.matchPolicy,
        isPinned: tab.isPinned,
        dedupeKey: tab.dedupeKey,
        requiresStableLayout: tab.requiresStableLayout,
        // `ExternalBookMatches` מחזיק `List.unmodifiable` בלבד, ולכן שיתוף
        // המופע בטוח.
        externalMatches: tab.externalMatches.value,
      );
      // ⚠️ שדות שנקבעים **אחרי** הבנייה, ולכן אינם עוברים בפרמטרים.
      // בלעדיהם שיכפול כרטיסיה, מעבר שולחן עבודה ופיצול לשתי חלוניות
      // איפסו את המפרשים הפעילים ואת התקריב — אף שאותם שדות שורדים
      // `toJson`/`fromJson`. `PdfCommentatorsTab.clone` העתיק אותם ידנית
      // כדי לעקוף בדיוק את הפער הזה.
      copy.activeCommentators = Set<String>.of(tab.activeCommentators);
      copy.savedZoom = tab.savedZoom;
      copy.savedLayoutMode = tab.savedLayoutMode;
      return copy;
    } else if (tab is CombinedTab) {
      return CombinedTab(
        rightTab: OpenedTab.from(tab.rightTab),
        leftTab: OpenedTab.from(tab.leftTab),
        splitRatio: tab.splitRatio,
        isPinned: tab.isPinned,
      );
    } else if (tab is SearchingTab) {
      return SearchingTab.clone(tab);
    }
    return tab.clone();
  }

  factory OpenedTab.fromBook(
    Book book,
    int index, {
    String searchText = '',
    String highlightText = '',
    int? permanentHighlightLine,
    List<String>? commentators,
    bool openLeftPane = false,
    bool isPinned = false,
    bool? showPageShapeView,
    bool requiresStableLayout = false,
    String? pinpointHighlight,
    int? pinpointHighlightSectionIndex,
    String? dedupeKey,
    ExternalBookMatches? externalMatches,
  }) {
    if (book is PdfBook) {
      return PdfBookTab(
        book: book,
        pageNumber: index,
        openLeftPane: openLeftPane,
        searchText: searchText,
        isPinned: isPinned,
        requiresStableLayout: requiresStableLayout,
        dedupeKey: dedupeKey,
        externalMatches: externalMatches,
      );
    } else if (book is ConvertibleDocumentBook) {
      // ספרי מסמך רצים דרך זרימת TextBook — העטיפה דרך toTextBook משמרת
      // id/categoryId/externalLibraryId שדרושים ל-LibraryProviderManager.
      return TextBookTab(
        book: book.toTextBook(),
        index: index,
        searchText: searchText,
        highlightText: highlightText,
        permanentHighlightLine: permanentHighlightLine,
        commentators: commentators,
        openLeftPane: openLeftPane,
        isPinned: isPinned,
        showPageShapeView: showPageShapeView,
        pinpointHighlight: pinpointHighlight,
        pinpointHighlightSectionIndex: pinpointHighlightSectionIndex,
        dedupeKey: dedupeKey,
      );
    } else if (book is TextBook) {
      return TextBookTab(
        book: book,
        index: index,
        searchText: searchText,
        highlightText: highlightText,
        permanentHighlightLine: permanentHighlightLine,
        commentators: commentators,
        openLeftPane: openLeftPane,
        isPinned: isPinned,
        showPageShapeView: showPageShapeView,
        pinpointHighlight: pinpointHighlight,
        pinpointHighlightSectionIndex: pinpointHighlightSectionIndex,
        dedupeKey: dedupeKey,
      );
    }
    throw UnsupportedError("Unsupported book type: ${book.runtimeType}");
  }

  /// המפענח **היחיד** של טאב שמור.
  ///
  /// ⚠️ קודם לכן הוא הכיר חמישה טיפוסים בלבד, ושלושה קוראים עקפו אותו עם
  /// מפענחים מקבילים משלהם (`TabsRepository`, `Workspace.fromJson`,
  /// `decodeCombinedTab`). התוצאה: כרטיסיית מפרשים לא הייתה ניתנת להעברה
  /// בין חלונות — `canTransfer` חסם אותה — בעוד אותה כרטיסיה בדיוק כן
  /// נטענה מהדיסק, כי המסלול הזה עבר במפענח אחר. שכפול של טבלת טיפוסים
  /// מתיישן בכיוונים שונים, וזו בדיוק הדרך שבה זה קרה.
  ///
  /// טיפוס לא מוכר זורק ולא נופל בשקט ל-[SearchingTab]: נפילה כזו יצרה טאב
  /// רפאים בשם הכלי/הספר בכל ירידת גרסה, וההצפה נשמרה חזרה לדיסק. הקוראים
  /// (`TabsRepository.loadTabs`, `Workspace.fromJson`) מדלגים על טאב שנכשל.
  factory OpenedTab.fromJson(Map<String, dynamic> json) {
    String type = json['type'];
    if (type == 'TextBookTab') {
      return TextBookTab.fromJson(json);
    } else if (type == 'PdfBookTab') {
      return PdfBookTab.fromJson(json);
    } else if (type == 'CombinedTab') {
      return decodeCombinedTab(json);
    } else if (type == 'ToolTab') {
      return ToolTab.fromJson(json);
    } else if (type == 'SearchingTabWindow' || type == 'SearchingTab') {
      return SearchingTab.fromJson(json);
    } else if (type == 'CommentatorsTab') {
      return CommentatorsTab.fromJson(json);
    } else if (type == 'PdfCommentatorsTab') {
      return PdfCommentatorsTab.fromJson(json);
    }
    throw FormatException('Unknown tab type: $type');
  }
  Map<String, dynamic> toJson();
}
