import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/cross_line_result.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/utils/in_book_search_routing.dart';
import 'package:otzaria/search/utils/index_freshness_warner.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/utils/navigation/talmud_bavli_open_format.dart';

/// ספר העיון של תוצאת חיפוש: [resolvedBook] כשפוענח, ואחרת לפי הכותרת והנתיב.
Book searchResultBook(
  Book? resolvedBook,
  String title,
  String filePath, {
  required bool isPdf,
}) => isPdf
    ? (resolvedBook is PdfBook
          ? resolvedBook
          : PdfBook(title: title, path: filePath))
    : switch (resolvedBook) {
        final TextBook book => book,
        final ConvertibleDocumentBook book => book.toTextBook(),
        _ => TextBook(title: title),
      };

/// פותח תוצאת חיפוש שכבר אומתה מול האינדקס בכרטיסיית עיון.
///
/// [resolvedBook] הוא הספר שפוענח מהמפתח; מחזיר את הכרטיסייה שנשלחה לפתיחה.
/// [continuesToNextLine] מסמן גם את השורה הבאה כשורת תוצאה. [markResultLine]
/// כבוי: היעד אינו התאמה מילולית, ושורות התוצאה נקבעות בחיפוש בספר בלבד.
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
  bool continuesToNextLine = false,
  bool markResultLine = true,
}) async {
  final tabsBloc = context.read<TabsBloc>();
  final openLeftPane =
      (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
      (Settings.getValue<bool>('key-default-sidebar-open') ?? false);
  // filePath הוא מפתח האינדקס היציב — בלעדיו תוצאה מספר אישי הייתה מתמקדת
  // בטאב פתוח של ספר רשמי באותה כותרת.
  final dedupeKey =
      'search:${isPdf ? 'pdf' : 'text'}|$title|$reference|$segment|$filePath';

  PdfBookTab buildPdfTab(PdfBook book, int page) => PdfBookTab(
    book: book,
    pageNumber: page,
    dedupeKey: dedupeKey,
    searchText: searchText,
    searchOrigin: InBookSearchOrigin.globalResult,
    searchOptions: searchOptions,
    alternativeWords: alternativeWords,
    spacingValues: spacingValues,
    searchMode: inBook.searchMode,
    searchDistance: inBook.distance,
    matchPolicy: inBook.matchPolicy,
    openLeftPane: openLeftPane,
    requiresStableLayout: true,
    centerSearchMatchPage: page,
  );

  void open(OpenedTab tab) => tabsBloc.add(
    OpenOrFocusTab(
      tab,
      targetTitle: reference,
      insertAdjacent: true,
      inBackground: inBackground,
    ),
  );

  final book = searchResultBook(resolvedBook, title, filePath, isPdf: isPdf);
  if (book is PdfBook) {
    final pdfTab = buildPdfTab(book, segment + 1);
    open(pdfTab);
    return pdfTab;
  }
  final textBook = book as TextBook;

  TextBookTab buildTextTab() => TextBookTab(
    book: textBook,
    index: segment,
    dedupeKey: dedupeKey,
    searchText: searchText,
    searchOrigin: InBookSearchOrigin.globalResult,
    searchOptions: searchOptions,
    alternativeWords: alternativeWords,
    spacingValues: spacingValues,
    searchMode: inBook.searchMode,
    searchDistance: inBook.distance,
    matchPolicy: inBook.matchPolicy,
    initialSearchResultLines: markResultLine
        ? searchResultLinesFor(
            segment,
            continuesToNextLine: continuesToNextLine,
          )
        : null,
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
          buildPdfTab: (page, _) => buildPdfTab(target.pdfBook, page),
        );

  open(tab);
  unawaited(
    IndexFreshnessWarner.instance.warnIfContentDrifted(
      textBook,
      indexingBloc: context.read<IndexingBloc?>(),
    ),
  );
  return tab;
}
