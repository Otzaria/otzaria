import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/utils/text/ref_helper.dart';

/// Snapshot של מיקום הקריאה הנוכחי
///
/// מכיל את כל המידע הדרוש כדי לזהות את המיקום המדויק בקורא
class ReaderLocationSnapshot {
  final String? currentBook;
  final String? currentBookId;
  final int? currentId;
  final String? currentType;
  final int currentIndex;
  final String? currentRef;

  const ReaderLocationSnapshot({
    required this.currentBook,
    required this.currentBookId,
    required this.currentId,
    required this.currentType,
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
    'currentId': currentId,
    'currentType': currentType,
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

// TODO(plugin-sdk): currentBookId is temporarily backed by the display title
// because OpenedTab does not yet expose one stable cross-provider identifier.
// Titles are not guaranteed to be unique; new code must not use this value as
// a database key until the library layer provides a canonical plugin book ID.

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
    return ReaderLocationSnapshot(
      currentBook: tab.title,
      currentBookId: tab.title,
      currentId: tab.book.id,
      currentType: 'text',
      currentIndex: resolvedIndex,
      currentRef: notifierTitle,
    );
  }

  // ניסיון שני: מה-state של ה-bloc
  if (state is TextBookLoaded) {
    final stateTitle = state.currentTitle?.trim() ?? '';
    if (stateTitle.isNotEmpty) {
      return ReaderLocationSnapshot(
        currentBook: tab.title,
        currentBookId: tab.title,
        currentId: tab.book.id,
        currentType: 'text',
        currentIndex: resolvedIndex,
        currentRef: stateTitle,
      );
    }

    // ניסיון שלישי: חישוב מתוך TOC
    try {
      final ref = await refFromIndex(
        resolvedIndex,
        Future.value(state.tableOfContents),
      );
      final normalizedRef = ref.trim();
      return ReaderLocationSnapshot(
        currentBook: tab.title,
        currentBookId: tab.title,
        currentId: tab.book.id,
        currentType: 'text',
        currentIndex: resolvedIndex,
        currentRef: normalizedRef.isEmpty ? null : normalizedRef,
      );
    } catch (_) {
      return ReaderLocationSnapshot(
        currentBook: tab.title,
        currentBookId: tab.title,
        currentId: tab.book.id,
        currentType: 'text',
        currentIndex: resolvedIndex,
        currentRef: null,
      );
    }
  }

  return ReaderLocationSnapshot(
    currentBook: tab.title,
    currentBookId: tab.title,
    currentId: tab.book.id,
    currentType: 'text',
    currentIndex: tab.index,
    currentRef: null,
  );
}

/// פותר מיקום עבור PDF
ReaderLocationSnapshot _resolvePdfBookLocation(PdfBookTab tab) {
  final currentTitle = tab.currentTitle.value.trim();
  if (currentTitle.isNotEmpty) {
    return ReaderLocationSnapshot(
      currentBook: tab.title,
      currentBookId: tab.title,
      currentId: tab.book.id,
      currentType: 'pdf',
      currentIndex: tab.pageNumber,
      currentRef: currentTitle,
    );
  }

  final defaultRef = tab.pageNumber > 0 ? 'עמוד ${tab.pageNumber}' : null;

  return ReaderLocationSnapshot(
    currentBook: tab.title,
    currentBookId: tab.title,
    currentId: tab.book.id,
    currentType: 'pdf',
    currentIndex: tab.pageNumber,
    currentRef: defaultRef,
  );
}
