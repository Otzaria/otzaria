/* this is a representation of the tabs that could be open in the app.
a tab is either a pdf book or a text book, or a full text search window*/

import 'package:otzaria/tabs/models/external_book_matches.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/semantic_search_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/utils/reading_position.dart';

abstract class OpenedTab {
  String title;
  bool isPinned;
  final String? dedupeKey;

  /// מזהה רשומת ההיסטוריה שהטאב מעדכן, כדי ששני טאבים של אותו ספר יישמרו
  /// כשני מקומות. null = הרשומה היחידה של הספר (כמו ברשומות ישנות).
  String? historySlot;

  OpenedTab(this.title, {this.isPinned = false, this.dedupeKey});

  static int _historySlotCounter = 0;

  static String newHistorySlot() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '-${(_historySlotCounter++).toRadixString(36)}';

  /// Called when the tab is being disposed.
  /// Override this method to perform cleanup.
  void dispose() {}

  /// מחזיר עותק עצמאי עם בקרים ומחזור חיים נפרדים.
  OpenedTab clone();

  factory OpenedTab.from(OpenedTab tab) => tab.clone();

  /// מטען להעברה עם בעלות נפרדת על מצב התוספים, גם בחלוניות מפוצלות.
  Map<String, dynamic> toTransferJson() => withNewRuntimeIdentity(toJson());

  /// מנתק זהות של מופעי תוספים לפני יצירת עץ טאבים חי נוסף.
  static Map<String, dynamic> withNewRuntimeIdentity(
    Map<String, dynamic> json,
  ) => switch (json['type']) {
    'ToolTab' => {...json, 'instanceId': ToolTab.newInstanceId()},
    'CombinedTab' => {
      ...json,
      for (final side in ['rightTab', 'leftTab'])
        if (json[side] case final Map<String, dynamic> pane)
          side: withNewRuntimeIdentity(pane),
    },
    _ => json,
  };

  factory OpenedTab.fromBook(
    Book book,
    int index, {
    ReadingAnchor? initialReadingAnchor,
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
    }
    final textBook = switch (book) {
      // ספרי מסמך רצים דרך זרימת TextBook — העטיפה דרך toTextBook משמרת
      // id/categoryId/externalLibraryId שדרושים ל-LibraryProviderManager.
      final ConvertibleDocumentBook document => document.toTextBook(),
      final TextBook text => text,
      _ => throw UnsupportedError("Unsupported book type: ${book.runtimeType}"),
    };
    return TextBookTab(
      book: textBook,
      index: index,
      initialReadingAnchor: initialReadingAnchor,
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

  /// מפענח טאב שמור; טיפוס לא מוכר זורק כדי שלא יישמר במקומו טאב שגוי.
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
    } else if (type == 'SemanticSearchTab') {
      return SemanticSearchTab.fromJson(json);
    } else if (type == 'CommentatorsTab') {
      return CommentatorsTab.fromJson(json);
    } else if (type == 'PdfCommentatorsTab') {
      return PdfCommentatorsTab.fromJson(json);
    }
    throw FormatException('Unknown tab type: $type');
  }
  Map<String, dynamic> toJson();
}

/// מחזיק טאב מקור חי עד שכל הכרטיסיות התלויות בו נסגרות.
class SourceTabOwnership {
  SourceTabOwnership(this.sourceTab);

  final OpenedTab sourceTab;
  int _leases = 0;

  void retain() {
    _leases++;
  }

  void release() {
    if (_leases == 0 || --_leases != 0) return;
    sourceTab.dispose();
  }
}
