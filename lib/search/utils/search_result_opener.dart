import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/in_book_search_routing.dart';
import 'package:otzaria/search/utils/index_freshness_warner.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/utils/navigation/talmud_bavli_open_format.dart';

/// פותח תוצאת חיפוש שכבר אומתה מול האינדקס בכרטיסיית עיון.
///
/// [resolvedBook] הוא הספר שפוענח מהמפתח; מחזיר את הכרטיסייה שנשלחה לפתיחה.
Future<OpenedTab?> openSearchResultInReader(
  BuildContext context, {
  required Book? resolvedBook,
  required String title,
  required String reference,
  required int segment,
  required bool isPdf,
  required String filePath,
  required String searchText,
  required Map<String, Map<String, bool>> searchOptions,
  required Map<int, List<String>> alternativeWords,
  required Map<String, String> spacingValues,
  required InBookSearchParameters inBook,
  bool inBackground = false,
}) async {
  final tabsBloc = context.read<TabsBloc>();
  final openLeftPane =
      (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
      (Settings.getValue<bool>('key-default-sidebar-open') ?? false);
  // filePath הוא מפתח האינדקס היציב — בלעדיו תוצאה מספר אישי הייתה מתמקדת
  // בטאב פתוח של ספר רשמי באותה כותרת.
  final dedupeKey =
      'search:${isPdf ? 'pdf' : 'text'}|$title|$reference|$segment|$filePath';

  if (isPdf) {
    final pdfTab = PdfBookTab(
      book: resolvedBook is PdfBook
          ? resolvedBook
          : PdfBook(title: title, path: filePath),
      pageNumber: segment + 1,
      dedupeKey: dedupeKey,
      searchText: searchText,
      searchOptions: searchOptions,
      alternativeWords: alternativeWords,
      spacingValues: spacingValues,
      searchMode: inBook.searchMode,
      searchDistance: inBook.distance,
      matchPolicy: inBook.matchPolicy,
      openLeftPane: openLeftPane,
      requiresStableLayout: true,
    );
    tabsBloc.add(
      OpenOrFocusTab(
        pdfTab,
        targetTitle: reference,
        insertAdjacent: true,
        inBackground: inBackground,
      ),
    );
    return pdfTab;
  }

  final textBook = switch (resolvedBook) {
    final TextBook book => book,
    final ConvertibleDocumentBook book => book.toTextBook(),
    _ => TextBook(title: title),
  };

  TextBookTab buildTextTab() => TextBookTab(
    book: textBook,
    index: segment,
    dedupeKey: dedupeKey,
    searchText: searchText,
    searchOptions: searchOptions,
    alternativeWords: alternativeWords,
    spacingValues: spacingValues,
    searchMode: inBook.searchMode,
    searchDistance: inBook.distance,
    matchPolicy: inBook.matchPolicy,
    initialSearchResultLines: {segment},
    showPageShapeView: PageShapeSettingsManager.getViewModePreference(title),
    openLeftPane: openLeftPane,
  );

  // הגדרת "פורמט פתיחת תלמוד בבלי": תוצאת טקסט של מסכת בבלי נפתחת
  // מיידית כטאב טעינה, ומיפוי העמוד ל-PDF רץ בתוך הטאב עצמו.
  final target = await resolveTalmudBavliPdfBook(textBook);
  if (!context.mounted) return null;

  final OpenedTab tab = target == null
      ? buildTextTab()
      : buildTalmudBavliResolvingTab(
          target: target,
          textIndex: segment,
          dedupeKey: dedupeKey,
          buildTextTab: (_) => buildTextTab(),
          buildPdfTab: (page, _) => PdfBookTab(
            book: target.pdfBook,
            pageNumber: page,
            dedupeKey: dedupeKey,
            searchText: searchText,
            searchOptions: searchOptions,
            alternativeWords: alternativeWords,
            spacingValues: spacingValues,
            searchMode: inBook.searchMode,
            searchDistance: inBook.distance,
            matchPolicy: inBook.matchPolicy,
            openLeftPane: openLeftPane,
            requiresStableLayout: true,
          ),
        );

  tabsBloc.add(
    OpenOrFocusTab(
      tab,
      targetTitle: reference,
      insertAdjacent: true,
      inBackground: inBackground,
    ),
  );
  unawaited(IndexFreshnessWarner.instance.warnIfContentDrifted(textBook));
  return tab;
}
