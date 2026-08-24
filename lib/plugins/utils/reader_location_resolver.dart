import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';

/// Snapshot של מיקום הקריאה הנוכחי
///
/// מכיל את כל המידע הדרוש כדי לזהות את המיקום המדויק בקורא
class ReaderLocationSnapshot {
  final String? currentBook;
  final String? currentBookId;

  /// מזהה ספר יציב חוצה-ספקים ([PluginBookIdentity.uidOf]). מומלץ לתוספים
  /// לאחסן אותו במקום כותרת, שאינה מובטחת ייחודית או יציבה.
  final String? bookUid;
  final int? currentId;
  final String? currentType;
  final String? currentSource;
  final int currentIndex;
  final String? currentRef;

  const ReaderLocationSnapshot({
    required this.currentBook,
    required this.currentBookId,
    this.bookUid,
    required this.currentId,
    required this.currentType,
    this.currentSource,
    required this.currentIndex,
    required this.currentRef,
  });

  /// יוצר signature ייחודי למיקום זה.
  /// כולל currentId ו-currentType כדי ששני ספרים בעלי אותו שם לא יתנגשו.
  String signature() =>
      '${currentId ?? ''}|${currentType ?? ''}|'
      '${currentBook ?? ''}|$currentIndex|${currentRef ?? ''}';

  /// ממיר ל-JSON לשליחה לתוספים
  Map<String, dynamic> toJson() => {
    'currentBook': currentBook,
    'currentBookId': currentBookId,
    'bookUid': bookUid,
    'currentId': currentId,
    'currentType': currentType,
    'currentSource': currentSource,
    'currentIndex': currentIndex,
    'currentRef': currentRef,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReaderLocationSnapshot &&
          runtimeType == other.runtimeType &&
          signature() == other.signature();

  @override
  int get hashCode => signature().hashCode;
}

/// פותר את מיקום הקריאה הנוכחי מטאב נתון
///
/// פונקציה מרכזית אחת שמשמשת גם את reader.getCurrentRef
/// וגם את האירוע reader.current_ref_changed
Future<ReaderLocationSnapshot?> resolveReaderLocation(
  OpenedTab? currentTab,
) async {
  if (currentTab == null) {
    return null;
  }

  if (currentTab is TextBookTab) {
    return await _resolveTextBookLocation(currentTab);
  }

  if (currentTab is PdfBookTab) {
    return _resolvePdfBookLocation(currentTab);
  }

  return null;
}

/// פותר מיקום עבור ספר טקסט
Future<ReaderLocationSnapshot?> _resolveTextBookLocation(
  TextBookTab tab,
) async {
  final state = tab.bloc.state;
  final resolvedIndex = state is TextBookLoaded
      ? state.selectedIndex ??
            (state.visibleIndices.isNotEmpty
                ? state.visibleIndices.first
                : tab.index)
      : tab.index;

  // ניסיון ראשון: currentTitle מה-ValueNotifier
  final notifierTitle = tab.currentTitle.value.trim();
  if (notifierTitle.isNotEmpty) {
    return _snapshotFor(tab, resolvedIndex, notifierTitle);
  }

  // ניסיון שני: מה-state של ה-bloc
  if (state is TextBookLoaded) {
    final stateTitle = state.currentTitle?.trim() ?? '';
    if (stateTitle.isNotEmpty) {
      return _snapshotFor(tab, resolvedIndex, stateTitle);
    }

    // ניסיון שלישי: חישוב מתוך TOC
    try {
      final ref = await refFromIndex(
        resolvedIndex,
        Future.value(state.tableOfContents),
      );
      final normalizedRef = ref.trim();
      return _snapshotFor(
        tab,
        resolvedIndex,
        normalizedRef.isEmpty ? null : normalizedRef,
      );
    } catch (_) {
      return _snapshotFor(tab, resolvedIndex, null);
    }
  }

  return _snapshotFor(tab, tab.index, null);
}

ReaderLocationSnapshot _snapshotFor(
  TextBookTab tab,
  int index,
  String? currentRef,
) => ReaderLocationSnapshot(
  currentBook: tab.title,
  currentBookId: tab.title,
  bookUid: PluginBookIdentity.uidOf(tab.book),
  currentId: tab.book.id,
  currentType: PluginBookIdentity.typeOf(tab.book),
  currentSource: PluginBookIdentity.sourceOf(tab.book),
  currentIndex: index,
  currentRef: currentRef,
);

/// פותר מיקום עבור PDF
ReaderLocationSnapshot _resolvePdfBookLocation(PdfBookTab tab) {
  final currentTitle = tab.currentTitle.value.trim();
  final currentRef = currentTitle.isNotEmpty
      ? currentTitle
      : (tab.pageNumber > 0 ? 'עמוד ${tab.pageNumber}' : null);

  return ReaderLocationSnapshot(
    currentBook: tab.title,
    currentBookId: tab.title,
    bookUid: PluginBookIdentity.uidOf(tab.book),
    currentId: tab.book.id,
    currentType: PluginBookIdentity.typeOf(tab.book),
    currentSource: PluginBookIdentity.sourceOf(tab.book),
    currentIndex: tab.pageNumber,
    currentRef: currentRef,
  );
}
