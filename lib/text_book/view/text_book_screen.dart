import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:file_picker/file_picker.dart';
import 'package:otzaria/core/messages/text_book_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/models/live_tip.dart';
import 'package:provider/provider.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/bookmarks/utils/section_bookmark.dart';
import 'package:otzaria/bookmarks/view/bookmark_screen.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/settings/settings_exports.dart' hide UpdateFontSize;
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/widgets/navigation/reader_nav_center.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/utils/per_book_display_settings.dart';
import 'package:otzaria/text_book/utils/text_book_export_utils.dart';
import 'package:otzaria/text_book/utils/visible_index.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
// [EDITING DISABLED] import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/printing/print_content_models.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/printing/word_export_service.dart';
import 'package:otzaria/text_book/view/text_book_scaffold.dart';
import 'package:otzaria/text_book/view/text_book_search_screen.dart';
import 'package:otzaria/text_book/view/toc_navigator_screen.dart';
import 'package:otzaria/text_book/view/alt_toc_sidebar_view.dart';
import 'package:otzaria/utils/navigation/open_book.dart';
import 'package:otzaria/data/book_locator.dart';
import 'package:otzaria/utils/file/page_converter.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
// [EDITING DISABLED] import 'package:otzaria/text_book/editing/widgets/text_section_editor_dialog.dart';
import 'package:otzaria/text_book/view/book_source_dialog.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
// [EDITING DISABLED] import 'package:otzaria/text_book/editing/helpers/editor_settings_helper.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/utils/ui/fullscreen_helper.dart';

import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';
import 'package:otzaria/widgets/navigation/book_view_actions.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tools/shamor_zachor/models/book_model.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/settings/services/nikud_display_service.dart';
import 'package:otzaria/utils/link_helpers.dart';
import 'package:otzaria/text_book/utils/link_processing.dart'
    show splitContentLines;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/widgets/navigation/panel_tab_header.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';

// קבועים למצבי תצוגה (למניעת magic strings)
const String _viewModeSplit = 'split';
const String _viewModeBelow = 'below';
const String _viewModePage = 'page';
// פעולה (לא מצב תצוגה): פתיחת כרטיסיית מפרשים נפרדת
const String _actionOpenCommentatorsTab = 'open_commentators_tab';

enum _TextBookExportFormat {
  word('docx'),
  text('txt');

  final String extension;
  const _TextBookExportFormat(this.extension);
}

class _WordExportRequest {
  final String title;
  final String rawContent;
  final bool removeNikud;
  final bool removeTaamim;
  final bool shouldReplaceHolyNames;
  final String? fontFamily;
  final double fontSize;

  const _WordExportRequest({
    required this.title,
    required this.rawContent,
    required this.removeNikud,
    required this.removeTaamim,
    required this.shouldReplaceHolyNames,
    required this.fontFamily,
    required this.fontSize,
  });
}

class _TextExportRequest {
  final String rawContent;
  final bool removeNikud;
  final bool removeTaamim;
  final bool shouldReplaceHolyNames;

  const _TextExportRequest({
    required this.rawContent,
    required this.removeNikud,
    required this.removeTaamim,
    required this.shouldReplaceHolyNames,
  });
}

Uint8List _createTextBookWordExport(_WordExportRequest request) {
  final blocks = request.rawContent
      .split('\n')
      .map(
        (line) => PrintBlock(
          kind: PrintBlockKind.text,
          text: applyTextBookExportTextTransforms(
            line,
            removeNikud: request.removeNikud,
            removeTaamim: request.removeTaamim,
            shouldReplaceHolyNames: request.shouldReplaceHolyNames,
            stripHtml: false,
          ),
        ),
      )
      .toList(growable: false);

  return WordExportService.createWordDocument(
    title: request.title,
    blocks: blocks,
    format: PdfPageFormat.a4,
    isLandscape: false,
    pageMargin: 20,
    fontFamily: request.fontFamily,
    fontSize: request.fontSize,
  );
}

String _createTextBookTextExport(_TextExportRequest request) {
  if (request.rawContent.isEmpty) {
    return '';
  }

  return request.rawContent
      .split('\n')
      .map(
        (line) => applyTextBookExportTextTransforms(
          line,
          removeNikud: request.removeNikud,
          removeTaamim: request.removeTaamim,
          shouldReplaceHolyNames: request.shouldReplaceHolyNames,
          stripHtml: true,
        ),
      )
      .join('\n');
}

final GlobalKey textBookNavigationTourTargetKey = GlobalKey(
  debugLabel: 'text_book_navigation_tour_target',
);
final GlobalKey textBookNavPanelTourTargetKey = GlobalKey(
  debugLabel: 'text_book_nav_panel_tour_target',
);
final GlobalKey textBookCommentatorsTourTargetKey = GlobalKey(
  debugLabel: 'text_book_commentators_tour_target',
);
final GlobalKey textBookBookmarkTourTargetKey = GlobalKey(
  debugLabel: 'text_book_bookmark_tour_target',
);
final GlobalKey textBookSearchTourTargetKey = GlobalKey(
  debugLabel: 'text_book_search_tour_target',
);
final GlobalKey textBookPrintTourTargetKey = GlobalKey(
  debugLabel: 'text_book_print_tour_target',
);
final GlobalKey textBookOverflowTourTargetKey = GlobalKey(
  debugLabel: 'text_book_overflow_tour_target',
);
final GlobalKey textBookOverflowCommentatorsTourTargetKey = GlobalKey(
  debugLabel: 'text_book_overflow_commentators_tour_target',
);
final GlobalKey textBookOverflowBookmarkTourTargetKey = GlobalKey(
  debugLabel: 'text_book_overflow_bookmark_tour_target',
);
final GlobalKey textBookOverflowSearchTourTargetKey = GlobalKey(
  debugLabel: 'text_book_overflow_search_tour_target',
);
final GlobalKey textBookOverflowPrintTourTargetKey = GlobalKey(
  debugLabel: 'text_book_overflow_print_tour_target',
);

class TextBookViewerBloc extends StatefulWidget {
  final void Function(OpenedTab) openBookCallback;
  final TextBookTab tab;
  final bool isInCombinedView;
  final bool enableTourTargets;

  const TextBookViewerBloc({
    super.key,
    required this.openBookCallback,
    required this.tab,
    this.isInCombinedView = false,
    this.enableTourTargets = false,
  });

  @override
  State<TextBookViewerBloc> createState() => _TextBookViewerBlocState();
}

class _TextBookViewerBlocState extends State<TextBookViewerBloc>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final FocusNode textSearchFocusNode = FocusNode();
  final FocusNode navigationSearchFocusNode = FocusNode();
  final FocusNode altTitlesSearchFocusNode = FocusNode();
  final FocusNode _bookContentFocusNode = FocusNode(); // FocusNode לתוכן הספר
  late TabController tabController;
  late final ValueNotifier<double> _sidebarWidth;
  late final StreamSubscription<SettingsState> _settingsSub;
  int? _sidebarTabIndex; // אינדקס הכרטיסייה בסרגל הצדי
  // עוקב אחרי מצב הפאנל הצדדי כדי לבקש פוקוס לשדה החיפוש רק ברגע שהפאנל
  // נפתח (false→true) ולא בכל rebuild - אחרת היה גונב פוקוס מתוכן הספר.
  bool _wasLeftPaneShown = false;
  FocusRepository? _focusRepository; // שמירת הפניה לשימוש ב-dispose
  String? _selectedTextForSearch;
  int?
  _selectedLineForNote; // שורת המקור של הטקסט המסומן, ליצירת הערה בקיצור מקשים
  int?
  _selectedColumnForNote; // עמודת הבחירה — לזיהוי המופע הנכון כשהטקסט חוזר בשורה
  Book? _pdfBook; // Companion PDF
  bool _hasPdfBook = false;
  bool _hasResolvedCompanionPdf = false;
  bool _leftPaneAutoCloseQueuedByScroll = false;
  // מצב חלונית הצד שזוהה לאחרונה, לעיגון-מחדש של הטקסט בעת פתיחה/סגירה.
  bool _lastShowLeftPaneForReanchor = false;
  // האם החלונית דוחקת את התוכן (wide). ב-overlay הרוחב לא משתנה ולכן ה-reanchor
  // מיותר — וה-jumpTo שלו מבטל אנימציית ניווט פעילה מבחירה בסרגל הצד.
  bool _paneUsesPushLayout = false;

  /// מונה כמה פעמים רץ ה-reanchor בעקבות פתיחה/סגירת החלונית. לבדיקת הרגרסיה:
  /// חייב לרוץ במצב push ולהידכא ב-overlay.
  @visibleForTesting
  int reanchorOnPaneToggleCount = 0;

  // Key עבור PageShapeScreen
  final Key _pageShapeKey = UniqueKey();

  // בקשה לפתיחת דיאלוג הגדרות צורת הדף מתוך PageShapeScreen (עדכון חי)
  final ValueNotifier<int> _pageShapeOpenSettingsNotifier = ValueNotifier<int>(
    0,
  );

  // RepaintBoundary key עבור הדפסה של "צורת הדף" כפי שמוצג
  final GlobalKey _pageShapePrintBoundaryKey = GlobalKey();

  // בקשות לפתיחת חלונית פנימית ב"צורת הדף": 0=קישורים, 1=הערות
  final ValueNotifier<int?> _pageShapeSidebarTabNotifier = ValueNotifier<int?>(
    null,
  );

  // Cache לרשימת אינדקסי TOC ממוינת - למניעת חישוב מחדש בכל לחיצה
  List<int>? _cachedTocIndices;
  String? _cachedTocBookTitle;
  List<TocEntry>? _cachedToc;

  /// Check if book is already being tracked in Shamor Zachor
  /// שמור וזכור נשען על מזהי seforim.db בלבד; ספר אישי/חיצוני מחזיק מזהה
  /// ממרחב אחר שעלול להתנגש עם ספר רשמי אקראי, ולכן אינו נתמך.
  bool _isOfficialSeforimBook(Book book) =>
      book.id != null &&
      !book.isUserBook &&
      (book.externalLibraryId == null || book.externalLibraryId!.isEmpty);

  bool _isBookTrackedInShamorZachor(Book book) {
    if (!_isOfficialSeforimBook(book)) return false;
    try {
      final dataProvider = context.read<ShamorZachorDataProvider>();
      if (!dataProvider.hasData) return false;
      return dataProvider.getBookById(book.id!) != null;
    } catch (e) {
      debugPrint('Error checking if book is tracked: $e');
      return false;
    }
  }

  /// סימון V בשמור וזכור
  Future<void> _markShamorZachorProgress(String bookTitle) async {
    try {
      final dataProvider = context.read<ShamorZachorDataProvider>();
      final progressProvider = context.read<ShamorZachorProgressProvider>();
      final state = context.read<TextBookBloc>().state as TextBookLoaded;

      if (!dataProvider.hasData) {
        UiSnack.showError(TextBookMessages.shamorZachorDataNotLoaded);
        return;
      }

      // בדיקה אם יש ID לספר - אם לא, נחפש לפי כותרת
      int? bookId = state.book.id;
      if (bookId == null) {
        final resolvedBook = await BookDatabaseResolver.resolveBook(
          title: bookTitle,
          categoryId: state.book.categoryId,
          fileType: state.book.fileType,
          filePath: state.book.filePath,
          preferUserBooks: BookDatabaseResolver.isLikelyUserBook(
            isUserBook: state.book.isUserBook,
            categoryPath: state.book.categoryPath,
          ),
        );
        bookId = resolvedBook?.book.id;
      }

      if (bookId == null) {
        UiSnack.showError(TextBookMessages.bookNotFoundInDatabase);
        return;
      }

      // חיפוש הספר לפי ID ב-shamor zachor
      final result = dataProvider.getBookById(bookId);

      if (result == null) {
        UiSnack.showError(TextBookMessages.bookNotFoundInShamorZachor);
        return;
      }

      final (bookDetails, bookName, topLevelCategoryKey) = result;
      debugPrint('Book found: $bookName (ID: $bookId)');

      // קבלת הפרק הנוכחי — שורת מקור (לא segmentIndex של מצב רצף).
      final currentIndex = _topmostVisibleSourceLine(state);

      // קבלת הכותרת הנוכחית
      String currentRef = await refFromIndex(
        currentIndex,
        state.book.tableOfContents,
      );

      // אם הכותרת זהה לשם הספר, סימן שאנחנו לפני כל פרק - נחפש את ה-H2 הראשונה
      if (currentRef == state.book.title || currentRef.isEmpty) {
        debugPrint('Current ref is book title, looking for first H2...');
        final toc = await state.book.tableOfContents;

        for (final entry in toc) {
          if (entry.index >= currentIndex) {
            currentRef = entry.text;
            debugPrint('Found first H2: $currentRef');
            break;
          }
          for (final child in entry.children) {
            if (child.index >= currentIndex) {
              currentRef = '${entry.text}, ${child.text}';
              debugPrint('Found first H2 child: $currentRef');
              break;
            }
          }
          if (currentRef != state.book.title && currentRef.isNotEmpty) break;
        }
      }

      debugPrint('Current ref: $currentRef');

      // חילוץ שם הפרק מהפניה
      String? chapterName = _extractChapterName(currentRef);

      // אם לא הצלחנו לחלץ שם פרק, נשתמש בכל הפניה
      if (chapterName == null || chapterName.isEmpty) {
        chapterName = currentRef;
      }

      debugPrint('Chapter name: $chapterName');
      debugPrint('Book content type: ${bookDetails.contentType}');
      debugPrint('Book is daf type: ${bookDetails.isDafType}');
      debugPrint('Total learnable items: ${bookDetails.learnableItems.length}');

      // מציאת הפריט הרלוונטי בשמור וזכור
      final learnableItems = bookDetails.learnableItems;

      // חיפוש הפריט המתאים לפי שם הכותרת (כפי שהיא מופיעה בטקסט)
      LearnableItem? targetItem;

      // נחפש לפי שם הכותרת הנוכחית
      final searchTitle = chapterName;

      debugPrint('Searching for title: "$searchTitle"');
      debugPrint('Available learnable items:');
      for (int i = 0; i < learnableItems.length && i < 10; i++) {
        final item = learnableItems[i];
        debugPrint(
          '  [$i] displayLabel: "${item.displayLabel}", partName: "${item.partName}", hierarchyPath: ${item.hierarchyPath}',
        );
      }
      if (learnableItems.length > 10) {
        debugPrint('  ... and ${learnableItems.length - 10} more items');
      }

      // חיפוש לפי displayLabel או partName שמכיל את שם הכותרת. בכוונה אין
      // התאמה חלקית לפי מילים בודדות — היא סימנה התקדמות על פריט שגוי.
      targetItem = learnableItems.firstWhereOrNull(
        (item) {
          if (item.displayLabel != null &&
              item.displayLabel!.contains(searchTitle)) {
            return true;
          }
          if (item.partName.contains(searchTitle)) {
            return true;
          }
          return item.hierarchyPath.any((path) => path.contains(searchTitle));
        },
      );

      if (targetItem == null) {
        throw Exception('$searchTitle לא נמצא בשמור וזכור');
      }

      debugPrint(
        'Found target item: displayLabel="${targetItem.displayLabel}", partName="${targetItem.partName}"',
      );

      debugPrint(
        'Target item: ${targetItem.pageNumber}${targetItem.amudKey}, absoluteIndex: ${targetItem.absoluteIndex}',
      );

      // בדיקת מצב העמודות עבור הפרק הספציפי - משתמשים ב-ID!
      final itemProgress = progressProvider.getProgressForItemById(
        bookId,
        targetItem.absoluteIndex,
      );

      // מציאת העמודה הראשונה שלא מסומנת
      String? columnToMark;
      const columns = ['learn', 'review1', 'review2', 'review3'];

      for (final column in columns) {
        if (!itemProgress.getProperty(column)) {
          columnToMark = column;
          break;
        }
      }

      if (columnToMark == null) {
        UiSnack.show(TextBookMessages.noFreeSlotInChapter(chapterName));
        return;
      }

      // סימון הפרק הספציפי - משתמשים ב-ID!
      await progressProvider.updateProgressById(
        bookId,
        targetItem.absoluteIndex,
        columnToMark,
        true,
        bookDetails,
      );

      final columnName = _getColumnDisplayName(columnToMark);
      // השתמש בשם המקורי מהכותרת
      final displayName = chapterName;
      UiSnack.show(TextBookMessages.chapterMarked(displayName, columnName));
    } catch (e) {
      debugPrint('Error in _markShamorZachorProgress: $e');
      UiSnack.showError(TextBookMessages.markingError(e));
    }
  }

  /// חילוץ שם הפרק/דף מהפניה (לתצוגה)
  String? _extractChapterName(String ref) {
    // דוגמאות: "בראשית, פרק א" -> "פרק א", "ברכות, דף ו." -> "דף ו"

    final patterns = [
      RegExp(r'(פרק\s+[א-ת]+)'),
      RegExp(r'(דף\s+[א-ת]+[.:]?)'), // שמירת הנקודה או הנקודתיים
      RegExp(r',\s*([א-ת]+[.:]?)$'), // אם זה רק האות בסוף עם הסימן
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(ref);
      if (match != null) {
        String result = match.group(1) ?? '';
        return result;
      }
    }

    // אם לא מצאנו דפוס מיוחד, ננסה לחלץ רק את החלק האחרון
    final parts = ref.split(',');
    if (parts.length > 1) {
      String lastPart = parts.last.trim();
      return lastPart; // שמירת הסימן המקורי
    }

    return null;
  }

  /// קבלת שם העמודה להצגה
  String _getColumnDisplayName(String column) {
    switch (column) {
      case 'learn':
        return 'נלמד';
      case 'review1':
        return 'חזרה ראשונה';
      case 'review2':
        return 'חזרה שנייה';
      case 'review3':
        return 'חזרה שלישית';
      default:
        return column;
    }
  }

  Future<Uint8List?> _capturePageShapeViewPng() async {
    final boundaryContext = _pageShapePrintBoundaryKey.currentContext;
    if (boundaryContext == null) return null;

    final renderObject = boundaryContext.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;

    final pixelRatio = View.of(boundaryContext).devicePixelRatio;

    // ודא שהמסך צויר לפני צילום
    await WidgetsBinding.instance.endOfFrame;

    if (!mounted) return null;

    final image = await renderObject.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }

  void _handleBookSourcePress(BuildContext context, TextBookLoaded state) {
    context.read<TourCubit>().recordInteraction(
      TourInteraction(type: TourInteractionType.bookSourceViewed),
    );
    showBookSourceDialog(context, state);
  }

  Future<void> _handlePrintPress(TextBookLoaded state) async {
    context.read<TourCubit>().recordInteraction(
      TourInteraction(type: TourInteractionType.printUsed),
    );
    if (state.showPageShapeView) {
      final png = await _capturePageShapeViewPng();
      if (!mounted) return;

      final settingsState = context.read<SettingsBloc>().state;

      if (png == null || png.isEmpty) {
        UiSnack.showError(TextBookMessages.cannotCapturePageShapeForPrint);
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => PrintingScreen(
          // במצב זה ה-PDF נוצר מצילום המסך, ולכן אין צורך בנתוני הטקסט
          data: Future.value(''),
          bookId: state.book.title,
          removeNikud: state.removeNikud,
          removeTaamim: !settingsState.showTeamim,
          createPdfOverride: (PdfPageFormat format) async {
            final doc = pw.Document(compress: false);
            final img = pw.MemoryImage(png);
            doc.addPage(
              pw.Page(
                pageFormat: format,
                margin: pw.EdgeInsets.zero,
                build: (context) => pw.Center(
                  child: pw.Image(
                    img,
                    fit: pw.BoxFit.contain,
                  ),
                ),
              ),
            );
            return doc.save();
          },
        ),
      );
      return;
    }

    // תוכן מלא מה-repository — state.content יכול להיות חלקי (חימום/שחרור).
    // חובה לקרוא כאן: בתוך ה-builder ה-context הוא של הדיאלוג וחסר לו provider ל-TextBookBloc.
    final contentData = context.read<TextBookBloc>().repository.getBookContent(
      state.book,
    );
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PrintingScreen(
        data: contentData,
        bookId: state.book.title,
        book: state.book,
        links: state.links,
        activeCommentators: state.activeCommentators,
        startLine: state.visibleIndices.first,
        removeNikud: state.removeNikud,
        removeTaamim: !context.read<SettingsBloc>().state.showTeamim,
        tableOfContents: state.tableOfContents,
      ),
    );
  }

  Future<void> _exportWholeBook(TextBookLoaded state) async {
    if (!await verifySaferModePassword(context)) return;
    if (!mounted) return;

    try {
      final selectedFormat = await _pickTextBookExportFormat();
      if (selectedFormat == null) return;

      final extension = selectedFormat.extension;
      final path = await FilePicker.saveFile(
        dialogTitle: 'ייצוא הספר',
        fileName:
            '${sanitizeTextBookExportFileName(state.book.title)}.$extension',
        type: FileType.custom,
        allowedExtensions: [extension],
        lockParentWindow: true,
      );
      if (path == null) return;
      if (!mounted) return;

      final file = File(
        normalizeTextBookExportPath(
          path,
          defaultExtension: extension,
        ),
      );

      final settingsState = context.read<SettingsBloc>().state;
      final removeTaamim = !settingsState.showTeamim;
      final shouldReplaceHolyNames =
          Settings.getValue<bool>('key-replace-holy-names') ?? true;
      final fullContent = await context
          .read<TextBookBloc>()
          .repository
          .getBookContent(
            state.book,
          );

      if (selectedFormat == _TextBookExportFormat.word) {
        final bytes = await compute(
          _createTextBookWordExport,
          _WordExportRequest(
            title: state.book.title,
            rawContent: fullContent,
            removeNikud: state.removeNikud,
            removeTaamim: removeTaamim,
            shouldReplaceHolyNames: shouldReplaceHolyNames,
            fontFamily: settingsState.fontFamily,
            fontSize: state.fontSize,
          ),
        );
        await file.writeAsBytes(bytes);
        UiSnack.showSuccess(TextBookMessages.wordFileSaved);
        return;
      }

      final text = await compute(
        _createTextBookTextExport,
        _TextExportRequest(
          rawContent: fullContent,
          removeNikud: state.removeNikud,
          removeTaamim: removeTaamim,
          shouldReplaceHolyNames: shouldReplaceHolyNames,
        ),
      );
      await file.writeAsString(text);
      UiSnack.showSuccess(TextBookMessages.textFileSaved);
    } on FileSystemException catch (e) {
      if (isLockedTextBookExportFileException(e)) {
        UiSnack.showError(TextBookMessages.exportFileLocked);
        return;
      }
      UiSnack.showError(TextBookMessages.exportFailed(e.message));
    } catch (e) {
      UiSnack.showError(TextBookMessages.exportFailed(e));
    }
  }

  Future<_TextBookExportFormat?> _pickTextBookExportFormat() async {
    final result = await showTwoActionsDialog(
      context: context,
      title: 'בחירת סוג קובץ',
      content: 'בחר פורמט לייצוא',
      cancelText: 'טקסט',
      confirmText: 'Word',
      barrierDismissible: true,
    );

    if (result == null) return null;
    return result ? _TextBookExportFormat.word : _TextBookExportFormat.text;
  }

  @override
  void initState() {
    super.initState();

    // טעינת נתוני שמור וזכור ברקע כדי שהמצב יהיה נכון בפתיחת ספר
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      context.read<ShamorZachorDataProvider>().ensureLoaded().then((_) {
        if (mounted) {
          context.read<ShamorZachorProgressProvider>().ensureLoaded();
        }
      });
    });

    // האזנה לקיצורי הניווט הגלובליים (קטע/דף-פרק קודם והבא).
    widget.tab.navPreviousSegmentNotifier.addListener(_onNavPreviousSegment);
    widget.tab.navNextSegmentNotifier.addListener(_onNavNextSegment);
    widget.tab.navPreviousTocNotifier.addListener(_onNavPreviousToc);
    widget.tab.navNextTocNotifier.addListener(_onNavNextToc);

    // רישום ה-FocusNode ב-FocusRepository
    _focusRepository = context.read<FocusRepository>();
    _focusRepository!.registerBookContentFocusNode(_bookContentFocusNode);

    // טעינת הגדרות פר-ספר
    _loadPerBookSettings();

    // איתור ה-PDF המלווה (getCompanionBook) דורש את כל קטלוג הספרייה
    // (~300ms CPU על ה-main thread). קריאתו כאן ב-initState הייתה חונקת את
    // שאילתת תוכן הספר ומעכבת את הצגתו ב-~600ms. הוא משפיע רק על נראות כפתור
    // ה-PDF (_hasPdfBook), לא על התוכן — לכן נדחה ל-_resolveCompanionPdf
    // שנקרא ברגע שהספר נטען (ראו ה-listener של ה-BlocConsumer).

    final pendingSidebarTab = Settings.getValue<int>(
      'key-sidebar-tab-index-pending',
    );
    if (pendingSidebarTab != null && pendingSidebarTab >= 0) {
      _sidebarTabIndex = pendingSidebarTab;
    }

    // וודא שהמיקום הנוכחי נשמר בטאב

    // אם יש טקסט חיפוש (searchText), נתחיל בלשונית 'חיפוש' (שנמצאת במקום ה-2)
    // אחרת, נתחיל בלשונית 'ניווט' (שנמצאת במקום ה-0)
    // highlightText לא פותח את חלונית החיפוש
    final int initialIndex = widget.tab.searchText.isNotEmpty ? 2 : 0;

    // יוצרים את בקר הלשוניות עם האינדקס ההתחלתי שקבענו
    tabController = TabController(
      length: 3, // ברירת מחדל, יעודכן ב-_checkAltTitles
      vsync: this,
      initialIndex: initialIndex,
    );
    tabController.addListener(_handleTabChange);

    // בדיקה האם יש כותרות חלופיות
    _checkAltTitles();

    _sidebarWidth = ValueNotifier<double>(
      Settings.getValue<double>('key-sidebar-width', defaultValue: 300)!,
    );

    // שמירת הגדרות נוכחיות כדי לזהות שינויים
    double previousFontSize = context.read<SettingsBloc>().state.fontSize;
    String previousFontFamily = context.read<SettingsBloc>().state.fontFamily;
    SettingsState previousSettingsState = context.read<SettingsBloc>().state;

    _settingsSub = context.read<SettingsBloc>().stream.listen((state) {
      _sidebarWidth.value = state.sidebarWidth;

      // אם גודל הגופן השתנה, עדכן אותו מיידית
      if (state.fontSize != previousFontSize) {
        previousFontSize = state.fontSize;

        if (!mounted) return;

        // נשלח תמיד, גם אם הבלוק עדיין בטעינה: _onUpdateFontSize ישמור את
        // הערך כ-pending ויחיל אותו במעבר ל-Loaded. כך לא נאבד שינוי גופן
        // שמגיע מההגדרות לפני שתוכן הספר סיים להיטען (מרוץ בעליית התוכנה).
        context.read<TextBookBloc>().add(UpdateFontSize(state.fontSize));
      }

      // אם משפחת הגופן או הסרת ניקוד השתנו, טען מחדש את התוכן
      final isNikudSettingsChange = shouldReloadForNikudSettingsChange(
        previous: previousSettingsState,
        current: state,
      );
      final isPunctuationSettingsChange =
          shouldReloadForPunctuationSettingsChange(
            previous: previousSettingsState,
            current: state,
          );
      if (state.fontFamily != previousFontFamily ||
          isNikudSettingsChange ||
          isPunctuationSettingsChange) {
        previousFontFamily = state.fontFamily;
        previousSettingsState = state;

        if (!mounted) return;

        final currentState = context.read<TextBookBloc>().state;
        if (currentState is TextBookLoaded) {
          context.read<TextBookBloc>().add(
            LoadContent(
              fontSize: state.fontSize,
              showSplitView: currentState.showSplitView,
              removeNikud: state.defaultRemoveNikud,
              forceCloseLeftPane: widget.isInCombinedView,
              preserveState: true,
              // שמירת מצב הניקוד הנוכחי של המשתמש רק כשרק הגופן
              // השתנה - אם הגדרות הניקוד עצמן השתנו, יש להחיל את
              // הערך החדש
              preserveRemoveNikud: !isNikudSettingsChange,
              preserveRemovePunctuation: !isPunctuationSettingsChange,
              // שינוי הגדרות גלובליות (גופן/ניקוד) לעולם לא יכבה
              // את מצב הרצף שהמשתמש בחר עבור הספר.
              preserveContinuousReadingMode: true,
            ),
          );
        }
      } else {
        previousSettingsState = state;
      }
    });
  }

  /// טעינת הגדרות פר-ספר
  Future<void> _checkAltTitles() async {
    try {
      final structures = await DatabaseLibraryProvider.instance
          .getAlternativeStructuresForBook(widget.tab.book.title);

      if (!mounted) return;

      final hasAltTitles = structures.isNotEmpty;
      if (hasAltTitles != _hasAltTitles) {
        setState(() {
          _hasAltTitles = hasAltTitles;

          // Recreate tab controller with correct length
          final int newLength = hasAltTitles ? 3 : 2;
          // Adjust index if needed
          int newIndex = tabController.index;
          if (newIndex >= newLength) {
            newIndex = newLength - 1;
          }

          tabController.dispose();
          tabController = TabController(
            length: newLength,
            vsync: this,
            initialIndex: newIndex,
          );
          tabController.addListener(_handleTabChange);
        });
      }
    } catch (e) {
      debugPrint('Error checking alt titles: $e');
    }
  }

  /// מאזין למעבר בין לשוניות הפאנל הצדדי. מעביר פוקוס לשדה החיפוש של
  /// הלשונית החדשה רק לאחר שהמעבר הושלם (לא במהלך אנימציית המעבר).
  void _handleTabChange() {
    if (tabController.indexIsChanging) return;
    _focusActiveTabSearchField();
  }

  /// מבקש פוקוס לשדה החיפוש של הלשונית הפעילה בפאנל הצדדי
  /// ('ניווט' / 'כותרות' / 'חיפוש'). לא עושה דבר באנדרואיד או כשהפאנל סגור.
  void _focusActiveTabSearchField() {
    if (Platform.isAndroid) return;
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded || !state.showLeftPane) return;

    final int searchTabIndex = _hasAltTitles ? 2 : 1;
    if (tabController.index == 0) {
      navigationSearchFocusNode.requestFocus();
    } else if (_hasAltTitles && tabController.index == 1) {
      altTitlesSearchFocusNode.requestFocus();
    } else if (tabController.index == searchTabIndex) {
      textSearchFocusNode.requestFocus();
    }
  }

  /// מאתר את ספר ה-PDF המלווה (לכפתור "פתח גרסת PDF") פעם אחת, אחרי שתוכן
  /// הספר כבר נטען. `getCompanionBook` דורש את כל קטלוג הספרייה (~300ms CPU),
  /// ולכן הוא נדחה לכאן כדי לא לחנוק את שאילתת תוכן הספר בעלייה. עד שיתבצע,
  /// כפתור ה-PDF פשוט מוסתר (`_hasPdfBook == false`).
  Future<void> _resolveCompanionPdf() async {
    if (_hasResolvedCompanionPdf) return;
    _hasResolvedCompanionPdf = true;
    try {
      final library = await DataRepository.instance.library;
      if (!mounted) return;
      setState(() {
        _pdfBook = library.getCompanionBook(widget.tab.book, PdfBook);
        _hasPdfBook = _pdfBook != null;
      });
    } catch (e, stackTrace) {
      debugPrint('שגיאה בפתרון PDF מלווה: $e\n$stackTrace');
    }
  }

  Future<void> _loadPerBookSettings() async {
    final settingsBloc = context.read<SettingsBloc>();

    if (!settingsBloc.state.enablePerBookSettings) {
      return;
    }

    final settings = await TextBookPerBookSettings.load(widget.tab.book);

    if (settings == null) {
      return;
    }

    if (!mounted) {
      return;
    }

    final textBookBloc = context.read<TextBookBloc>();

    // המתן עד שה-TextBookBloc יהיה במצב TextBookLoaded
    await for (final state in textBookBloc.stream) {
      if (state is TextBookLoaded) {
        // החלת ההגדרות
        if (settings.fontSize != null) {
          textBookBloc.add(UpdateFontSize(settings.fontSize!));
        }
        if (settings.commentatorsBelow != null) {
          textBookBloc.add(ToggleSplitView(!settings.commentatorsBelow!));
        }
        if (settings.removeNikud != null) {
          textBookBloc.add(ToggleNikud(settings.removeNikud!));
        }
        if (settings.removePunctuation != null) {
          textBookBloc.add(TogglePunctuation(settings.removePunctuation!));
        }
        if (settings.continuousReadingMode != null) {
          textBookBloc.add(
            ToggleContinuousReadingMode(settings.continuousReadingMode!),
          );
        }
        break;
      }
    }
  }

  /// איפוס הגדרות פר-ספר
  Future<void> _resetPerBookSettings() async {
    await TextBookPerBookSettings.delete(widget.tab.book);

    // טעינה מחדש של ההגדרות הכלליות
    if (!mounted) return;
    final settingsBloc = context.read<SettingsBloc>();
    final textBookBloc = context.read<TextBookBloc>();

    textBookBloc.add(
      LoadContent(
        fontSize: settingsBloc.state.fontSize,
        showSplitView: Settings.getValue<bool>('key-splited-view') ?? true,
        removeNikud: settingsBloc.state.defaultRemoveNikud,
        preserveState: true,
        // בתצוגה משולבת, חלונית הצד תמיד סגורה
        forceCloseLeftPane: widget.isInCombinedView,
      ),
    );

    if (mounted) {
      UiSnack.show(TextBookMessages.perBookSettingsReset);
    }
  }

  bool _hasAltTitles = true; // נניח שיש בהתחלה, נעדכן אחרי בדיקה

  @override
  void dispose() {
    // ביטול רישום ה-FocusNode מ-FocusRepository (שימוש בהפניה שנשמרה)
    _focusRepository?.unregisterBookContentFocusNode(_bookContentFocusNode);

    widget.tab.navPreviousSegmentNotifier.removeListener(_onNavPreviousSegment);
    widget.tab.navNextSegmentNotifier.removeListener(_onNavNextSegment);
    widget.tab.navPreviousTocNotifier.removeListener(_onNavPreviousToc);
    widget.tab.navNextTocNotifier.removeListener(_onNavNextToc);

    tabController.dispose();
    textSearchFocusNode.dispose();
    navigationSearchFocusNode.dispose();
    altTitlesSearchFocusNode.dispose();
    _bookContentFocusNode.dispose();
    _sidebarWidth.dispose();
    _pageShapeSidebarTabNotifier.dispose();
    _pageShapeOpenSettingsNotifier.dispose();
    _settingsSub.cancel();
    super.dispose();
  }

  void _openPersonalNotesForCurrentView(TextBookLoaded state) {
    if (state.showPageShapeView) {
      _pageShapeSidebarTabNotifier.value = 1;
      return;
    }

    setState(() {
      _sidebarTabIndex = 2;
    });
    // Fire the notifier directly so SplitedViewScreen always opens the panel,
    // even when showSplitView is already true and the bloc won't emit a new state
    // (TextBookLoaded uses Equatable, so a no-op ToggleSplitView is swallowed).
    widget.tab.openNotesTabNotifier.value++;
    context.read<TextBookBloc>().add(const ToggleSplitView(true));
  }

  void _openLeftPaneTab(int index, {String? searchText}) {
    context.read<TextBookBloc>().add(const ToggleLeftPane(true));

    // טיפול מיוחד לאינדקס 1 - אם זה אמור להיות חיפוש
    // צריך לבדוק אם יש כותרות חלופיות
    int targetIndex = index;
    if (index == 1) {
      // אם מבקשים אינדקס 1, זה יכול להיות חיפוש או כותרות
      // נבדוק אם יש כותרות חלופיות - אם כן, חיפוש הוא באינדקס 2
      targetIndex = _hasAltTitles ? 2 : 1;

      // אם זה חיפוש ויש טקסט, נעדכן את טקסט החיפוש
      if (searchText != null && searchText.trim().isNotEmpty) {
        context.read<TextBookBloc>().add(UpdateSearchText(searchText.trim()));
      }
    }

    // וידוא שהאינדקס תקף לפני הגדרה
    final validIndex = targetIndex.clamp(0, tabController.length - 1);
    tabController.index = validIndex;

    // אם זה חיפוש, נתן פוקוס לשדה החיפוש
    if (targetIndex == (_hasAltTitles ? 2 : 1)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          textSearchFocusNode.requestFocus();
        }
      });
    }
  }

  void _onSelectedTextChanged(
    String? selectedText,
    int? lineIndex, [
    int? column,
  ]) {
    _selectedTextForSearch = selectedText;
    _selectedLineForNote = lineIndex;
    _selectedColumnForNote = column;
    final selectedLines = selectedText?.split('\n');
    final isSingleSectionSelection = selectedLines?.length == 1;
    context.read<TextBookBloc>().add(
      UpdateSelectedTextForNote(
        text: selectedText,
        sectionIndex: lineIndex,
        start: isSingleSectionSelection ? column : null,
        end: isSingleSectionSelection && column != null && selectedText != null
            ? column + selectedText.length
            : null,
      ),
    );
    if (selectedText == null || selectedText.trim().isEmpty) {
      return;
    }

    final tourCubit = context.read<TourCubit>();
    final currentState = context.read<TextBookBloc>().state;
    if (currentState is TextBookLoaded &&
        currentState.availableCommentators.isNotEmpty &&
        !tourCubit.hasRegisteredCommentaryOpportunity) {
      tourCubit.recordInteraction(
        TourInteraction(
          type: TourInteractionType.commentaryAvailable,
          primaryValue: widget.tab.title,
        ),
      );
    }
    tourCubit.recordInteraction(
      TourInteraction(
        type: TourInteractionType.textSelected,
        primaryValue: widget.tab.title,
      ),
    );
  }

  void _openSearchFromToolbar() {
    _openLeftPaneTab(1, searchText: _selectedTextForSearch);
  }

  void _openSearchWithText(String? selectedText) {
    _openLeftPaneTab(
      1,
      searchText: selectedText?.trim().isNotEmpty == true
          ? selectedText
          : _selectedTextForSearch,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        return BlocConsumer<TabsBloc, TabsState>(
          listenWhen: (previous, current) =>
              previous.currentTabIndex != current.currentTabIndex,
          listener: (context, tabsState) {
            // בקשת focus כשהטאב הנוכחי הוא הטאב של הספר הזה
            // הסרת החזרה אוטומטית של פוקוס כדי לאפשר לדיאלוגים וחלוניות לקבל פוקוס
            // final currentTab = tabsState.tabs.isNotEmpty &&
            //         tabsState.currentTabIndex < tabsState.tabs.length
            //     ? tabsState.tabs[tabsState.currentTabIndex]
            //     : null;
            // if (currentTab == widget.tab && mounted) {
            //   WidgetsBinding.instance.addPostFrameCallback((_) {
            //     if (mounted && !_bookContentFocusNode.hasFocus) {
            //       _bookContentFocusNode.requestFocus();
            //     }
            //   });
            // }
          },
          builder: (context, tabsState) {
            // סגירת חלונית הצד כשנמצאים במצב side-by-side
            if (tabsState.isSideBySideMode) {
              final currentState = context.read<TextBookBloc>().state;
              if (currentState is TextBookLoaded && currentState.showLeftPane) {
                // בדיקה אם הטאב הנוכחי הוא אחד מהטאבים המוצגים
                final currentTabIndex = tabsState.currentTabIndex;
                final isInSideBySide =
                    currentTabIndex == tabsState.sideBySideMode!.leftTabIndex ||
                    currentTabIndex == tabsState.sideBySideMode!.rightTabIndex;

                if (isInSideBySide) {
                  // סגירה מיידית
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      context.read<TextBookBloc>().add(
                        const ToggleLeftPane(false),
                      );
                    }
                  });
                }
              }
            }

            return BlocConsumer<TextBookBloc, TextBookState>(
              bloc: context.read<TextBookBloc>(),
              listener: (context, state) {
                // [EDITING DISABLED]
                // if (state is TextBookLoaded &&
                //     state.isEditorOpen &&
                //     state.editorIndex != null) {
                //   _openEditorDialog(context, state);
                // }

                if (state is TextBookLoaded) {
                  // איתור ה-PDF המלווה נדחה עד שהתוכן נטען, כדי שלא יחנוק את
                  // שאילתת התוכן בעלייה (ראו _resolveCompanionPdf).
                  _resolveCompanionPdf();
                  if (!state.showLeftPane) {
                    _leftPaneAutoCloseQueuedByScroll = false;
                  }
                  // פתיחת/סגירת חלונית הצד משנה את רוחב הטקסט; מעגנים מחדש
                  // לפריט העליון הנראה כדי שהתצוגה לא תקפוץ בזרימה-מחדש.
                  if (state.showLeftPane != _lastShowLeftPaneForReanchor) {
                    _lastShowLeftPaneForReanchor = state.showLeftPane;
                    if (_paneUsesPushLayout) {
                      reanchorOnPaneToggleCount++;
                      _reanchorMainContentToTopmostVisible();
                    }
                  }
                  final pendingSidebarTab = Settings.getValue<int>(
                    'key-sidebar-tab-index-pending',
                  );
                  if (pendingSidebarTab != null && pendingSidebarTab >= 0) {
                    if (_sidebarTabIndex != pendingSidebarTab) {
                      setState(() {
                        _sidebarTabIndex = pendingSidebarTab;
                      });
                    }
                    if (state.showSplitView) {
                      Settings.setValue<int>(
                        'key-sidebar-tab-index-pending',
                        -1,
                      );
                    }
                  } else if (!state.showSplitView && _sidebarTabIndex != null) {
                    setState(() {
                      _sidebarTabIndex = null;
                    });
                  }
                }
              },
              builder: (context, state) {
                if (state is TextBookInitial) {
                  // איפוס אינדקס הכרטיסייה כשטוענים ספר חדש
                  final pendingSidebarTab = Settings.getValue<int>(
                    'key-sidebar-tab-index-pending',
                  );
                  if (_sidebarTabIndex != null &&
                      (pendingSidebarTab == null || pendingSidebarTab < 0)) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      setState(() {
                        _sidebarTabIndex = null;
                      });
                    });
                  }

                  context.read<TextBookBloc>().add(
                    LoadContent(
                      fontSize: settingsState.fontSize,
                      showSplitView: state.splitedView,
                      removeNikud: settingsState.defaultRemoveNikud,
                      // בתצוגה משולבת, חלונית הצד תמיד סגורה
                      forceCloseLeftPane: widget.isInCombinedView,
                    ),
                  );
                }

                if (state is TextBookInitial || state is TextBookLoading) {
                  final isCompact = context
                      .read<SettingsBloc>()
                      .state
                      .compactMenuMode;
                  return Scaffold(
                    body: Column(
                      children: [
                        AppTopBar(
                          leadingItems: [
                            AppTopBarItem(
                              widget: BarButton.icon(
                                tooltip: 'ניווט וחיפוש',
                                icon: FluentIcons.navigation_24_regular,
                                compact: isCompact,
                                onPressed: () {},
                              ),
                            ),
                          ],
                          center: Text(
                            widget.tab.book.title,
                            style: AppTopBar.titleStyle(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Expanded(
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ],
                    ),
                  );
                }

                if (state is TextBookError) {
                  return Center(child: Text('Error: ${(state).message}'));
                }

                if (state is TextBookLoaded) {
                  // בקשת focus אוטומטית כשהספר נטען
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) {
                      return;
                    }

                    if (state.showPageShapeView) {
                      // hasPrimaryFocus ולא hasFocus: ה-KeyboardListener הזה עוטף
                      // את כל גוף המסך (כולל פאנל החיפוש), ו-hasFocus מחזיר true
                      // גם כשצאצא (שדה החיפוש) ממוקד. unfocus כזה היה מסיר פוקוס
                      // מכל התת-עץ ומבריח את הסמן משדה החיפוש בכל הקלדה. כאן
                      // משחררים פוקוס רק אם ה-node הזה עצמו מחזיק בפוקוס.
                      if (_bookContentFocusNode.hasPrimaryFocus) {
                        _bookContentFocusNode.unfocus();
                      }
                      return;
                    }

                    // ה-callback הזה נרשם בכל build — כולל כשפתיחת מקלדת
                    // וירטואלית משנה את ה-viewport וגורמת rebuild. אסור לחטוף
                    // פוקוס כשהמשתמש נמצא בדיאלוג מעל המסך (חיפוש/איתור) או
                    // בשדה קלט כלשהו — חטיפה כזו סוגרת את המקלדת מיד אחרי
                    // שנפתחה (ראה תקדים דומה ב-resolveLeftPaneSearchFocus).
                    if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
                      return;
                    }
                    if (isTextInputFocusNode(
                      FocusManager.instance.primaryFocus,
                    )) {
                      return;
                    }

                    if (!_bookContentFocusNode.hasFocus &&
                        !textSearchFocusNode.hasFocus &&
                        !navigationSearchFocusNode.hasFocus &&
                        !altTitlesSearchFocusNode.hasFocus) {
                      // ממקד את אזור הגלילה (ProgressiveScroll) דרך ה-requester
                      // שרשם CombinedView; הוא צאצא של ה-KeyboardListener הזה,
                      // לכן Ctrl+P/Home וכו' ממשיכים לעבוד. fallback ל-node הזה
                      // אם אין requester (למשל צורת הדף).
                      final didFocus =
                          _focusRepository?.requestTabContentFocus(
                            widget.tab,
                          ) ??
                          false;
                      if (!didFocus) _bookContentFocusNode.requestFocus();
                    }
                  });

                  final wideScreen = MediaQuery.of(context).size.width >= 600;
                  return KeyboardListener(
                    focusNode: _bookContentFocusNode,
                    autofocus: false,
                    onKeyEvent: (event) => _handleGlobalKeyEvent(
                      event,
                      context,
                      state,
                      widget.tab,
                      openSearchFromToolbar: _openSearchFromToolbar,
                      openNotesForCurrentView: () =>
                          _openPersonalNotesForCurrentView(state),
                      selectedTextForNote: _selectedTextForSearch,
                      selectedLineForNote: _selectedLineForNote,
                      selectedColumnForNote: _selectedColumnForNote,
                    ),
                    child: Scaffold(
                      body: Column(
                        children: [
                          _buildAppBar(context, state, wideScreen),
                          Expanded(child: _buildBody(context, state)),
                        ],
                      ),
                    ),
                  );
                }

                // Fallback
                return const Center(child: Text('Unknown state'));
              },
            );
          },
        );
      },
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    TextBookLoaded state,
    bool wideScreen,
  ) {
    return AppTopBar(
      leadingItems: [
        AppTopBarItem(widget: _buildMenuButton(context, state)),
        if (state.showPageShapeView)
          AppTopBarItem(widget: _buildPageShapeSettingsButton(context, state)),
      ],
      center: widget.isInCombinedView
          ? _buildTitle(state)
          : ReaderNavCenter(
              title: _buildTitle(state, textAlign: TextAlign.center),
              prevMajorTooltip: 'הדף/פרק הקודם',
              prevMinorTooltip: 'הקטע הקודם',
              nextMinorTooltip: 'הקטע הבא',
              nextMajorTooltip: 'הדף/פרק הבא',
              onPrevMajor: () => _navigateToPreviousToc(state),
              onPrevMinor: () => _scrollToPreviousSegment(state),
              onNextMinor: () => _scrollToNextSegment(state),
              onNextMajor: () => _navigateToNextToc(state),
            ),
      trailingItems: [
        AppTopBarItem(
          widget: Row(
            mainAxisSize: MainAxisSize.min,
            children: _buildActions(context, state, wideScreen),
          ),
        ),
      ],
    );
  }

  /// כפתור הגדרות צורת הדף.
  /// הדיאלוג נפתח ע"י PageShapeScreen עצמו (דרך ה-notifier), כדי שכל שינוי
  /// בדיאלוג יוחל על המסך בעדכון חי בלי להמתין לסגירתו.
  Widget _buildPageShapeSettingsButton(
    BuildContext context,
    TextBookLoaded state,
  ) {
    final isCompact = context.read<SettingsBloc>().state.compactMenuMode;
    return BarButton.icon(
      tooltip: 'הגדרות צורת הדף',
      icon: FluentIcons.settings_24_regular,
      compact: isCompact,
      onPressed: () => _pageShapeOpenSettingsNotifier.value++,
    );
  }

  Widget _buildTitle(
    TextBookLoaded state, {
    TextAlign textAlign = TextAlign.end,
  }) {
    if (state.currentTitle == null) {
      return const SizedBox.shrink();
    }

    // שימוש בפונקציה העזר להוספת שם הספר
    String displayText = addBookTitleToRef(
      state.currentTitle!,
      state.book.title,
    );

    final author = state.book.author;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // line-height מרוסן כדי ששתי השורות ייכנסו בגובה הסרגל הקומפקטי
        // (פונטים עבריים בעלי מטריקות גבוהות גרמו לחריגת RenderFlex).
        final titleStyle = AppTopBar.titleStyle(context).copyWith(height: 1.1);
        final authorStyle = AppTopBar.subtitleStyle(
          context,
        ).copyWith(height: 1.1);
        final textPainter = TextPainter(
          text: TextSpan(text: displayText, style: titleStyle),
          textDirection: Directionality.of(context),
          maxLines: 1,
        )..layout(minWidth: 0, maxWidth: constraints.maxWidth);

        // כשהכותרת בפורמט "שם הספר, מיקום" מציגים אותם כשני חלקים: השם מתקצר
        // (ellipsis) לפי המקום הפנוי, אך המיקום נשאר גלוי במלואו — נחוץ לחברותא
        // שבה אין מידע אחר על המיקום.
        final namePrefix = '${state.book.title}, ';
        final hasSeparateLocation = displayText.startsWith(namePrefix);
        final rowAlignment = switch (textAlign) {
          TextAlign.center => MainAxisAlignment.center,
          TextAlign.start => MainAxisAlignment.start,
          _ => MainAxisAlignment.end,
        };

        final titleWidget = AppSelectionArea(
          child: hasSeparateLocation
              ? Row(
                  mainAxisAlignment: rowAlignment,
                  children: [
                    Flexible(
                      child: Text(
                        namePrefix,
                        style: titleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      displayText.substring(namePrefix.length),
                      style: titleStyle,
                      maxLines: 1,
                    ),
                  ],
                )
              : Text(
                  displayText,
                  style: titleStyle,
                  textAlign: textAlign,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
        );

        // אם יש מחבר, מציגים אותו מתחת לכותרת
        final child = author != null && author.isNotEmpty
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  titleWidget,
                  Text(
                    author,
                    style: authorStyle,
                    textAlign: textAlign,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              )
            : titleWidget;

        if (textPainter.didExceedMaxLines) {
          return Tooltip(
            message: author != null ? '$displayText\n$author' : displayText,
            child: child,
          );
        }

        return child;
      },
    );
  }

  Widget _buildMenuButton(BuildContext context, TextBookLoaded state) {
    final isCompact = context.read<SettingsBloc>().state.compactMenuMode;
    return BarButton.icon(
      key: widget.enableTourTargets ? textBookNavigationTourTargetKey : null,
      tooltip: 'ניווט וחיפוש',
      icon: FluentIcons.navigation_24_regular,
      compact: isCompact,
      onPressed: () =>
          context.read<TextBookBloc>().add(ToggleLeftPane(!state.showLeftPane)),
    );
  }

  List<Widget> _buildActions(
    BuildContext context,
    TextBookLoaded state,
    bool wideScreen,
  ) {
    final maxButtons = maxToolbarButtonsForWidth(
      MediaQuery.of(context).size.width,
    );

    return [
      Consumer<ShamorZachorDataProvider>(
        builder: (context, _, _) => ResponsiveActionBar(
          key: const ValueKey('responsive_actions'),
          overflowMenuOffset: const Offset(0, 8),
          overflowButtonKey: widget.enableTourTargets
              ? textBookOverflowTourTargetKey
              : null,
          menuItemKeysByTooltip: widget.enableTourTargets
              ? {
                  _getViewModeTooltip(state):
                      textBookOverflowCommentatorsTourTargetKey,
                  'סימניות בספר זה': textBookOverflowBookmarkTourTargetKey,
                  'חיפוש': textBookOverflowSearchTourTargetKey,
                  'הדפסה': textBookOverflowPrintTourTargetKey,
                }
              : null,
          actions: _buildDisplayOrderActions(context, state),
          alwaysInMenu: _buildAlwaysInMenuActions(context, state),
          maxVisibleButtons: maxButtons,
        ),
      ),
    ];
  }

  /// בניית רשימת כפתורים בסדר ההצגה (מימין לשמאל ב-RTL)
  /// הכפתורים יוסתרו מהסוף לתחילה, כך שהכפתור הימני ביותר (ראשון ברשימה) יעלם אחרון
  List<ActionButtonData> _buildDisplayOrderActions(
    BuildContext context,
    TextBookLoaded state,
  ) {
    return [
      // 1) PDF Button (ראשון מימין - יעלם אחרון!)
      if (_hasPdfBook)
        ActionButtonData(
          widget: BarButton.icon(
            tooltip: 'פתח ספר במהדורה מודפסת',
            icon: FluentIcons.document_pdf_24_regular,
            compact: context.read<SettingsBloc>().state.compactMenuMode,
            onPressed: () => _handlePdfButtonPress(context, state),
          ),
          icon: FluentIcons.document_pdf_24_regular,
          tooltip: 'פתח ספר במהדורה מודפסת',
          onPressed: () => _handlePdfButtonPress(context, state),
        ),

      // 2) View Mode Dropdown (מאחד את Split View ו-Page Shape View)
      ActionButtonData(
        widget: KeyedSubtree(
          key: widget.enableTourTargets
              ? textBookCommentatorsTourTargetKey
              : null,
          child: _buildViewModeDropdown(context, state),
        ),
        icon: _getViewModeIcon(state),
        tooltip: _getViewModeTooltip(state),
        // ב-overflow הכפתור עצמו לא בנוי בעץ, לכן המצבים מוצגים כתת-תפריט
        submenuItems: [
          ActionButtonData(
            widget: const SizedBox.shrink(),
            icon: FluentIcons.panel_left_24_regular,
            tooltip: 'מפרשים בצד',
            onPressed: () =>
                _onViewModeSelected(context, state, _viewModeSplit),
          ),
          ActionButtonData(
            widget: const SizedBox.shrink(),
            icon: FluentIcons.panel_bottom_20_regular,
            tooltip: 'מפרשים מתחת',
            onPressed: () =>
                _onViewModeSelected(context, state, _viewModeBelow),
          ),
          ActionButtonData(
            widget: const SizedBox.shrink(),
            icon: FluentIcons.book_open_24_regular,
            tooltip: 'צורת הדף',
            onPressed: () => _onViewModeSelected(context, state, _viewModePage),
          ),
          ActionButtonData(
            widget: const SizedBox.shrink(),
            icon: FluentIcons.open_24_regular,
            tooltip: 'פתח כרטיסיית מפרשים',
            onPressed: () =>
                _onViewModeSelected(context, state, _actionOpenCommentatorsTab),
          ),
        ],
      ),

      // 3) Nikud Button
      ActionButtonData(
        widget: _buildNikudButton(context, state),
        icon: state.removeNikud
            ? FluentIcons.text_font_24_regular
            : FluentIcons.text_font_info_24_regular,
        tooltip: state.removeNikud ? 'הצג ניקוד' : 'הסתר ניקוד',
        onPressed: () async {
          final newValue = !state.removeNikud;
          context.read<TextBookBloc>().add(ToggleNikud(newValue));
          await savePerBookDisplaySettings(
            context,
            state,
            removeNikud: newValue,
          );
        },
      ),

      // 3b) Punctuation Button - מוסתר בספרי תנ"ך
      if (!state.isTanach)
        ActionButtonData(
          widget: _buildPunctuationButton(context, state),
          icon: state.removePunctuation
              ? FluentIcons.text_quote_24_regular
              : FluentIcons.text_clear_formatting_24_regular,
          tooltip: state.removePunctuation ? 'הצג פיסוק' : 'הסתר פיסוק',
          onPressed: () => _toggleAndSavePunctuation(context, state),
        ),

      // 3c) Continuous Reading Mode Button - רק לספרים שתומכים (תנ"ך/תלמוד)
      if (state.supportsContinuousReadingMode)
        ActionButtonData(
          widget: _buildContinuousReadingButton(context, state),
          icon: state.continuousReadingMode
              ? FluentIcons.text_align_justify_24_filled
              : FluentIcons.text_align_justify_24_regular,
          tooltip: state.continuousReadingMode
              ? 'הצג כשורות בודדות'
              : 'הצג כטקסט רציף',
          onPressed: () => _toggleAndSaveContinuousReading(context, state),
        ),

      // 4) Search Button
      ActionButtonData(
        widget: _buildSearchButton(
          context,
          state,
          key: widget.enableTourTargets ? textBookSearchTourTargetKey : null,
        ),
        icon: FluentIcons.search_24_regular,
        tooltip: 'חיפוש',
        onPressed: _openSearchFromToolbar,
      ),

      // 5) Zoom In Button
      ActionButtonData(
        widget: _buildZoomInButton(context, state),
        icon: FluentIcons.zoom_in_24_regular,
        tooltip: 'הגדל את גודל הטקסט',
        onPressed: () async {
          final newSize = min(50.0, state.fontSize + 3);
          context.read<TextBookBloc>().add(UpdateFontSize(newSize));
          await savePerBookDisplaySettings(context, state, fontSize: newSize);
        },
      ),

      // 6) Zoom Out Button
      ActionButtonData(
        widget: _buildZoomOutButton(context, state),
        icon: FluentIcons.zoom_out_24_regular,
        tooltip: 'הקטן את גודל הטקסט',
        onPressed: () async {
          final newSize = max(15.0, state.fontSize - 3);
          context.read<TextBookBloc>().add(UpdateFontSize(newSize));
          await savePerBookDisplaySettings(context, state, fontSize: newSize);
        },
      ),
    ];
  }

  /// כפתורים שתמיד יהיו בתפריט "..." (בסדר הרצוי)
  List<ActionButtonData> _buildAlwaysInMenuActions(
    BuildContext context,
    TextBookLoaded state,
  ) {
    final navigationActions = _buildNavigationActions(context, state);
    return [
      // כפתורי ניווט - רק בתצוגה משולבת
      if (widget.isInCombinedView) ...navigationActions,

      // הצגת סימניות הספר הנוכחי (הוספת סימניה עברה לתפריט ההקשר בטקסט)
      ActionButtonData(
        widget: KeyedSubtree(
          key: widget.enableTourTargets ? textBookBookmarkTourTargetKey : null,
          child: BarButton.icon(
            tooltip: 'סימניות בספר זה',
            icon: FluentIcons.bookmark_multiple_24_regular,
            compact: context.read<SettingsBloc>().state.compactMenuMode,
            onPressed: () => _showBookmarksForCurrentBook(context, state.book),
          ),
        ),
        icon: FluentIcons.bookmark_multiple_24_regular,
        tooltip: 'סימניות בספר זה',
        onPressed: () => _showBookmarksForCurrentBook(context, state.book),
      ),

      // 2) הצג הערות אישיות
      ActionButtonData(
        widget: BarButton.icon(
          tooltip: 'הצג הערות אישיות',
          icon: FluentIcons.note_24_regular,
          compact: context.read<SettingsBloc>().state.compactMenuMode,
          onPressed: () => _openPersonalNotesForCurrentView(state),
        ),
        icon: FluentIcons.note_24_regular,
        tooltip: 'הצג הערות אישיות',
        onPressed: () => _openPersonalNotesForCurrentView(state),
      ),

      // 3) שמור וזכור - סמן כנלמד או הוסף למעקב
      ActionButtonData(
        widget: _buildShamorZachorButton(context, state),
        icon: _isBookTrackedInShamorZachor(state.book)
            ? FluentIcons.checkmark_circle_24_regular
            : FluentIcons.add_circle_24_regular,
        tooltip: _isBookTrackedInShamorZachor(state.book)
            ? 'סמן קטע פתוח כנלמד בשמור וזכור'
            : 'הוסף למעקב לימוד בשמור וזכור',
        onPressed: () {
          if (_isBookTrackedInShamorZachor(state.book)) {
            _markShamorZachorProgress(state.book.title);
          } else {
            _addBookToShamorZachorTracking(state.book);
          }
        },
      ),

      // 4) איפוס הגדרות פר-ספר (מוצג רק כשההגדרה מופעלת) - לא בתצוגה משולבת
      if (!widget.isInCombinedView &&
          context.read<SettingsBloc>().state.enablePerBookSettings)
        ActionButtonData.simple(
          icon: FluentIcons.arrow_reset_24_regular,
          tooltip: 'אפס הגדרות ספר זה',
          onPressed: _resetPerBookSettings,
          compact: false,
          visual: ActionButtonVisual.iconButton,
        ),

      // [EDITING DISABLED]
      // // 5) ערוך את הספר - לא בתצוגה משולבת
      // if (!widget.isInCombinedView)
      //   ActionButtonData(
      //     widget: _buildFullFileEditorButton(context, state),
      //     icon: FluentIcons.document_edit_24_regular,
      //     tooltip: 'ערוך את הספר',
      //     onPressed: () => _handleFullFileEditorPress(context, state),
      //   ),

      // העתק קישור ישיר לספר זה (קישור למקטע/הדגשה זמין בתפריט הלחיצה הימנית)
      ActionButtonData(
        widget: const SizedBox.shrink(),
        icon: FluentIcons.link_24_regular,
        tooltip: state.book.id != null
            ? 'העתק קישור ישיר לספר זה'
            : 'העתק קישור ישיר (לא זמין לספר זה)',
        onPressed: state.book.id != null
            ? () => copyLinkToClipboard(buildBookLink(state.book.id!))
            : null,
      ),

      // ייצוא הספר המלא - Word מעוצב או טקסט פשוט
      if (!widget.isInCombinedView)
        ActionButtonData(
          widget: const SizedBox.shrink(),
          icon: FluentIcons.arrow_export_ltr_24_regular,
          tooltip: 'ייצוא הספר',
          onPressed: () => _exportWholeBook(state),
        ),

      // 6) הדפסה - לא בתצוגה משולבת
      if (!widget.isInCombinedView)
        ActionButtonData(
          widget: _buildPrintButton(
            context,
            state,
            key: widget.enableTourTargets ? textBookPrintTourTargetKey : null,
          ),
          icon: FluentIcons.print_24_regular,
          tooltip: 'הדפסה',
          onPressed: () => _handlePrintPress(state),
        ),

      // 7) אודות הספר - לא בתצוגה משולבת
      if (!widget.isInCombinedView)
        ActionButtonData(
          widget: IconButton(
            icon: const Icon(FluentIcons.book_information_24_regular),
            tooltip: 'אודות הספר',
            onPressed: () => _handleBookSourcePress(context, state),
          ),
          icon: FluentIcons.book_information_24_regular,
          tooltip: 'אודות הספר',
          onPressed: () => _handleBookSourcePress(context, state),
        ),

      // תת-תפריט "פעולות נוספות" - רק בתצוגה משולבת
      if (widget.isInCombinedView)
        ActionButtonData(
          widget: const SizedBox.shrink(), // לא נראה כי זה בתפריט
          icon: FluentIcons.more_horizontal_24_regular,
          tooltip: 'פעולות נוספות',
          onPressed: null, // לא ניתן ללחיצה - זה submenu
          submenuItems: [
            // איפוס הגדרות פר-ספר (מוצג רק כשההגדרה מופעלת)
            if (context.read<SettingsBloc>().state.enablePerBookSettings)
              ActionButtonData(
                widget: const SizedBox.shrink(),
                icon: FluentIcons.arrow_reset_24_regular,
                tooltip: 'אפס הגדרות ספר זה',
                onPressed: () => _resetPerBookSettings(),
              ),
            // [EDITING DISABLED]
            // ActionButtonData(
            //   widget: const SizedBox.shrink(),
            //   icon: FluentIcons.document_edit_24_regular,
            //   tooltip: 'ערוך את הספר',
            //   onPressed: () => _handleFullFileEditorPress(context, state),
            // ),
            ActionButtonData(
              widget: const SizedBox.shrink(),
              icon: FluentIcons.print_24_regular,
              tooltip: 'הדפסה',
              onPressed: () => _handlePrintPress(state),
            ),
            ActionButtonData(
              widget: const SizedBox.shrink(),
              icon: FluentIcons.arrow_export_ltr_24_regular,
              tooltip: 'ייצוא הספר',
              onPressed: () => _exportWholeBook(state),
            ),
            ActionButtonData(
              widget: const SizedBox.shrink(),
              icon: FluentIcons.book_information_24_regular,
              tooltip: 'אודות הספר',
              onPressed: () => _handleBookSourcePress(context, state),
            ),
          ],
        ),
    ];
  }

  List<ActionButtonData> _buildNavigationActions(
    BuildContext context,
    TextBookLoaded state,
  ) {
    return buildBookViewNavigationActions(
      firstAction: buildBookViewFirstNavigationAction(
        widget: _buildPreviousTocButton(context, state),
        tooltip: 'הדף/פרק הקודם',
        onPressed: () => _navigateToPreviousToc(state),
      ),
      previousAction: buildBookViewPreviousNavigationAction(
        widget: _buildPreviousPageButton(context, state),
        tooltip: 'הקטע הקודם',
        onPressed: () => _scrollToPreviousSegment(state),
      ),
      nextAction: buildBookViewNextNavigationAction(
        widget: _buildNextPageButton(context, state),
        tooltip: 'הקטע הבא',
        onPressed: () => _scrollToNextSegment(state),
      ),
      lastAction: buildBookViewLastNavigationAction(
        widget: _buildNextTocButton(context, state),
        tooltip: 'הדף/פרק הבא',
        onPressed: () => _navigateToNextToc(state),
      ),
    );
  }

  /// קבלת האייקון המתאים למצב התצוגה הנוכחי
  IconData _getViewModeIcon(TextBookLoaded state) {
    if (state.showPageShapeView) {
      return FluentIcons.book_open_24_filled;
    }
    if (state.showSplitView) {
      return FluentIcons.panel_left_24_regular;
    }
    return FluentIcons.panel_bottom_20_regular;
  }

  /// קבלת ה-tooltip למצב התצוגה הנוכחי
  String _getViewModeTooltip(TextBookLoaded state) {
    if (state.showPageShapeView) {
      return 'תצוגה: צורת הדף';
    } else if (state.showSplitView) {
      return 'תצוגה: מפרשים בצד';
    } else {
      return 'תצוגה: מפרשים מתחת';
    }
  }

  /// טיפול בבחירת מצב תצוגה — משותף לתפריט הכפתור ולתת-התפריט ב-overflow
  Future<void> _onViewModeSelected(
    BuildContext context,
    TextBookLoaded state,
    String value,
  ) async {
    // פתיחת כרטיסיית מפרשים נפרדת — פעולה, לא מצב תצוגה
    if (value == _actionOpenCommentatorsTab) {
      context.read<TabsBloc>().add(
        AddTab(
          CommentatorsTab(sourceTab: widget.tab),
          insertAdjacent: true,
        ),
      );
      return;
    }

    final bloc = context.read<TextBookBloc>();
    final tourCubit = context.read<TourCubit>();

    // קביעת מצב היעד לפי הבחירה
    final bool isPageSelected = value == _viewModePage;
    final bool isSplitSelected = value == _viewModeSplit;

    // עדכון תצוגת צורת הדף במידת הצורך
    if (isPageSelected != state.showPageShapeView) {
      bloc.add(TogglePageShapeView(isPageSelected));
    }

    // עדכון תצוגת המפרשים במידת הצורך (רק במצבים שאינם 'צורת הדף')
    if (!isPageSelected && isSplitSelected != state.showSplitView) {
      bloc.add(ToggleSplitView(isSplitSelected));
      await savePerBookDisplaySettings(
        context,
        state,
        showSplitView: isSplitSelected,
      );
    }

    if (isPageSelected || isSplitSelected) {
      tourCubit.recordInteraction(
        TourInteraction(
          type: TourInteractionType.commentaryUsed,
          primaryValue: widget.tab.title,
        ),
      );
    }
  }

  /// בניית תפריט נפתח לבחירת מצב תצוגה
  Widget _buildViewModeDropdown(BuildContext context, TextBookLoaded state) {
    final iconWidget = Icon(_getViewModeIcon(state));

    final isSplit = !state.showPageShapeView && state.showSplitView;
    final isBelow = !state.showPageShapeView && !state.showSplitView;
    final isPage = state.showPageShapeView;

    return AppPopupMenuButton<String>(
      tooltip: 'בחר סוג תצוגת מפרשים',
      iconData: _getViewModeIcon(state),
      icon: iconWidget,
      initialValue: state.showPageShapeView
          ? _viewModePage
          : (state.showSplitView ? _viewModeSplit : _viewModeBelow),
      onSelected: (value) => _onViewModeSelected(context, state, value),
      entries: [
        AppMenuEntry(
          value: _viewModeSplit,
          label: 'מפרשים בצד',
          icon: isSplit
              ? FluentIcons.panel_left_24_filled
              : FluentIcons.panel_left_24_regular,
        ),
        AppMenuEntry(
          value: _viewModeBelow,
          label: 'מפרשים מתחת',
          icon: isBelow
              ? FluentIcons.panel_bottom_20_filled
              : FluentIcons.panel_bottom_20_regular,
        ),
        AppMenuEntry(
          value: _viewModePage,
          label: 'צורת הדף',
          icon: isPage
              ? FluentIcons.book_open_24_filled
              : FluentIcons.book_open_24_regular,
        ),
        const AppMenuEntry(
          value: _actionOpenCommentatorsTab,
          label: 'פתח כרטיסיית מפרשים',
          icon: FluentIcons.open_24_regular,
        ),
      ],
    );
  }

  Widget _buildNikudButton(BuildContext context, TextBookLoaded state) {
    final isCompact = context.read<SettingsBloc>().state.compactMenuMode;
    return BarButton.icon(
      tooltip: state.removeNikud ? 'הצג ניקוד' : 'הסתר ניקוד',
      icon: state.removeNikud
          ? FluentIcons.text_font_24_regular
          : FluentIcons.text_font_info_24_regular,
      compact: isCompact,
      onPressed: () async {
        final newValue = !state.removeNikud;
        context.read<TextBookBloc>().add(ToggleNikud(newValue));
        await savePerBookDisplaySettings(context, state, removeNikud: newValue);
      },
    );
  }

  Future<void> _toggleAndSavePunctuation(
    BuildContext context,
    TextBookLoaded state,
  ) async {
    final newValue = !state.removePunctuation;
    context.read<TextBookBloc>().add(TogglePunctuation(newValue));
    await savePerBookDisplaySettings(
      context,
      state,
      removePunctuation: newValue,
    );
  }

  Widget _buildPunctuationButton(BuildContext context, TextBookLoaded state) {
    final isCompact = context.read<SettingsBloc>().state.compactMenuMode;
    return BarButton.icon(
      tooltip: state.removePunctuation ? 'הצג פיסוק' : 'הסתר פיסוק',
      icon: state.removePunctuation
          ? FluentIcons.text_quote_24_regular
          : FluentIcons.text_clear_formatting_24_regular,
      compact: isCompact,
      onPressed: () => _toggleAndSavePunctuation(context, state),
    );
  }

  Future<void> _toggleAndSaveContinuousReading(
    BuildContext context,
    TextBookLoaded state,
  ) async {
    final newValue = !state.continuousReadingMode;
    context.read<TextBookBloc>().add(ToggleContinuousReadingMode(newValue));
    await savePerBookDisplaySettings(
      context,
      state,
      continuousReadingMode: newValue,
    );
  }

  Widget _buildContinuousReadingButton(
    BuildContext context,
    TextBookLoaded state,
  ) {
    final isCompact = context.read<SettingsBloc>().state.compactMenuMode;
    return BarButton.icon(
      tooltip: state.continuousReadingMode
          ? 'הצג כשורות בודדות'
          : 'הצג כטקסט רציף',
      icon: state.continuousReadingMode
          ? FluentIcons.text_align_justify_24_filled
          : FluentIcons.text_align_justify_24_regular,
      compact: isCompact,
      onPressed: () => _toggleAndSaveContinuousReading(context, state),
    );
  }

  void _showBookmarksForCurrentBook(BuildContext context, Book book) {
    showDialog(
      context: context,
      builder: (_) => BookmarksDialog(bookFilter: book),
    );
  }

  Widget _buildSearchButton(
    BuildContext context,
    TextBookLoaded state, {
    Key? key,
  }) {
    final shortcut =
        ShortcutValidator.getShortcutValue(
          ShortcutValidator.currentWindowSearchKey,
        ) ??
        'ctrl+f';
    final isCompact = context.read<SettingsBloc>().state.compactMenuMode;
    return BarButton.icon(
      key: key,
      tooltip: 'חיפוש (${shortcut.toUpperCase()})',
      icon: FluentIcons.search_24_regular,
      compact: isCompact,
      onPressed: _openSearchFromToolbar,
    );
  }

  Widget _buildZoomInButton(BuildContext context, TextBookLoaded state) {
    final isCompact = context.read<SettingsBloc>().state.compactMenuMode;
    return BarButton.icon(
      tooltip:
          'הגדל את גודל הטקסט (${ShortcutHelper.formatShortcutForDisplay('ctrl++')})',
      icon: FluentIcons.zoom_in_24_regular,
      compact: isCompact,
      onPressed: () async {
        final newSize = min(50.0, state.fontSize + 3);
        context.read<TextBookBloc>().add(UpdateFontSize(newSize));
        await savePerBookDisplaySettings(context, state, fontSize: newSize);
      },
    );
  }

  Widget _buildZoomOutButton(BuildContext context, TextBookLoaded state) {
    final isCompact = context.read<SettingsBloc>().state.compactMenuMode;
    return BarButton.icon(
      tooltip:
          'הקטן את גודל הטקסט (${ShortcutHelper.formatShortcutForDisplay('ctrl+-')})',
      icon: FluentIcons.zoom_out_24_regular,
      compact: isCompact,
      onPressed: () async {
        final newSize = max(15.0, state.fontSize - 3);
        context.read<TextBookBloc>().add(UpdateFontSize(newSize));
        await savePerBookDisplaySettings(context, state, fontSize: newSize);
      },
    );
  }

  Widget _buildPreviousPageButton(BuildContext context, TextBookLoaded state) {
    final isCompact = context.read<SettingsBloc>().state.compactMenuMode;
    return BarButton.icon(
      tooltip: 'הקטע הקודם',
      icon: FluentIcons.chevron_left_24_regular,
      compact: isCompact,
      onPressed: () => _scrollToPreviousSegment(state),
    );
  }

  /// מריץ פעולת ניווט מקיצור מקלדת מול ה-state הנוכחי, אם הספר כבר נטען.
  void _runNavigation(void Function(TextBookLoaded) action) {
    if (!mounted) return;
    final state = context.read<TextBookBloc>().state;
    if (state is TextBookLoaded) action(state);
  }

  void _onNavPreviousSegment() => _runNavigation(_scrollToPreviousSegment);
  void _onNavNextSegment() => _runNavigation(_scrollToNextSegment);
  void _onNavPreviousToc() => _runNavigation(_navigateToPreviousToc);
  void _onNavNextToc() => _runNavigation(_navigateToNextToc);

  void _scrollToPreviousSegment(TextBookLoaded state) {
    final positions = state.positionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    state.scrollController.scrollTo(
      duration: const Duration(milliseconds: 300),
      index: max(0, _topmostVisibleIndex(state) - 1),
    );
  }

  void _scrollToNextSegment(TextBookLoaded state) {
    final positions = state.positionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    state.scrollController.scrollTo(
      duration: const Duration(milliseconds: 300),
      index: _bottommostVisibleIndex(state) + 1,
    );
  }

  Widget _buildNextPageButton(BuildContext context, TextBookLoaded state) {
    final isCompact = context.read<SettingsBloc>().state.compactMenuMode;
    return BarButton.icon(
      tooltip: 'הקטע הבא',
      icon: FluentIcons.chevron_right_24_regular,
      compact: isCompact,
      onPressed: () => _scrollToNextSegment(state),
    );
  }

  /// מחזיר רשימה ממוינת של כל אינדקסי ה-TOC (עם cache)
  List<int> _getSortedTocIndices(List<TocEntry> entries, String bookTitle) {
    // אם יש cache תקף, נשתמש בו (בודקים גם את זהות רשימת ה-TOC)
    if (_cachedTocIndices != null &&
        _cachedTocBookTitle == bookTitle &&
        identical(_cachedToc, entries)) {
      return _cachedTocIndices!;
    }

    // יוצרים רשימה שטוחה של כל האינדקסים
    final allIndices = <int>[];

    void collectIndices(List<TocEntry> toc) {
      for (final entry in toc) {
        allIndices.add(entry.index);
        collectIndices(entry.children);
      }
    }

    collectIndices(entries);
    allIndices.sort();

    // שומרים ב-cache
    _cachedTocIndices = allIndices;
    _cachedTocBookTitle = bookTitle;
    _cachedToc = entries;

    return allIndices;
  }

  /// מוצא את הכותרת הבאה (דף/פרק) מתוך תוכן העניינים
  /// מחזיר את האינדקס של הכותרת הבאה, או null אם אין
  int? _findNextTocIndex(
    List<TocEntry> entries,
    int currentIndex,
    String bookTitle,
  ) {
    final allIndices = _getSortedTocIndices(entries, bookTitle);

    // חיפוש בינארי יעיל יותר
    int low = 0;
    int high = allIndices.length - 1;

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (allIndices[mid] <= currentIndex) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    return low < allIndices.length ? allIndices[low] : null;
  }

  /// מוצא את הכותרת הקודמת (דף/פרק) מתוך תוכן העניינים
  /// מחזיר את האינדקס של הכותרת הקודמת, או null אם אין
  int? _findPreviousTocIndex(
    List<TocEntry> entries,
    int currentIndex,
    String bookTitle,
  ) {
    final allIndices = _getSortedTocIndices(entries, bookTitle);

    // חיפוש בינארי יעיל יותר
    int low = 0;
    int high = allIndices.length - 1;

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (allIndices[mid] < currentIndex) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    return high >= 0 ? allIndices[high] : null;
  }

  /// ניווט לכותרת הקודמת ב-TOC
  void _navigateToPreviousToc(TextBookLoaded state) {
    final currentIndex = _topmostVisibleSourceLine(state);
    final prevIndex = _findPreviousTocIndex(
      state.tableOfContents,
      currentIndex,
      state.book.title,
    );
    if (prevIndex != null) {
      state.scrollController.scrollTo(
        // ה-TOC עובד בשורות מקור; ה-ListView לפי itemIndex (=segmentIndex
        // במצב רצף).
        index: _itemIndexForSourceLine(state, prevIndex),
        duration: const Duration(milliseconds: 300),
      );
    }
  }

  /// ניווט לכותרת הבאה ב-TOC
  void _navigateToNextToc(TextBookLoaded state) {
    final currentIndex = _bottommostVisibleSourceLine(state);
    final nextIndex = _findNextTocIndex(
      state.tableOfContents,
      currentIndex,
      state.book.title,
    );
    if (nextIndex != null) {
      state.scrollController.scrollTo(
        index: _itemIndexForSourceLine(state, nextIndex),
        duration: const Duration(milliseconds: 300),
      );
    }
  }

  Widget _buildPreviousTocButton(BuildContext context, TextBookLoaded state) {
    final isCompact = context.read<SettingsBloc>().state.compactMenuMode;
    return BarButton.icon(
      tooltip: 'הדף/פרק הקודם',
      icon: FluentIcons.arrow_previous_24_filled,
      compact: isCompact,
      onPressed: () => _navigateToPreviousToc(state),
    );
  }

  Widget _buildNextTocButton(BuildContext context, TextBookLoaded state) {
    final isCompact = context.read<SettingsBloc>().state.compactMenuMode;
    return BarButton.icon(
      tooltip: 'הדף/פרק הבא',
      icon: FluentIcons.arrow_next_24_filled,
      compact: isCompact,
      onPressed: () => _navigateToNextToc(state),
    );
  }

  Widget _buildPrintButton(
    BuildContext context,
    TextBookLoaded state, {
    Key? key,
  }) {
    final shortcut =
        Settings.getValue<String>('key-shortcut-print') ?? 'ctrl+p';
    return IconButton(
      key: key,
      icon: const Icon(FluentIcons.print_24_regular),
      tooltip: 'הדפסה (${shortcut.toUpperCase()})',
      onPressed: () {
        context.read<TourCubit>().recordInteraction(
          TourInteraction(type: TourInteractionType.printUsed),
        );
        final settingsState = context.read<SettingsBloc>().state;
        // תוכן מלא מה-repository — state.content יכול להיות חלקי (חימום/שחרור).
        // חובה לקרוא כאן: בתוך ה-builder ה-context הוא של הדיאלוג וחסר לו provider ל-TextBookBloc.
        final contentData = context
            .read<TextBookBloc>()
            .repository
            .getBookContent(state.book);
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => PrintingScreen(
            data: contentData,
            bookId: state.book.title,
            book: state.book,
            links: state.links,
            activeCommentators: state.activeCommentators,
            startLine: state.visibleIndices.first,
            removeNikud: state.removeNikud,
            removeTaamim: !settingsState.showTeamim,
            tableOfContents: state.tableOfContents,
          ),
        );
      },
    );
  }

  Widget _buildShamorZachorButton(BuildContext context, TextBookLoaded state) {
    final isTracked = _isBookTrackedInShamorZachor(state.book);
    final isCompact = context.read<SettingsBloc>().state.compactMenuMode;
    final iconSize = isCompact ? 16.0 : 20.0;
    return BarButton.icon(
      tooltip: isTracked
          ? 'סמן קטע פתוח כנלמד בשמור וזכור'
          : 'הוסף למעקב לימוד בשמור וזכור',
      icon: isTracked
          ? FluentIcons.checkmark_circle_24_regular
          : FluentIcons.add_circle_24_regular,
      iconWidget: isTracked
          ? Image.asset(
              'assets/icon/shamor_zachor_with_v.png',
              width: iconSize,
              height: iconSize,
            )
          : null,
      compact: isCompact,
      onPressed: () {
        if (isTracked) {
          _markShamorZachorProgress(state.book.title);
        } else {
          _addBookToShamorZachorTracking(state.book);
        }
      },
    );
  }

  /// Add book to Shamor Zachor tracking
  Future<void> _addBookToShamorZachorTracking(Book book) async {
    if (!_isOfficialSeforimBook(book)) {
      UiSnack.showError(TextBookMessages.onlyOfficialBooksSupportedInTracking);
      return;
    }
    try {
      final dataProvider = context.read<ShamorZachorDataProvider>();

      final bookTitle = book.title;

      // 1. Get book path from library or database
      String? bookPath = book.filePath;

      if (bookPath == null) {
        final location = await BookLocator.locateBook(
          bookTitle,
          categoryId: book.categoryId,
        );
        bookPath = location?.filePath;
      }

      // If not found in file system, try to get category from database
      if (bookPath == null) {
        String categoryPath = '';
        // Try to use the category path from the book object first
        if (book.categoryPath != null && book.categoryPath!.isNotEmpty) {
          categoryPath = book.categoryPath!.replaceAll(', ', '/');
        } else {
          final dbProvider = SqliteDataProvider.instance;
          if (await dbProvider.databaseExists() && dbProvider.isInitialized) {
            try {
              final resolvedBook = await BookDatabaseResolver.resolveBook(
                title: bookTitle,
                categoryId: book.categoryId,
                fileType: book.fileType,
                filePath: book.filePath,
                preferUserBooks: BookDatabaseResolver.isLikelyUserBook(
                  isUserBook: book.isUserBook,
                  categoryPath: book.categoryPath,
                ),
              );
              if (resolvedBook != null) {
                categoryPath = await BookDatabaseResolver.buildCategoryPath(
                  resolvedBook.repository,
                  resolvedBook.book.categoryId,
                );
                categoryPath = categoryPath.replaceAll(', ', '/');
              }
            } catch (e) {
              debugPrint('Error getting category from DB: $e');
            }
          }
        }

        if (categoryPath.isNotEmpty) {
          final libraryPath =
              Settings.getValue<String>(SettingsRepository.keyLibraryPath) ??
              '.';
          bookPath =
              '$libraryPath${Platform.pathSeparator}אוצריא${Platform.pathSeparator}$categoryPath${Platform.pathSeparator}$bookTitle.txt';
          debugPrint('Book path from DB: $bookPath');
        }
      }

      if (bookPath == null) {
        UiSnack.showError(TextBookMessages.bookPathNotFound);
        return;
      }

      debugPrint('Adding book to tracking - Path: $bookPath');

      // 2. Use the actual book title as-is (don't modify it)
      // The title should match exactly what's in the DB
      String cleanBookName = bookTitle;

      // 3. Show loading indicator
      UiSnack.show(TextBookMessages.addingBookToTracking);

      // 4. Add book via provider (only needs book name)
      await dataProvider.addCustomBook(
        bookName: cleanBookName,
        bookId: book.id,
        categoryId: book.categoryId,
      );

      // 5. Success message
      UiSnack.show(TextBookMessages.bookAddedToTracking(cleanBookName));

      // 6. Update UI to reflect the change
      setState(() {});
    } catch (e, stackTrace) {
      debugPrint('Error adding book to Shamor Zachor: $e');
      debugPrint('Stack trace: $stackTrace');
      UiSnack.showError(TextBookMessages.addBookToTrackingError(e));
    }
  }

  /// פונקציות עזר לטיפול בלחיצות על כפתורים בתפריט הנפתח
  void _handlePdfButtonPress(BuildContext context, TextBookLoaded state) async {
    if (_pdfBook == null) {
      UiSnack.showError(TextBookMessages.pdfNotFoundForBook(state.book.title));
      return;
    }

    // PDF נמדד מול שורות מקור; ל-tab.index גם רוצים שורת מקור (לשמירה).
    final currentIndex = _topmostVisibleSourceLine(state);
    widget.tab.index = currentIndex;

    final index = await textToPdfPage(state.book, currentIndex);

    if (!context.mounted) return;

    openBook(
      context,
      _pdfBook!,
      index ?? 1,
      '',
      ignoreHistory: true,
      requiresStableLayout: true,
      insertAdjacent: true,
    );
  }

  /// עיגון מחדש לפריט העליון הנראה לפני שינוי רוחב התוכן: SPL שומר היסט בפיקסלים
  /// מול שורת הפתיחה, כך שבלעדי זה זרימה-מחדש ברוחב אחר מקפיצה את התצוגה.
  void _reanchorMainContentToTopmostVisible() {
    final controller = widget.tab.scrollController;
    if (!controller.isAttached) return;

    final visible = widget.tab.positionsListener.itemPositions.value.where(
      (p) => p.itemLeadingEdge < 1 && p.itemTrailingEdge > 0,
    );
    if (visible.isEmpty) return;

    ItemPosition pickByMinLeadingEdge(Iterable<ItemPosition> items) =>
        items.reduce((a, b) => a.itemLeadingEdge <= b.itemLeadingEdge ? a : b);

    final atOrBelowFold = visible.where((p) => p.itemLeadingEdge >= 0);
    final anchor = atOrBelowFold.isNotEmpty
        ? pickByMinLeadingEdge(atOrBelowFold)
        : pickByMinLeadingEdge(visible);

    // itemLeadingEdge יכול להיות שלילי כשקטע ארוך מתחיל מעל התצוגה (גלילה
    // לעומק הקטע). clamp ל-0 היה מיישר את תחילת הקטע לראש התצוגה = קפיצה.
    controller.jumpTo(
      index: anchor.index,
      alignment: anchor.itemLeadingEdge,
    );
  }

  Widget _buildBody(
    BuildContext context,
    TextBookLoaded state,
  ) {
    return AdaptiveSidePane(
      isOpen: state.showLeftPane,
      alignment: AlignmentDirectional.centerEnd,
      paneWidth: _sidebarWidth.value,
      minMainContentWidth: 520,
      onClose: () =>
          context.read<TextBookBloc>().add(const ToggleLeftPane(false)),
      paneContent: widget.enableTourTargets
          ? KeyedSubtree(
              key: textBookNavPanelTourTargetKey,
              child: _buildLeftPaneContent(state),
            )
          : _buildLeftPaneContent(state),
      mainContent: _buildHTMLViewer(state),
      isResizable: true,
      minPaneWidth: 200,
      maxPaneWidth: 600,
      onPaneWidthChanged: (nextWidth) {
        _sidebarWidth.value = nextWidth;
      },
      onPaneResizeEnd: () {
        _reanchorMainContentToTopmostVisible();
        context.read<SettingsBloc>().add(
          UpdateSidebarWidth(_sidebarWidth.value),
        );
      },
      onLayoutModeChanged: (usesPushLayout) {
        _paneUsesPushLayout = usesPushLayout;
      },
      autoHandleResponsiveVisibility: false,
      scrollbarTopMargin: 0,
    );
  }

  Widget _buildHTMLViewer(TextBookLoaded state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 5, 5),
      child: GestureDetector(
        onScaleUpdate: (details) {
          context.read<TextBookBloc>().add(
            UpdateFontSize((state.fontSize * details.scale).clamp(15, 60)),
          );
        },
        onScaleEnd: (details) {
          // שמירת גודל הגופן בסיום המחווה
          final textBookBloc = context.read<TextBookBloc>();
          final currentState = textBookBloc.state;
          if (currentState is TextBookLoaded) {
            savePerBookDisplaySettings(
              context,
              currentState,
              fontSize: currentState.fontSize,
            );
          }
        },
        child: NotificationListener<UserScrollNotification>(
          onNotification: (scrollNotification) {
            final isSidebarPinned =
                state.pinLeftPane ||
                (Settings.getValue<bool>('key-pin-sidebar') ?? false);
            final shouldAutoCloseLeftPane =
                scrollNotification.direction != ScrollDirection.idle &&
                state.showLeftPane &&
                !isSidebarPinned &&
                !_leftPaneAutoCloseQueuedByScroll;
            if (shouldAutoCloseLeftPane) {
              _leftPaneAutoCloseQueuedByScroll = true;
              Future.microtask(() {
                if (!mounted || !context.mounted) {
                  _leftPaneAutoCloseQueuedByScroll = false;
                  return;
                }
                final currentState = context.read<TextBookBloc>().state;
                if (currentState is! TextBookLoaded ||
                    !currentState.showLeftPane) {
                  _leftPaneAutoCloseQueuedByScroll = false;
                  return;
                }
                context.read<TextBookBloc>().add(const ToggleLeftPane(false));
              });
            }
            return false;
          },
          child: CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              LogicalKeySet(
                LogicalKeyboardKey.control,
                LogicalKeyboardKey.keyF,
              ): _openSearchFromToolbar,
              // Mac: Cmd+F
              LogicalKeySet(
                LogicalKeyboardKey.meta,
                LogicalKeyboardKey.keyF,
              ): _openSearchFromToolbar,
            },
            child: TextBookScaffold(
              content: state.content,
              openBookCallback: widget.openBookCallback,
              openLeftPaneTab: _openLeftPaneTab,
              onSelectedTextChanged: _onSelectedTextChanged,
              searchTextController: TextEditingValue(text: state.searchText),
              tab: widget.tab,
              initialSidebarTabIndex: _sidebarTabIndex,
              onSidebarTabChanged: (index) {
                if (_sidebarTabIndex != index) {
                  setState(() {
                    _sidebarTabIndex = index;
                  });
                }
              },
              pageShapeKey: _pageShapeKey,
              pageShapePrintBoundaryKey: _pageShapePrintBoundaryKey,
              pageShapeSidebarTabNotifier: _pageShapeSidebarTabNotifier,
              pageShapeOpenSettingsNotifier: _pageShapeOpenSettingsNotifier,
              openSearch: _openSearchWithText,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeftPaneContent(TextBookLoaded state) {
    // ברגע שהפאנל הצדדי נפתח (false→true) מעבירים פוקוס לשדה החיפוש של
    // הלשונית הפעילה. ההחלטה מבוצעת בפונקציה טהורה (resolveLeftPaneSearchFocus)
    // שמבטיחה שלא נבקש פוקוס בכל rebuild - הגנה מפני רגרסיה לבאג הגלילה
    // האינסופית (commit 41a5816fc).
    final focusDecision = resolveLeftPaneSearchFocus(
      showLeftPane: state.showLeftPane,
      wasShown: _wasLeftPaneShown,
    );
    _wasLeftPaneShown = focusDecision.wasShownNext;
    if (focusDecision.shouldFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusActiveTabSearchField();
      });
    }
    return Column(
      children: [
        SidebarTabHeader(
          controller: tabController,
          tabs: [
            (
              icon: FluentIcons.navigation_24_regular,
              iconFilled: FluentIcons.navigation_24_filled,
              label: 'ניווט',
            ),
            if (_hasAltTitles)
              (
                icon: FluentIcons.list_24_regular,
                iconFilled: FluentIcons.list_24_filled,
                label: 'כותרות',
              ),
            (
              icon: FluentIcons.search_24_regular,
              iconFilled: FluentIcons.search_24_filled,
              label: 'חיפוש',
            ),
          ],
          isPinned: state.pinLeftPane,
          onTogglePin: MediaQuery.of(context).size.width >= 600
              ? () => context.read<TextBookBloc>().add(
                  TogglePinLeftPane(!state.pinLeftPane),
                )
              : null,
        ),
        Expanded(
          child: TabBarView(
            controller: tabController,
            children: [
              _buildTocViewer(context, state),
              if (_hasAltTitles)
                AltTocSidebarView(
                  book: widget.tab.book,
                  focusNode: altTitlesSearchFocusNode,
                  closeLeftPaneCallback: () => context.read<TextBookBloc>().add(
                    const ToggleLeftPane(false),
                  ),
                  scrollController: state.scrollController,
                ),
              Builder(
                builder: (context) {
                  void openSearch() {
                    context.read<TextBookBloc>().add(
                      const ToggleLeftPane(true),
                    );
                    tabController.index = _hasAltTitles ? 2 : 1;
                    textSearchFocusNode.requestFocus();
                  }

                  return CallbackShortcuts(
                    bindings: <ShortcutActivator, VoidCallback>{
                      LogicalKeySet(
                        LogicalKeyboardKey.control,
                        LogicalKeyboardKey.keyF,
                      ): openSearch,
                      // Mac: Cmd+F
                      LogicalKeySet(
                        LogicalKeyboardKey.meta,
                        LogicalKeyboardKey.keyF,
                      ): openSearch,
                    },
                    child: _buildSearchView(context, state),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchView(BuildContext context, TextBookLoaded state) {
    final repository = context.read<TextBookBloc>().repository;
    return TextBookSearchView(
      focusNode: textSearchFocusNode,
      contentLoader: () async =>
          splitContentLines(await repository.getBookContent(state.book)),
      scrollControler: state.scrollController,
      // הוא מעביר את טקסט החיפוש מה-state הנוכחי אל תוך רכיב החיפוש
      initialQuery: state.searchText,
      initialSearchOptions: state.searchOptions,
      initialAlternativeWords: state.alternativeWords,
      initialSpacingValues: state.spacingValues,
      initialSearchMode: state.searchMode,
      initialSearchDistance: state.searchDistance,
      closeLeftPaneCallback: () =>
          context.read<TextBookBloc>().add(const ToggleLeftPane(false)),
    );
  }

  Widget _buildTocViewer(BuildContext context, TextBookLoaded state) {
    return TocViewer(
      scrollController: state.scrollController,
      focusNode: navigationSearchFocusNode,
      closeLeftPaneCallback: () =>
          context.read<TextBookBloc>().add(const ToggleLeftPane(false)),
    );
  }
}

/// מחליטה אם לבקש פוקוס לשדה החיפוש של הפאנל הצדדי, ומחזירה גם את המצב
/// הבא של "הפאנל הוצג".
///
/// מבקשים פוקוס אך ורק במעבר של הפאנל מסגור לפתוח. בכל rebuild שבו הפאנל
/// כבר פתוח (למשל בזמן גלילה, שבה ה-bloc פולט states חדשים שוב ושוב) —
/// [shouldFocus] יהיה false. זו ההגנה מפני רגרסיה לבאג "הגלילה האינסופית"
/// (commit 41a5816fc): קריאת requestFocus חוזרת בכל build חטפה פוקוס מתוכן
/// הספר ויצרה לולאת גלילה עד סוף המסמך.
({bool shouldFocus, bool wasShownNext}) resolveLeftPaneSearchFocus({
  required bool showLeftPane,
  required bool wasShown,
}) {
  if (!showLeftPane) return (shouldFocus: false, wasShownNext: false);
  if (wasShown) return (shouldFocus: false, wasShownNext: true);
  return (shouldFocus: true, wasShownNext: true);
}

int _topmostVisibleIndex(TextBookLoaded state) =>
    topmostVisibleIndex(state.positionsListener.itemPositions.value);

int _bottommostVisibleIndex(TextBookLoaded state) =>
    bottommostVisibleIndex(state.positionsListener.itemPositions.value);

// ה-helpers הבאים הם wrapper-ים דקים לפונקציות הטהורות ב-visible_index.dart
// (`resolveTopmostSourceLine`/`resolveBottommostSourceLine`/`resolveItemIndexForSourceLine`).
// הלוגיקה נבדקת ב-test/text_book/utils/visible_index_test.dart.

int _topmostVisibleSourceLine(TextBookLoaded state) => resolveTopmostSourceLine(
  positions: state.positionsListener.itemPositions.value,
  continuousReadingMode: state.continuousReadingMode,
  readingSegments: state.readingSegments,
);

int _bottommostVisibleSourceLine(TextBookLoaded state) =>
    resolveBottommostSourceLine(
      positions: state.positionsListener.itemPositions.value,
      continuousReadingMode: state.continuousReadingMode,
      readingSegments: state.readingSegments,
    );

int _itemIndexForSourceLine(TextBookLoaded state, int lineIndex) =>
    resolveItemIndexForSourceLine(
      lineIndex: lineIndex,
      readingSegments: state.readingSegments,
    );

// [EDITING DISABLED]
// // החלף את כל המחלקה הזו בקובץ text_book_screen.TXT
//
// Widget _buildFullFileEditorButton(BuildContext context, TextBookLoaded state) {
//   final shortcut =
//       Settings.getValue<String>('key-shortcut-edit-section') ?? 'ctrl+e';
//   return IconButton(
//     onPressed: () => _handleFullFileEditorPress(context, state),
//     icon: const Icon(FluentIcons.document_edit_24_regular),
//     tooltip: 'ערוך את הספר (${shortcut.toUpperCase()})',
//   );
// }
//
// void _handleTextEditorPress(BuildContext context, TextBookLoaded state) {
//   final positions = state.positionsListener.itemPositions.value;
//   if (positions.isEmpty) return;
//
//   final currentIndex = positions.first.index;
//   context.read<TextBookBloc>().add(OpenEditor(index: currentIndex));
// }
//
// void _handleFullFileEditorPress(BuildContext context, TextBookLoaded state) {
//   context.read<TextBookBloc>().add(OpenFullFileEditor());
// }

bool _handleGlobalKeyEvent(
  KeyEvent event,
  BuildContext context,
  TextBookLoaded state,
  TextBookTab tab, {
  required VoidCallback openSearchFromToolbar,
  required VoidCallback openNotesForCurrentView,
  String? selectedTextForNote,
  int? selectedLineForNote,
  int? selectedColumnForNote,
}) {
  // קריאת קיצורים מההגדרות
  // [EDITING DISABLED]
  // final editSectionShortcut =
  //     Settings.getValue<String>('key-shortcut-edit-section') ?? 'ctrl+e';
  final searchInBookShortcut =
      ShortcutValidator.getShortcutValue(
        ShortcutValidator.currentWindowSearchKey,
      ) ??
      'ctrl+f';
  final printShortcut =
      Settings.getValue<String>('key-shortcut-print') ?? 'ctrl+p';
  final addBookmarkShortcut =
      Settings.getValue<String>('key-shortcut-add-bookmark') ?? 'ctrl+b';
  final addNoteShortcut =
      Settings.getValue<String>('key-shortcut-add-note') ?? 'ctrl+n';
  final togglePdfShortcut =
      Settings.getValue<String>('key-shortcut-toggle-pdf-view') ??
      ShortcutValidator.defaultShortcuts['key-shortcut-toggle-pdf-view'] ??
      'ctrl+shift+p';
  final copyBookLinkShortcut =
      ShortcutValidator.getShortcutValue(ShortcutValidator.copyBookLinkKey) ??
      '';
  final copySectionLinkShortcut =
      ShortcutValidator.getShortcutValue(
        ShortcutValidator.copySectionLinkKey,
      ) ??
      '';
  final copySectionMarkLinkShortcut =
      ShortcutValidator.getShortcutValue(
        ShortcutValidator.copySectionMarkLinkKey,
      ) ??
      '';
  final copyTextMarkLinkShortcut =
      ShortcutValidator.getShortcutValue(
        ShortcutValidator.copyTextMarkLinkKey,
      ) ??
      '';

  // [EDITING DISABLED]
  // // עריכת קטע
  // if (ShortcutHelper.matchesShortcut(event, editSectionShortcut)) {
  //   if (!state.isEditorOpen) {
  //     if (HardwareKeyboard.instance.isShiftPressed) {
  //       _handleFullFileEditorPress(context, state);
  //     } else {
  //       _handleTextEditorPress(context, state);
  //     }
  //     return true;
  //   }
  // }

  // חיפוש בספר
  if (ShortcutHelper.matchesShortcut(event, searchInBookShortcut)) {
    openSearchFromToolbar();
    return true;
  }

  // הדפסה
  if (ShortcutHelper.matchesShortcut(event, printShortcut)) {
    context.read<TourCubit>().recordInteraction(
      TourInteraction(type: TourInteractionType.printUsed),
    );
    final settingsState = context.read<SettingsBloc>().state;
    // תוכן מלא מה-repository — state.content יכול להיות חלקי (חימום/שחרור).
    // חובה לקרוא כאן: בתוך ה-builder ה-context הוא של הדיאלוג וחסר לו provider ל-TextBookBloc.
    final contentData = context.read<TextBookBloc>().repository.getBookContent(
      state.book,
    );
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PrintingScreen(
        data: contentData,
        bookId: state.book.title,
        book: state.book,
        links: state.links,
        activeCommentators: state.activeCommentators,
        startLine: state.visibleIndices.first,
        removeNikud: state.removeNikud,
        removeTaamim: !settingsState.showTeamim,
        tableOfContents: state.tableOfContents,
      ),
    );
    return true;
  }

  // הוספת סימניה
  if (ShortcutHelper.matchesShortcut(event, addBookmarkShortcut)) {
    _addBookmarkFromKeyboard(context, state);
    return true;
  }

  // הוספת הערה
  if (ShortcutHelper.matchesShortcut(event, addNoteShortcut)) {
    // בצורת הדף, כשהבחירה במפרש, חלונית המפרש כבר פתחה הערה תחת ספר המפרש.
    // האירוע ממשיך להתבעבע לכאן, ולכן נמנעים מפתיחת הערה כפולה על גוף הספר.
    if (SimpleTextViewer.commentaryNoteHandledRecently) {
      return true;
    }
    _addNoteFromKeyboard(
      context,
      state,
      openNotesForCurrentView: openNotesForCurrentView,
      selectedText: selectedTextForNote,
      selectedLineIndex: selectedLineForNote,
      selectionColumn: selectedColumnForNote,
    );
    return true;
  }

  // מעבר ל-PDF
  if (ShortcutHelper.matchesShortcut(event, togglePdfShortcut)) {
    _togglePdfView(context, state, tab);
    return true;
  }

  // העתקת קישורים — קיצורים אופציונליים. האינדקס נלקח מהשורה המסומנת, ואם אין
  // בחירה — מהמקטע הראשון הנראה (משחזר את מה שתפריט ההקשר היה מייצר).
  if (copyBookLinkShortcut.isNotEmpty ||
      copySectionLinkShortcut.isNotEmpty ||
      copySectionMarkLinkShortcut.isNotEmpty ||
      copyTextMarkLinkShortcut.isNotEmpty) {
    final bookId = state.book.id;
    final index =
        selectedLineForNote ??
        (state.visibleIndices.isNotEmpty ? state.visibleIndices.first : 0);

    if (ShortcutHelper.matchesShortcut(event, copyBookLinkShortcut)) {
      if (bookId == null) {
        UiSnack.showError(TextBookMessages.directLinkUnavailable);
      } else {
        copyLinkToClipboard(buildBookLink(bookId));
      }
      return true;
    }
    if (ShortcutHelper.matchesShortcut(event, copySectionLinkShortcut)) {
      if (bookId == null) {
        UiSnack.showError(TextBookMessages.directLinkUnavailable);
      } else {
        copyLinkToClipboard(buildSectionLink(bookId, index));
      }
      return true;
    }
    if (ShortcutHelper.matchesShortcut(event, copySectionMarkLinkShortcut)) {
      if (bookId == null) {
        UiSnack.showError(TextBookMessages.directLinkUnavailable);
      } else {
        copyLinkToClipboard(buildSectionMarkLink(bookId, index));
      }
      return true;
    }
    if (ShortcutHelper.matchesShortcut(event, copyTextMarkLinkShortcut)) {
      final link = bookId == null
          ? null
          : buildTextMarkLink(bookId, index, selectedTextForNote ?? '');
      if (bookId == null) {
        UiSnack.showError(TextBookMessages.directLinkUnavailable);
      } else if (link == null) {
        UiSnack.showError(TextBookMessages.selectTextForMarkLink);
      } else {
        copyLinkToClipboard(link);
      }
      return true;
    }
  }

  // קיצורים קבועים (לא ניתנים להתאמה אישית).
  // ב-Mac מקבלים גם את Cmd (Meta) כי זו המוסכמה בפלטפורמה.
  final isCtrlOrCmd =
      HardwareKeyboard.instance.isControlPressed ||
      (Platform.isMacOS && HardwareKeyboard.instance.isMetaPressed);

  if (event is KeyDownEvent && isCtrlOrCmd) {
    switch (event.logicalKey) {
      // הגדל את גודל הטקסט (Ctrl++ או Ctrl+=)
      case LogicalKeyboardKey.equal:
      case LogicalKeyboardKey.add:
        final newSize = min(50.0, state.fontSize + 3);
        context.read<TextBookBloc>().add(UpdateFontSize(newSize));
        savePerBookDisplaySettings(context, state, fontSize: newSize);
        return true;

      // הקטן את גודל הטקסט (Ctrl+-)
      case LogicalKeyboardKey.minus:
        final newSize = max(15.0, state.fontSize - 3);
        context.read<TextBookBloc>().add(UpdateFontSize(newSize));
        savePerBookDisplaySettings(context, state, fontSize: newSize);
        return true;

      // איפוס גודל טקסט (Ctrl+0)
      case LogicalKeyboardKey.digit0:
        context.read<TextBookBloc>().add(const UpdateFontSize(25.0));
        savePerBookDisplaySettings(context, state, fontSize: 25.0);
        return true;
    }
  }

  // ניווט עם Ctrl+Home ו-Ctrl+End
  if (event is KeyDownEvent && isCtrlOrCmd) {
    switch (event.logicalKey) {
      // Ctrl+Home - תחילת הספר
      case LogicalKeyboardKey.home:
        state.scrollController.scrollTo(
          index: 0,
          duration: const Duration(milliseconds: 300),
        );
        return true;

      // Ctrl+End - סוף הספר
      case LogicalKeyboardKey.end:
        state.scrollController.scrollTo(
          index: state.content.length - 1,
          duration: const Duration(milliseconds: 300),
        );
        return true;
    }
  }

  // מקשי פונקציה ללא Ctrl/Cmd
  if (event is KeyDownEvent && !isCtrlOrCmd) {
    switch (event.logicalKey) {
      // F11 - מסך מלא
      case LogicalKeyboardKey.f11:
        if (!Platform.isAndroid && !Platform.isIOS) {
          final settingsBloc = context.read<SettingsBloc>();
          final newFullscreenState = !settingsBloc.state.isFullscreen;
          FullscreenHelper.toggleFullscreen(context, newFullscreenState);
          return true;
        }
        break;

      // ESC - יציאה ממסך מלא
      case LogicalKeyboardKey.escape:
        if (!Platform.isAndroid && !Platform.isIOS) {
          final settingsBloc = context.read<SettingsBloc>();
          if (settingsBloc.state.isFullscreen) {
            FullscreenHelper.toggleFullscreen(context, false);
            return true;
          }
        }
        break;
    }
  }

  return false;
}

/// Helper function to add bookmark from keyboard shortcut
void _addBookmarkFromKeyboard(
  BuildContext context,
  TextBookLoaded state,
) async {
  final index = _topmostVisibleSourceLine(state);
  await addTextSectionBookmark(context, state, index);
}

/// Helper function to add note from keyboard shortcut
Future<void> _addNoteFromKeyboard(
  BuildContext context,
  TextBookLoaded state, {
  required VoidCallback openNotesForCurrentView,
  String? selectedText,
  int? selectedLineIndex,
  int? selectionColumn,
}) async {
  // אם יש טקסט מסומן — מתנהגים בדיוק כמו תפריט הקליק-ימני: ההערה חלה על
  // השורה שממנה הודגש הטקסט, והטקסט המסומן עצמו משמש ככותרת ההערה.
  // אחרת — ההערה חלה על השורה הנבחרת/הראשונה הנראית, וכותרתה היא טקסט הזיהוי.
  final trimmedSelection = selectedText?.trim();
  final hasSelection = trimmedSelection != null && trimmedSelection.isNotEmpty;

  final currentIndex =
      (hasSelection ? selectedLineIndex : null) ??
      state.selectedIndex ??
      (state.visibleIndices.isNotEmpty ? state.visibleIndices.first : 0);

  // קבלת הטקסט המזהה של השורה (כמו שיוצג ככותרת ההערה), או הטקסט המסומן
  final referenceText = hasSelection
      ? removeHebrewDiacritics(trimmedSelection)
      : extractDisplayTextFromLines(
          state.content,
          currentIndex + 1,
          excludeBookTitle: state.book.title,
        );

  // טען טיוטה אם קיימת
  final draftService = PersonalNoteDraftService();
  final draft = await draftService.loadDraft(
    bookId: state.book.title,
    lineNumber: currentIndex + 1,
  );

  if (!context.mounted) return;

  // שלח event לפתיחת מצב יצירה בסיידבר
  context.read<PersonalNotesBloc>().add(
    StartCreatingPersonalNote(
      bookId: state.book.title,
      lineNumber: currentIndex + 1,
      referenceText: referenceText,
      selectedText: hasSelection ? trimmedSelection : null,
      selectionColumn: hasSelection ? selectionColumn : null,
      initialContent: draft?.content ?? '',
      initialFormat: draft?.contentFormat ?? PersonalNoteContentFormat.plain,
    ),
  );

  openNotesForCurrentView();
}

// [EDITING DISABLED]
// void _openEditorDialog(BuildContext context, TextBookLoaded state) async {
//   if (state.editorIndex == null || state.editorSectionId == null) return;
//
//   final settings = EditorSettingsHelper.getSettings();
//
//   // Reload the content from file system to ensure fresh data
//   String freshContent = '';
//   try {
//     // Try to reload content from file system
//     final dataProvider = FileSystemData.instance;
//     freshContent = await dataProvider.getBookText(
//       state.book.title,
//       categoryId: state.book.categoryId,
//       fileType: state.book.fileType,
//     );
//   } catch (e) {
//     debugPrint('Failed to load fresh content: $e');
//     // Fall back to cached content
//     freshContent = state.editorText ?? '';
//   }
//
//   if (!context.mounted) return;
//
//   await showDialog(
//     context: context,
//     barrierDismissible: false,
//     builder: (dialogContext) => BlocProvider.value(
//       value: context.read<TextBookBloc>(),
//       child: TextSectionEditorDialog(
//         bookId: state.book.title,
//         category: state.book.categoryPath,
//         categoryId: state.book.categoryId,
//         fileType: state.book.fileType,
//         sectionIndex: state.editorIndex!,
//         sectionId: state.editorSectionId!,
//         initialContent:
//             freshContent.isNotEmpty ? freshContent : state.editorText ?? '',
//         hasLinksFile: state.hasLinksFile,
//         hasDraft: state.hasDraft,
//         settings: settings,
//       ),
//     ),
//   );
//
//   if (!context.mounted) return;
//
//   // Close editor when dialog is dismissed
//   context.read<TextBookBloc>().add(const CloseEditor());
// }

void _togglePdfView(
  BuildContext context,
  TextBookLoaded state,
  TextBookTab tab,
) async {
  final currentIndex = _topmostVisibleSourceLine(state);
  tab.index = currentIndex;

  final library = await DataRepository.instance.library;
  if (!context.mounted) return;

  final book = library.getCompanionBook(state.book, PdfBook);
  if (book == null) {
    UiSnack.showError(TextBookMessages.pdfNotFoundForBook(state.book.title));
    return;
  }

  final index = await textToPdfPage(
    state.book,
    currentIndex,
  );

  if (!context.mounted) return;

  openBook(
    context,
    book,
    index ?? 1,
    '',
    ignoreHistory: true,
    requiresStableLayout: true,
    insertAdjacent: true,
  );
}
