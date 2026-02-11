import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:otzaria/core/scaffold_messenger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/focus/focus_repository.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_event.dart' hide UpdateFontSize;
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/printing/printing_screen.dart';
import 'package:otzaria/text_book/view/text_book_scaffold.dart';
import 'package:otzaria/text_book/view/text_book_search_screen.dart';
import 'package:otzaria/text_book/view/toc_navigator_screen.dart';
import 'package:otzaria/text_book/view/alt_toc_sidebar_view.dart';
import 'package:otzaria/utils/open_book.dart';
import 'package:otzaria/data/book_locator.dart';
import 'package:otzaria/utils/page_converter.dart';
import 'package:otzaria/utils/ref_helper.dart';
import 'package:otzaria/text_book/editing/widgets/text_section_editor_dialog.dart';
import 'package:otzaria/text_book/view/book_source_dialog.dart';
import 'package:otzaria/text_book/editing/helpers/editor_settings_helper.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/utils/shortcut_helper.dart';
import 'package:otzaria/utils/shortcut_validator.dart';
import 'package:otzaria/utils/fullscreen_helper.dart';

import 'package:otzaria/widgets/responsive_action_bar.dart';
import 'package:otzaria/widgets/resizable_drag_handle.dart';
import 'package:otzaria/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/shamor_zachor/models/book_model.dart';
import 'package:otzaria/settings/per_book_settings.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_settings_dialog.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/text_book/view/page_shape/utils/default_commentators.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// קבועים למצבי תצוגה (למניעת magic strings)
const String _viewModeSplit = 'split';
const String _viewModeBelow = 'below';
const String _viewModePage = 'page';

class TextBookViewerBloc extends StatefulWidget {
  final void Function(OpenedTab) openBookCallback;
  final TextBookTab tab;
  final bool isInCombinedView;

  const TextBookViewerBloc({
    super.key,
    required this.openBookCallback,
    required this.tab,
    this.isInCombinedView = false,
  });

  @override
  State<TextBookViewerBloc> createState() => _TextBookViewerBlocState();
}

class _TextBookViewerBlocState extends State<TextBookViewerBloc>
    with TickerProviderStateMixin {
  final FocusNode textSearchFocusNode = FocusNode();
  final FocusNode navigationSearchFocusNode = FocusNode();
  final FocusNode _bookContentFocusNode = FocusNode(); // FocusNode לתוכן הספר
  late TabController tabController;
  late final ValueNotifier<double> _sidebarWidth;
  late final StreamSubscription<SettingsState> _settingsSub;
  int? _sidebarTabIndex; // אינדקס הכרטיסייה בסרגל הצדי
  bool _isInitialFocusDone = false;
  FocusRepository? _focusRepository; // שמירת הפניה לשימוש ב-dispose
  final GlobalKey _viewModeMenuKey = GlobalKey(); // מפתח לתפריט בחירת התצוגה
  String? _selectedTextForSearch;

  // Key עבור PageShapeScreen - שינוי המפתח יגרום לבנייה מחדש
  Key _pageShapeKey = UniqueKey();

  // RepaintBoundary key עבור הדפסה של "צורת הדף" כפי שמוצג
  final GlobalKey _pageShapePrintBoundaryKey = GlobalKey();

  // Cache לרשימת אינדקסי TOC ממוינת - למניעת חישוב מחדש בכל לחיצה
  List<int>? _cachedTocIndices;
  String? _cachedTocBookTitle;
  List<TocEntry>? _cachedToc;

  /// Check if book is already being tracked in Shamor Zachor
  bool _isBookTrackedInShamorZachor(String bookTitle) {
    try {
      final dataProvider = context.read<ShamorZachorDataProvider>();
      if (!dataProvider.hasData) {
        return false;
      }

      // Extract clean book name
      String cleanBookName = bookTitle;
      if (bookTitle.contains(' - ')) {
        final parts = bookTitle.split(' - ');
        cleanBookName = parts.last.trim();
      }

      // Search for the book

      // Legacy: Search for the book
      final searchResults = dataProvider.searchBooks(cleanBookName);

      // If found in existing categories, it's tracked
      return searchResults.any((result) =>
          result.bookName == cleanBookName ||
          result.bookName.contains(cleanBookName) ||
          cleanBookName.contains(result.bookName));
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
        UiSnack.showError('נתוני שמור וזכור לא נטענו');
        return;
      }

      // בדיקה אם יש ID לספר
      if (state.book.id == null) {
        UiSnack.showError('הספר לא נמצא במסד הנתונים');
        return;
      }

      final bookId = state.book.id!;

      // חיפוש הספר לפי ID ב-shamor zachor
      final result = dataProvider.getBookById(bookId);

      if (result == null) {
        UiSnack.showError('הספר לא נמצא בשמור וזכור');
        return;
      }

      final (bookDetails, bookName, topLevelCategoryKey) = result;
      debugPrint('Book found: $bookName (ID: $bookId)');

      // קבלת הפרק הנוכחי
      final currentIndex =
          state.positionsListener.itemPositions.value.isNotEmpty
              ? state.positionsListener.itemPositions.value.first.index
              : 0;

      // קבלת הכותרת הנוכחית
      String currentRef =
          await refFromIndex(currentIndex, state.book.tableOfContents);

      // אם הכותרת היא רק שם הספר (H1), נחפש את H2 הבאה
      if (currentRef == state.book.title || currentRef.split(',').length == 1) {
        debugPrint('Current ref is H1 (book title), looking for next H2...');
        final toc = await state.book.tableOfContents;

        // חיפוש הכותרת הבאה שגדולה מהאינדקס הנוכחי
        for (final entry in toc) {
          if (entry.index > currentIndex) {
            currentRef = entry.text;
            debugPrint('Found next H2: $currentRef');
            break;
          }
          // חיפוש גם בכותרות המשנה
          for (final child in entry.children) {
            if (child.index > currentIndex) {
              currentRef = '${entry.text}, ${child.text}';
              debugPrint('Found next H2 child: $currentRef');
              break;
            }
          }
          if (currentRef !=
              await refFromIndex(currentIndex, state.book.tableOfContents)) {
            break;
          }
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
            '  [$i] displayLabel: "${item.displayLabel}", partName: "${item.partName}", hierarchyPath: ${item.hierarchyPath}');
      }
      if (learnableItems.length > 10) {
        debugPrint('  ... and ${learnableItems.length - 10} more items');
      }

      try {
        // חיפוש לפי displayLabel או partName שמכיל את שם הכותרת
        targetItem = learnableItems.firstWhere(
          (item) {
            // בדיקה לפי displayLabel
            if (item.displayLabel != null &&
                item.displayLabel!.contains(searchTitle)) {
              return true;
            }
            // בדיקה לפי partName
            if (item.partName.contains(searchTitle)) {
              return true;
            }
            // בדיקה לפי hierarchyPath
            if (item.hierarchyPath.any((path) => path.contains(searchTitle))) {
              return true;
            }
            return false;
          },
        );
      } catch (e) {
        // אם לא מצאנו בחיפוש מדויק, ננסה חיפוש חלקי
        try {
          targetItem = learnableItems.firstWhere(
            (item) {
              final itemTitle = item.displayLabel ?? item.partName;
              final searchWords = searchTitle.split(' ');
              return searchWords
                  .any((word) => word.length > 2 && itemTitle.contains(word));
            },
          );
        } catch (e2) {
          targetItem = null;
        }
      }

      if (targetItem == null) {
        throw Exception('$searchTitle לא נמצא בשמור וזכור');
      }

      debugPrint(
          'Found target item: displayLabel="${targetItem.displayLabel}", partName="${targetItem.partName}"');

      debugPrint(
          'Target item: ${targetItem.pageNumber}${targetItem.amudKey}, absoluteIndex: ${targetItem.absoluteIndex}');

      // בדיקת מצב העמודות עבור הפרק הספציפי - משתמשים ב-ID!
      final itemProgress = progressProvider.getProgressForItemById(
          bookId, targetItem.absoluteIndex);

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
        UiSnack.show('אין מקום פנוי ב$chapterName, למדת הרבה!');
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
      UiSnack.show('$displayName סומן כ$columnName בהצלחה!');
    } catch (e) {
      debugPrint('Error in _markShamorZachorProgress: $e');
      UiSnack.showError('שגיאה בסימון: ${e.toString()}');
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

  Future<void> _handlePrintPress(TextBookLoaded state) async {
    if (state.showPageShapeView) {
      final png = await _capturePageShapeViewPng();
      if (!mounted) return;

      final settingsState = context.read<SettingsBloc>().state;

      if (png == null || png.isEmpty) {
        UiSnack.showError('לא ניתן לצלם את תצוגת "צורת הדף" לצורך הדפסה');
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
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
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PrintingScreen(
          data: Future.value(state.content.join('\n')),
          bookId: state.book.title,
          links: state.links,
          activeCommentators: state.activeCommentators,
          startLine: state.visibleIndices.first,
          removeNikud: state.removeNikud,
          removeTaamim: !context.read<SettingsBloc>().state.showTeamim,
          tableOfContents: state.tableOfContents,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    // רישום ה-FocusNode ב-FocusRepository
    _focusRepository = context.read<FocusRepository>();
    _focusRepository!.registerBookContentFocusNode(_bookContentFocusNode);

    // טעינת הגדרות פר-ספר
    _loadPerBookSettings();

    final pendingSidebarTab =
        Settings.getValue<int>('key-sidebar-tab-index-pending');
    if (pendingSidebarTab != null && pendingSidebarTab >= 0) {
      _sidebarTabIndex = pendingSidebarTab;
    }

    // וודא שהמיקום הנוכחי נשמר בטאב

    // אם יש טקסט חיפוש (searchText), נתחיל בלשונית 'חיפוש' (שנמצאת במקום ה-2)
    // אחרת, נתחיל בלשונית 'ניווט' (שנמצאת במקום ה-0)
    // הערה: נעדכן את זה שוב אחרי הבדיקה של כותרות
    final int initialIndex = widget.tab.searchText.isNotEmpty ? 2 : 0;

    // יוצרים את בקר הלשוניות עם האינדקס ההתחלתי שקבענו
    tabController = TabController(
      length: 3, // ברירת מחדל, יעודכן ב-_checkAltTitles
      vsync: this,
      initialIndex: initialIndex,
    );

    // בדיקה האם יש כותרות חלופיות
    _checkAltTitles();

    _sidebarWidth = ValueNotifier<double>(
        Settings.getValue<double>('key-sidebar-width', defaultValue: 300)!);

    // שמירת הגדרות נוכחיות כדי לזהות שינויים
    double previousFontSize = context.read<SettingsBloc>().state.fontSize;
    String previousFontFamily = context.read<SettingsBloc>().state.fontFamily;
    bool previousRemoveNikud =
        context.read<SettingsBloc>().state.defaultRemoveNikud;

    _settingsSub = context.read<SettingsBloc>().stream.listen((state) {
      _sidebarWidth.value = state.sidebarWidth;

      // אם גודל הגופן השתנה, עדכן אותו מיידית
      if (state.fontSize != previousFontSize) {
        previousFontSize = state.fontSize;

        if (!mounted) return;

        final currentState = context.read<TextBookBloc>().state;
        if (currentState is TextBookLoaded) {
          context.read<TextBookBloc>().add(UpdateFontSize(state.fontSize));
        }
      }

      // אם משפחת הגופן או הסרת ניקוד השתנו, טען מחדש את התוכן
      if (state.fontFamily != previousFontFamily ||
          state.defaultRemoveNikud != previousRemoveNikud) {
        previousFontFamily = state.fontFamily;
        previousRemoveNikud = state.defaultRemoveNikud;

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
                ),
              );
        }
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
        });
      }
    } catch (e) {
      debugPrint('Error checking alt titles: $e');
    }
  }

  Future<void> _loadPerBookSettings() async {
    final settingsBloc = context.read<SettingsBloc>();
    debugPrint(
        '🔧 _loadPerBookSettings: enablePerBookSettings = ${settingsBloc.state.enablePerBookSettings}');

    if (!settingsBloc.state.enablePerBookSettings) {
      debugPrint('🔧 Per-book settings disabled, skipping load');
      return;
    }

    final settings = await TextBookPerBookSettings.load(widget.tab.book.title);
    debugPrint('🔧 Loaded settings for "${widget.tab.book.title}": $settings');

    if (settings == null) {
      debugPrint('🔧 No saved settings found for this book');
      return;
    }

    if (!mounted) return;

    final textBookBloc = context.read<TextBookBloc>();

    // המתן עד שה-TextBookBloc יהיה במצב TextBookLoaded
    await for (final state in textBookBloc.stream) {
      if (state is TextBookLoaded) {
        debugPrint('🔧 TextBookLoaded state reached, applying settings...');

        // החלת ההגדרות
        if (settings.fontSize != null) {
          debugPrint('🔧 Applying fontSize: ${settings.fontSize}');
          textBookBloc.add(UpdateFontSize(settings.fontSize!));
        }
        if (settings.commentatorsBelow != null) {
          debugPrint(
              '🔧 Applying commentatorsBelow: ${settings.commentatorsBelow}');
          textBookBloc.add(ToggleSplitView(!settings.commentatorsBelow!));
        }
        if (settings.removeNikud != null) {
          debugPrint('🔧 Applying removeNikud: ${settings.removeNikud}');
          textBookBloc.add(ToggleNikud(settings.removeNikud!));
        }
        break;
      }
    }
  }

  /// איפוס הגדרות פר-ספר
  Future<void> _resetPerBookSettings() async {
    await TextBookPerBookSettings.delete(widget.tab.book.title);

    // טעינה מחדש של ההגדרות הכלליות
    if (!mounted) return;
    final settingsBloc = context.read<SettingsBloc>();
    final textBookBloc = context.read<TextBookBloc>();

    textBookBloc.add(LoadContent(
      fontSize: settingsBloc.state.fontSize,
      // בתצוגה משולבת, מפרשים תמיד מתחת
      showSplitView: widget.isInCombinedView
          ? false
          : (Settings.getValue<bool>('key-splited-view') ?? false),
      removeNikud: settingsBloc.state.defaultRemoveNikud,
      preserveState: true,
      // בתצוגה משולבת, חלונית הצד תמיד סגורה
      forceCloseLeftPane: widget.isInCombinedView,
    ));

    if (mounted) {
      UiSnack.show('ההגדרות הפר-ספריות אופסו בהצלחה');
    }
  }

  bool _hasAltTitles = true; // נניח שיש בהתחלה, נעדכן אחרי בדיקה

  @override
  void dispose() {
    // ביטול רישום ה-FocusNode מ-FocusRepository (שימוש בהפניה שנשמרה)
    _focusRepository?.unregisterBookContentFocusNode(_bookContentFocusNode);

    tabController.dispose();
    textSearchFocusNode.dispose();
    navigationSearchFocusNode.dispose();
    _bookContentFocusNode.dispose();
    _sidebarWidth.dispose();
    _settingsSub.cancel();
    super.dispose();
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

  void _onSelectedTextChanged(String? selectedText) {
    _selectedTextForSearch = selectedText;
  }

  void _openSearchFromToolbar() {
    _openLeftPaneTab(1, searchText: _selectedTextForSearch);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        return BlocConsumer<TabsBloc, TabsState>(
          listenWhen: (previous, current) =>
              previous.currentTabIndex != current.currentTabIndex,
          listener: (context, tabsState) {
            // בקשת focus כשהטאב הנוכחי הוא הטאב של הספר הזה
            final currentTab = tabsState.tabs.isNotEmpty &&
                    tabsState.currentTabIndex < tabsState.tabs.length
                ? tabsState.tabs[tabsState.currentTabIndex]
                : null;
            if (currentTab == widget.tab && mounted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_bookContentFocusNode.hasFocus) {
                  _bookContentFocusNode.requestFocus();
                }
              });
            }
          },
          builder: (context, tabsState) {
            // סגירת חלונית הצד כשנמצאים במצב side-by-side
            if (tabsState.isSideBySideMode) {
              final currentState = context.read<TextBookBloc>().state;
              if (currentState is TextBookLoaded && currentState.showLeftPane) {
                // בדיקה אם הטאב הנוכחי הוא אחד מהטאבים המוצגים
                final currentTabIndex = tabsState.currentTabIndex;
                final isInSideBySide = currentTabIndex ==
                        tabsState.sideBySideMode!.leftTabIndex ||
                    currentTabIndex == tabsState.sideBySideMode!.rightTabIndex;

                if (isInSideBySide) {
                  // סגירה מיידית
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      context
                          .read<TextBookBloc>()
                          .add(const ToggleLeftPane(false));
                    }
                  });
                }
              }
            }

            return BlocConsumer<TextBookBloc, TextBookState>(
              bloc: context.read<TextBookBloc>(),
              listener: (context, state) {
                if (state is TextBookLoaded &&
                    state.isEditorOpen &&
                    state.editorIndex != null) {
                  _openEditorDialog(context, state);
                }

                if (state is TextBookLoaded) {
                  final pendingSidebarTab =
                      Settings.getValue<int>('key-sidebar-tab-index-pending');
                  if (pendingSidebarTab != null && pendingSidebarTab >= 0) {
                    if (_sidebarTabIndex != pendingSidebarTab) {
                      setState(() {
                        _sidebarTabIndex = pendingSidebarTab;
                      });
                    }
                    if (state.showSplitView) {
                      Settings.setValue<int>(
                          'key-sidebar-tab-index-pending', -1);
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
                  final pendingSidebarTab =
                      Settings.getValue<int>('key-sidebar-tab-index-pending');
                  if (_sidebarTabIndex != null &&
                      (pendingSidebarTab == null || pendingSidebarTab < 0)) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      setState(() {
                        _sidebarTabIndex = null;
                      });
                    });
                  }

                  debugPrint(
                      'DEBUG: LoadContent נקרא עם showSplitView: ${state.splitedView} (isInCombinedView: ${widget.isInCombinedView})');

                  context.read<TextBookBloc>().add(
                        LoadContent(
                          fontSize: settingsState.fontSize,
                          // בתצוגה משולבת, מפרשים תמיד מתחת (showSplitView = false)
                          // אחרת, משתמשים בערך שנשמר ב-state של הטאב
                          showSplitView: widget.isInCombinedView
                              ? false
                              : state.splitedView,
                          removeNikud: settingsState.defaultRemoveNikud,
                          // בתצוגה משולבת, חלונית הצד תמיד סגורה
                          forceCloseLeftPane: widget.isInCombinedView,
                        ),
                      );
                }

                if (state is TextBookInitial || state is TextBookLoading) {
                  final screenWidth = MediaQuery.of(context).size.width;
                  return Scaffold(
                    appBar: AppBar(
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainer,
                      shape: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          width: 0.3,
                        ),
                      ),
                      elevation: 0,
                      scrolledUnderElevation: 0,
                      centerTitle: false,
                      title: Text(
                        widget.tab.book.title,
                        style: const TextStyle(fontSize: 17),
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      leading: IconButton(
                        icon: const Icon(FluentIcons.navigation_24_regular),
                        tooltip: "ניווט וחיפוש",
                        onPressed: null,
                      ),
                      actions: [
                        ResponsiveActionBar(
                          key: ValueKey('loading_actions_$screenWidth'),
                          actions: [
                            // NOTE: PDF button intentionally omitted during loading
                            ActionButtonData(
                              widget: IconButton(
                                icon: const Icon(
                                    FluentIcons.panel_left_24_regular),
                                tooltip: 'הצגת מפרשים',
                                onPressed: null,
                              ),
                              icon: FluentIcons.panel_left_24_regular,
                              tooltip: 'הצגת מפרשים',
                              onPressed: null,
                            ),
                            ActionButtonData(
                              widget: IconButton(
                                icon: const Icon(
                                    FluentIcons.text_font_24_regular),
                                tooltip: 'הצג או הסתר ניקוד',
                                onPressed: null,
                              ),
                              icon: FluentIcons.text_font_24_regular,
                              tooltip: 'הצג או הסתר ניקוד',
                              onPressed: null,
                            ),
                            ActionButtonData(
                              widget: IconButton(
                                icon: const Icon(FluentIcons.search_24_regular),
                                tooltip: 'חיפוש',
                                onPressed: null,
                              ),
                              icon: FluentIcons.search_24_regular,
                              tooltip: 'חיפוש',
                              onPressed: null,
                            ),
                            ActionButtonData(
                              widget: IconButton(
                                icon:
                                    const Icon(FluentIcons.zoom_in_24_regular),
                                tooltip: 'הגדל את גודל הטקסט',
                                onPressed: null,
                              ),
                              icon: FluentIcons.zoom_in_24_regular,
                              tooltip: 'הגדל את גודל הטקסט',
                              onPressed: null,
                            ),
                            ActionButtonData(
                              widget: IconButton(
                                icon:
                                    const Icon(FluentIcons.zoom_out_24_regular),
                                tooltip: 'הקטן את גודל הטקסט',
                                onPressed: null,
                              ),
                              icon: FluentIcons.zoom_out_24_regular,
                              tooltip: 'הקטן את גודל הטקסט',
                              onPressed: null,
                            ),
                            ActionButtonData(
                              widget: IconButton(
                                icon: const Icon(
                                    FluentIcons.arrow_previous_24_filled),
                                tooltip: 'תחילת הספר',
                                onPressed: null,
                              ),
                              icon: FluentIcons.arrow_previous_24_filled,
                              tooltip: 'תחילת הספר',
                              onPressed: null,
                            ),
                            ActionButtonData(
                              widget: IconButton(
                                icon: const Icon(
                                    FluentIcons.chevron_left_24_regular),
                                tooltip: 'הקטע הקודם',
                                onPressed: null,
                              ),
                              icon: FluentIcons.chevron_left_24_regular,
                              tooltip: 'הקטע הקודם',
                              onPressed: null,
                            ),
                            ActionButtonData(
                              widget: IconButton(
                                icon: const Icon(
                                    FluentIcons.chevron_right_24_regular),
                                tooltip: 'הקטע הבא',
                                onPressed: null,
                              ),
                              icon: FluentIcons.chevron_right_24_regular,
                              tooltip: 'הקטע הבא',
                              onPressed: null,
                            ),
                            ActionButtonData(
                              widget: IconButton(
                                icon: const Icon(
                                    FluentIcons.arrow_next_24_filled),
                                tooltip: 'סוף הספר',
                                onPressed: null,
                              ),
                              icon: FluentIcons.arrow_next_24_filled,
                              tooltip: 'סוף הספר',
                              onPressed: null,
                            ),
                          ],
                          // כך שהכפתור "..." יוצג גם במצב טעינה
                          alwaysInMenu: [
                            ActionButtonData(
                              widget: const SizedBox.shrink(),
                              icon: FluentIcons.more_horizontal_24_regular,
                              tooltip: 'פעולות נוספות',
                              onPressed: null,
                              submenuItems: [
                                ActionButtonData(
                                  widget: const SizedBox.shrink(),
                                  icon: FluentIcons.more_horizontal_24_regular,
                                  tooltip: '',
                                  onPressed: null,
                                ),
                              ],
                            ),
                          ],
                          maxVisibleButtons: screenWidth < 400
                              ? 2
                              : screenWidth < 500
                                  ? 4
                                  : screenWidth < 600
                                      ? 6
                                      : screenWidth < 700
                                          ? 8
                                          : screenWidth < 800
                                              ? 10
                                              : screenWidth < 900
                                                  ? 12
                                                  : screenWidth < 1100
                                                      ? 14
                                                      : 999,
                        ),
                      ],
                    ),
                    body: const Center(child: CircularProgressIndicator()),
                  );
                }

                if (state is TextBookError) {
                  return Center(child: Text('Error: ${(state).message}'));
                }

                if (state is TextBookLoaded) {
                  // בקשת focus אוטומטית כשהספר נטען
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_bookContentFocusNode.hasFocus) {
                      _bookContentFocusNode.requestFocus();
                    }
                  });

                  return LayoutBuilder(
                    builder: (context, constrains) {
                      final wideScreen =
                          (MediaQuery.of(context).size.width >= 600);
                      return KeyboardListener(
                        focusNode: _bookContentFocusNode,
                        autofocus: true,
                        onKeyEvent: (event) => _handleGlobalKeyEvent(
                            event, context, state, widget.tab),
                        child: Scaffold(
                          appBar: _buildAppBar(context, state, wideScreen),
                          body: _buildBody(context, state, wideScreen),
                        ),
                      );
                    },
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

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    TextBookLoaded state,
    bool wideScreen,
  ) {
    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: Border(
        bottom: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.3,
        ),
      ),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      title: _buildTitle(state),
      leadingWidth:
          state.showPageShapeView ? 96 : null, // רוחב מורחב לשני כפתורים
      leading: state.showPageShapeView
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildMenuButton(context, state),
                _buildPageShapeSettingsButton(context, state),
              ],
            )
          : _buildMenuButton(context, state),
      actions: _buildActions(context, state, wideScreen),
    );
  }

  /// כפתור הגדרות צורת הדף
  Widget _buildPageShapeSettingsButton(
      BuildContext context, TextBookLoaded state) {
    return IconButton(
      icon: const Icon(FluentIcons.settings_24_regular, size: 20),
      tooltip: 'הגדרות צורת הדף',
      onPressed: () async {
        // טעינת ההגדרות הנוכחיות
        final config = PageShapeSettingsManager.loadConfiguration(
          state.book.title,
          heCategories: state.book.heCategories,
        );

        // אם אין הגדרות שמורות, נשתמש בברירות מחדל
        final currentSettings = config ??
            await DefaultCommentators.getDefaults(state.book,
                links: state.links);

        if (!context.mounted) return;

        final availableCommentators = state.availableCommentators;
        final bookTitle = state.book.title;
        final hadChanges = await showDialog<bool>(
          context: context,
          builder: (builderContext) => PageShapeSettingsDialog(
            availableCommentators: availableCommentators,
            bookTitle: bookTitle,
            heCategories: state.book.heCategories,
            currentLeft: currentSettings['left'],
            currentRight: currentSettings['right'],
            currentBottom: currentSettings['bottom'],
            currentBottomRight: currentSettings['bottomRight'],
          ),
        );
        // אם היו שינויים, נשנה את המפתח כדי לגרום ל-PageShapeScreen להיבנות מחדש
        if (hadChanges == true && context.mounted) {
          setState(() {
            _pageShapeKey = UniqueKey();
          });
        }
      },
    );
  }

  Widget _buildTitle(TextBookLoaded state) {
    if (state.currentTitle == null) {
      return const SizedBox.shrink();
    }

    const titleStyle = TextStyle(fontSize: 17);
    const authorStyle = TextStyle(fontSize: 12, color: Colors.grey);

    // שימוש בפונקציה העזר להוספת שם הספר
    String displayText =
        addBookTitleToRef(state.currentTitle!, state.book.title);

    final author = state.book.author;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: displayText, style: titleStyle),
          maxLines: 1,
          textDirection: TextDirection.rtl,
        )..layout(minWidth: 0, maxWidth: constraints.maxWidth);

        final titleWidget = SelectionArea(
          child: Text(
            displayText,
            style: titleStyle,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );

        // אם יש מחבר, מציגים אותו מתחת לכותרת
        final child = author != null && author.isNotEmpty
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  titleWidget,
                  Text(
                    author,
                    style: authorStyle,
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
    return IconButton(
      icon: const Icon(FluentIcons.navigation_24_regular),
      tooltip: "ניווט וחיפוש",
      onPressed: () =>
          context.read<TextBookBloc>().add(ToggleLeftPane(!state.showLeftPane)),
    );
  }

  List<Widget> _buildActions(
    BuildContext context,
    TextBookLoaded state,
    bool wideScreen,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;

    // נקבע כמה כפתורים להציג בהתאם לרוחב המסך
    // שים לב: הכפתורים יוסתרו בסדר ההצגה (מימין לשמאל, כך שהימני ביותר יעלם אחרון)
    int maxButtons;

    if (screenWidth < 400) {
      maxButtons = 2; // 2 כפתורים + "..." במסכים קטנים מאוד
    } else if (screenWidth < 500) {
      maxButtons = 4; // 4 כפתורים + "..." במסכים קטנים
    } else if (screenWidth < 600) {
      maxButtons = 6; // 6 כפתורים + "..." במסכים בינוניים קטנים
    } else if (screenWidth < 700) {
      maxButtons = 8; // 8 כפתורים + "..." במסכים בינוניים
    } else if (screenWidth < 800) {
      maxButtons = 10; // 10 כפתורים + "..." במסכים בינוניים גדולים
    } else if (screenWidth < 900) {
      maxButtons = 12; // 12 כפתורים + "..." במסכים גדולים
    } else if (screenWidth < 1100) {
      maxButtons = 14; // 14 כפתורים + "..." במסכים גדולים יותר
    } else {
      maxButtons =
          999; // כל הכפתורים החיצוניים במסכים רחבים מאוד (ה-5 הקבועים תמיד בתפריט)
    }

    return [
      ResponsiveActionBar(
        key: ValueKey('responsive_actions_$screenWidth'),
        actions: _buildDisplayOrderActions(context, state),
        alwaysInMenu: _buildAlwaysInMenuActions(context, state),
        maxVisibleButtons: maxButtons,
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
      ActionButtonData(
        widget: _buildPdfButton(context, state),
        icon: FluentIcons.document_pdf_24_regular,
        tooltip: 'פתח ספר במהדורה מודפסת',
        onPressed: () => _handlePdfButtonPress(context, state),
      ),

      // 2) View Mode Dropdown (מאחד את Split View ו-Page Shape View)
      ActionButtonData(
        widget: _buildViewModeDropdown(context, state, key: _viewModeMenuKey),
        icon: _getViewModeIcon(state),
        tooltip: _getViewModeTooltip(state),
        onPressed: () {
          // פתיחת התפריט באופן פרוגרמטי (למקרה שהכפתור עבר לתפריט overflow)
          final dynamic menuState = _viewModeMenuKey.currentState;
          menuState?.showButtonMenu();
        },
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
          // שמירה עם הערך החדש
          await _savePerBookSettingsDirectly(context, state,
              removeNikud: newValue);
        },
      ),

      // 4) Search Button
      ActionButtonData(
        widget: _buildSearchButton(context, state),
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
          await _savePerBookSettingsDirectly(context, state, fontSize: newSize);
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
          await _savePerBookSettingsDirectly(context, state, fontSize: newSize);
        },
      ),

      // 7) Navigation Buttons - רק אם לא בתצוגה משולבת
      if (!widget.isInCombinedView) ...[
        ActionButtonData(
          widget: _buildPreviousTocButton(state),
          icon: FluentIcons.arrow_previous_24_filled,
          tooltip: 'הדף/פרק הקודם',
          onPressed: () => _navigateToPreviousToc(state),
        ),
        ActionButtonData(
          widget: _buildPreviousPageButton(state),
          icon: FluentIcons.chevron_left_24_regular,
          tooltip: 'הקטע הקודם',
          onPressed: () {
            state.scrollController.scrollTo(
              duration: const Duration(milliseconds: 300),
              index: max(
                0,
                state.positionsListener.itemPositions.value.first.index - 1,
              ),
            );
          },
        ),
        ActionButtonData(
          widget: _buildNextPageButton(state),
          icon: FluentIcons.chevron_right_24_regular,
          tooltip: 'הקטע הבא',
          onPressed: () {
            state.scrollController.scrollTo(
              index: max(
                state.positionsListener.itemPositions.value.first.index + 1,
                state.positionsListener.itemPositions.value.length - 1,
              ),
              duration: const Duration(milliseconds: 300),
            );
          },
        ),
        ActionButtonData(
          widget: _buildNextTocButton(state),
          icon: FluentIcons.arrow_next_24_filled,
          tooltip: 'הדף/פרק הבא',
          onPressed: () => _navigateToNextToc(state),
        ),
      ],
    ];
  }

  /// כפתורים שתמיד יהיו בתפריט "..." (בסדר הרצוי)
  List<ActionButtonData> _buildAlwaysInMenuActions(
    BuildContext context,
    TextBookLoaded state,
  ) {
    return [
      // כפתורי ניווט - רק בתצוגה משולבת
      if (widget.isInCombinedView) ...[
        ActionButtonData(
          widget: _buildPreviousTocButton(state),
          icon: FluentIcons.arrow_previous_24_filled,
          tooltip: 'הדף/פרק הקודם',
          onPressed: () => _navigateToPreviousToc(state),
        ),
        ActionButtonData(
          widget: _buildPreviousPageButton(state),
          icon: FluentIcons.chevron_left_24_regular,
          tooltip: 'הקטע הקודם',
          onPressed: () {
            state.scrollController.scrollTo(
              duration: const Duration(milliseconds: 300),
              index: max(
                0,
                state.positionsListener.itemPositions.value.first.index - 1,
              ),
            );
          },
        ),
        ActionButtonData(
          widget: _buildNextPageButton(state),
          icon: FluentIcons.chevron_right_24_regular,
          tooltip: 'הקטע הבא',
          onPressed: () {
            state.scrollController.scrollTo(
              index: max(
                state.positionsListener.itemPositions.value.first.index + 1,
                state.positionsListener.itemPositions.value.length - 1,
              ),
              duration: const Duration(milliseconds: 300),
            );
          },
        ),
        ActionButtonData(
          widget: _buildNextTocButton(state),
          icon: FluentIcons.arrow_next_24_filled,
          tooltip: 'הדף/פרק הבא',
          onPressed: () => _navigateToNextToc(state),
        ),
      ],

      // 1) הוספת סימניה
      ActionButtonData(
        widget: _buildBookmarkButton(context, state),
        icon: FluentIcons.bookmark_add_24_regular,
        tooltip: 'הוסף סימניה',
        onPressed: () => _handleBookmarkPress(context, state),
      ),

      // 2) הצג הערות אישיות
      ActionButtonData(
        widget: IconButton(
          onPressed: () {
            // פתיחת חלונית הצד עם כרטיסיית ההערות (אינדקס 2)
            setState(() {
              _sidebarTabIndex = 2; // כרטיסיית ההערות
            });
            context.read<TextBookBloc>().add(const ToggleSplitView(true));
          },
          icon: const Icon(FluentIcons.note_24_regular),
          tooltip: 'הצג הערות אישיות',
        ),
        icon: FluentIcons.note_24_regular,
        tooltip: 'הצג הערות אישיות',
        onPressed: () {
          // פתיחת חלונית הצד עם כרטיסיית ההערות (אינדקס 2)
          setState(() {
            _sidebarTabIndex = 2; // כרטיסיית ההערות
          });
          context.read<TextBookBloc>().add(const ToggleSplitView(true));
        },
      ),

      // 3) שמור וזכור - סמן כנלמד או הוסף למעקב
      ActionButtonData(
        widget: _buildShamorZachorButton(context, state),
        icon: _isBookTrackedInShamorZachor(state.book.title)
            ? FluentIcons.checkmark_circle_24_regular
            : FluentIcons.add_circle_24_regular,
        tooltip: _isBookTrackedInShamorZachor(state.book.title)
            ? 'סמן כנלמד בשמור וזכור'
            : 'הוסף למעקב לימוד בשמור וזכור',
        onPressed: () {
          if (_isBookTrackedInShamorZachor(state.book.title)) {
            _markShamorZachorProgress(state.book.title);
          } else {
            _addBookToShamorZachorTracking(state.book);
          }
        },
      ),

      // 4) איפוס הגדרות פר-ספר (מוצג רק כשההגדרה מופעלת) - לא בתצוגה משולבת
      if (!widget.isInCombinedView &&
          context.read<SettingsBloc>().state.enablePerBookSettings)
        ActionButtonData(
          widget: IconButton(
            icon: const Icon(FluentIcons.arrow_reset_24_regular),
            tooltip: 'אפס הגדרות ספר זה',
            onPressed: () => _resetPerBookSettings(),
          ),
          icon: FluentIcons.arrow_reset_24_regular,
          tooltip: 'אפס הגדרות ספר זה',
          onPressed: () => _resetPerBookSettings(),
        ),

      // 5) ערוך את הספר - לא בתצוגה משולבת
      if (!widget.isInCombinedView)
        ActionButtonData(
          widget: _buildFullFileEditorButton(context, state),
          icon: FluentIcons.document_edit_24_regular,
          tooltip: 'ערוך את הספר',
          onPressed: () => _handleFullFileEditorPress(context, state),
        ),

      // 6) הדפסה - לא בתצוגה משולבת
      if (!widget.isInCombinedView)
        ActionButtonData(
          widget: _buildPrintButton(context, state),
          icon: FluentIcons.print_24_regular,
          tooltip: 'הדפסה',
          onPressed: () => _handlePrintPress(state),
        ),

      // 7) אודות הספר - לא בתצוגה משולבת
      if (!widget.isInCombinedView)
        ActionButtonData(
          widget: IconButton(
            icon: const Icon(FluentIcons.info_24_regular),
            tooltip: 'אודות הספר',
            onPressed: () => showBookSourceDialog(context, state),
          ),
          icon: FluentIcons.info_24_regular,
          tooltip: 'אודות הספר',
          onPressed: () => showBookSourceDialog(context, state),
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
            ActionButtonData(
              widget: const SizedBox.shrink(),
              icon: FluentIcons.document_edit_24_regular,
              tooltip: 'ערוך את הספר',
              onPressed: () => _handleFullFileEditorPress(context, state),
            ),
            ActionButtonData(
              widget: const SizedBox.shrink(),
              icon: FluentIcons.print_24_regular,
              tooltip: 'הדפסה',
              onPressed: () => _handlePrintPress(state),
            ),
            ActionButtonData(
              widget: const SizedBox.shrink(),
              icon: FluentIcons.info_24_regular,
              tooltip: 'אודות הספר',
              onPressed: () => showBookSourceDialog(context, state),
            ),
          ],
        ),
    ];
  }

  Widget _buildPdfButton(BuildContext context, TextBookLoaded state) {
    return FutureBuilder<Book?>(
      future: DataRepository.instance.library.then(
        (library) => library.findBookByTitle(state.book.title, PdfBook),
      ),
      builder: (context, snapshot) {
        // Show button only if PDF book exists (snapshot.data is not null)
        final pdfBook = snapshot.data;
        if (pdfBook == null) {
          return const SizedBox.shrink();
        }

        return IconButton(
          icon: const Icon(FluentIcons.document_pdf_24_regular),
          tooltip: 'פתח ספר במהדורה מודפסת ',
          onPressed: () async {
            final currentIndex =
                state.positionsListener.itemPositions.value.isNotEmpty
                    ? state.positionsListener.itemPositions.value.first.index
                    : 0;
            widget.tab.index = currentIndex;

            final index = await textToPdfPage(
              state.book,
              currentIndex,
            );

            if (!context.mounted) return;

            openBook(context, pdfBook, index ?? 1, '', ignoreHistory: true);
          },
        );
      },
    );
  }

  /// קבלת האייקון המתאים למצב התצוגה הנוכחי
  IconData _getViewModeIcon(TextBookLoaded state) {
    if (state.showPageShapeView) {
      return FluentIcons.book_open_24_filled;
    }
    // מפרשים בצד/מתחת - אותו אייקון (הסיבוב מתבצע מחוץ לפונקציה)
    return FluentIcons.panel_left_24_regular;
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

  /// בניית תפריט נפתח לבחירת מצב תצוגה
  Widget _buildViewModeDropdown(BuildContext context, TextBookLoaded state,
      {Key? key}) {
    // אייקון מסובב כשמפרשים מתחת
    final iconWidget = state.showPageShapeView
        ? Icon(_getViewModeIcon(state))
        : RotatedBox(
            quarterTurns: state.showSplitView ? 0 : 3,
            child: Icon(_getViewModeIcon(state)),
          );

    return PopupMenuButton<String>(
      key: key,
      tooltip: 'בחר סוג תצוגת מפרשים',
      icon: iconWidget,
      enabled: !widget.isInCombinedView,
      position: PopupMenuPosition.under,
      onSelected: (value) async {
        final bloc = context.read<TextBookBloc>();

        // קביעת מצב היעד לפי הבחירה
        final bool isPage = value == _viewModePage;
        final bool isSplit = value == _viewModeSplit;

        // עדכון תצוגת צורת הדף במידת הצורך
        if (isPage != state.showPageShapeView) {
          bloc.add(TogglePageShapeView(isPage));
        }

        // עדכון תצוגת המפרשים במידת הצורך (רק במצבים שאינם 'צורת הדף')
        if (!isPage && isSplit != state.showSplitView) {
          bloc.add(ToggleSplitView(isSplit));
          await _savePerBookSettingsDirectly(context, state,
              showSplitView: isSplit);
        }
      },
      itemBuilder: (context) {
        final primaryColor = Theme.of(context).colorScheme.primary;
        final isSplit = !state.showPageShapeView && state.showSplitView;
        final isBelow = !state.showPageShapeView && !state.showSplitView;
        final isPage = state.showPageShapeView;

        PopupMenuItem<String> buildItem({
          required String value,
          required String text,
          required Widget icon,
          required bool isSelected,
        }) {
          final style = isSelected ? TextStyle(color: primaryColor) : null;
          return PopupMenuItem<String>(
            value: value,
            child: Row(
              children: [
                icon,
                const SizedBox(width: 12),
                Text(text, style: style),
                if (isSelected) ...[
                  const Spacer(),
                  Icon(FluentIcons.checkmark_24_regular,
                      size: 16, color: primaryColor),
                ],
              ],
            ),
          );
        }

        return [
          buildItem(
            value: _viewModeSplit,
            text: 'מפרשים בצד',
            icon: Icon(FluentIcons.panel_left_24_regular,
                color: isSplit ? primaryColor : null),
            isSelected: isSplit,
          ),
          buildItem(
            value: _viewModeBelow,
            text: 'מפרשים מתחת',
            icon: RotatedBox(
              quarterTurns: 3,
              child: Icon(FluentIcons.panel_left_24_regular,
                  color: isBelow ? primaryColor : null),
            ),
            isSelected: isBelow,
          ),
          buildItem(
            value: _viewModePage,
            text: 'צורת הדף',
            icon: Icon(FluentIcons.book_open_24_regular,
                color: isPage ? primaryColor : null),
            isSelected: isPage,
          ),
        ];
      },
    );
  }

  Widget _buildNikudButton(BuildContext context, TextBookLoaded state) {
    return IconButton(
      onPressed: () async {
        final newValue = !state.removeNikud;
        context.read<TextBookBloc>().add(ToggleNikud(newValue));
        // שמירה עם הערך החדש
        await _savePerBookSettingsDirectly(context, state,
            removeNikud: newValue);
      },
      icon: Icon(state.removeNikud
          ? FluentIcons.text_font_24_regular
          : FluentIcons.text_font_info_24_regular),
      tooltip: state.removeNikud ? 'הצג ניקוד' : 'הסתר ניקוד',
    );
  }

  Widget _buildBookmarkButton(BuildContext context, TextBookLoaded state) {
    final shortcut =
        Settings.getValue<String>('key-shortcut-add-bookmark') ?? 'ctrl+b';
    return IconButton(
      onPressed: () async {
        int index = state.positionsListener.itemPositions.value.first.index;
        final toc = state.book.tableOfContents;
        String ref = await refFromIndex(index, toc);
        // הוספת שם הספר לכותרת
        ref = addBookTitleToRef(ref, state.book.title);
        if (!mounted || !context.mounted) return;

        bool bookmarkAdded = context.read<BookmarkBloc>().addBookmark(
              ref: ref,
              book: state.book,
              index: index,
              commentatorsToShow: state.activeCommentators,
            );
        UiSnack.showQuick(
            bookmarkAdded ? 'הסימניה נוספה בהצלחה' : 'הסימניה כבר קיימת');
      },
      icon: const Icon(FluentIcons.bookmark_add_24_regular),
      tooltip: 'הוסף סימניה (${shortcut.toUpperCase()})',
    );
  }

  Widget _buildSearchButton(BuildContext context, TextBookLoaded state) {
    final shortcut =
        Settings.getValue<String>('key-shortcut-search-in-book') ?? 'ctrl+f';
    return IconButton(
      onPressed: _openSearchFromToolbar,
      icon: const Icon(FluentIcons.search_24_regular),
      tooltip: 'חיפוש (${shortcut.toUpperCase()})',
    );
  }

  Widget _buildZoomInButton(BuildContext context, TextBookLoaded state) {
    return IconButton(
      icon: const Icon(FluentIcons.zoom_in_24_regular),
      tooltip: 'הגדל את גודל הטקסט (CTRL + +)',
      onPressed: () async {
        final newSize = min(50.0, state.fontSize + 3);
        context.read<TextBookBloc>().add(UpdateFontSize(newSize));
        await _savePerBookSettingsDirectly(context, state, fontSize: newSize);
      },
    );
  }

  Widget _buildZoomOutButton(BuildContext context, TextBookLoaded state) {
    return IconButton(
      icon: const Icon(FluentIcons.zoom_out_24_regular),
      tooltip: 'הקטן את גודל הטקסט (CTRL + -)',
      onPressed: () async {
        final newSize = max(15.0, state.fontSize - 3);
        context.read<TextBookBloc>().add(UpdateFontSize(newSize));
        await _savePerBookSettingsDirectly(context, state, fontSize: newSize);
      },
    );
  }

  Widget _buildPreviousPageButton(TextBookLoaded state) {
    return IconButton(
      icon: const Icon(FluentIcons.chevron_left_24_regular),
      tooltip: 'הקטע הקודם',
      onPressed: () {
        state.scrollController.scrollTo(
          duration: const Duration(milliseconds: 300),
          index: max(
            0,
            state.positionsListener.itemPositions.value.first.index - 1,
          ),
        );
      },
    );
  }

  Widget _buildNextPageButton(TextBookLoaded state) {
    return IconButton(
      icon: const Icon(FluentIcons.chevron_right_24_regular),
      tooltip: 'הקטע הבא',
      onPressed: () {
        state.scrollController.scrollTo(
          index: max(
            state.positionsListener.itemPositions.value.first.index + 1,
            state.positionsListener.itemPositions.value.length - 1,
          ),
          duration: const Duration(milliseconds: 300),
        );
      },
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
      List<TocEntry> entries, int currentIndex, String bookTitle) {
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
      List<TocEntry> entries, int currentIndex, String bookTitle) {
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
    final currentIndex = state.positionsListener.itemPositions.value.isNotEmpty
        ? state.positionsListener.itemPositions.value.first.index
        : 0;
    final prevIndex = _findPreviousTocIndex(
        state.tableOfContents, currentIndex, state.book.title);
    if (prevIndex != null) {
      state.scrollController.scrollTo(
        index: prevIndex,
        duration: const Duration(milliseconds: 300),
      );
    }
  }

  /// ניווט לכותרת הבאה ב-TOC
  void _navigateToNextToc(TextBookLoaded state) {
    final currentIndex = state.positionsListener.itemPositions.value.isNotEmpty
        ? state.positionsListener.itemPositions.value.first.index
        : 0;
    final nextIndex = _findNextTocIndex(
        state.tableOfContents, currentIndex, state.book.title);
    if (nextIndex != null) {
      state.scrollController.scrollTo(
        index: nextIndex,
        duration: const Duration(milliseconds: 300),
      );
    }
  }

  Widget _buildPreviousTocButton(TextBookLoaded state) {
    return IconButton(
      icon: const Icon(FluentIcons.arrow_previous_24_filled),
      tooltip: 'הדף/פרק הקודם',
      onPressed: () => _navigateToPreviousToc(state),
    );
  }

  Widget _buildNextTocButton(TextBookLoaded state) {
    return IconButton(
      icon: const Icon(FluentIcons.arrow_next_24_filled),
      tooltip: 'הדף/פרק הבא',
      onPressed: () => _navigateToNextToc(state),
    );
  }

  Widget _buildPrintButton(BuildContext context, TextBookLoaded state) {
    final shortcut =
        Settings.getValue<String>('key-shortcut-print') ?? 'ctrl+p';
    return IconButton(
      icon: const Icon(FluentIcons.print_24_regular),
      tooltip: 'הדפסה (${shortcut.toUpperCase()})',
      onPressed: () {
        final settingsState = context.read<SettingsBloc>().state;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PrintingScreen(
              data: Future.value(state.content.join('\n')),
              bookId: state.book.title,
              links: state.links,
              activeCommentators: state.activeCommentators,
              startLine: state.visibleIndices.first,
              removeNikud: state.removeNikud,
              removeTaamim: !settingsState.showTeamim,
              tableOfContents: state.tableOfContents,
            ),
          ),
        );
      },
    );
  }

  Widget _buildShamorZachorButton(BuildContext context, TextBookLoaded state) {
    // Always show button - either for marking progress or for adding to tracking
    final isTracked = _isBookTrackedInShamorZachor(state.book.title);

    return IconButton(
      onPressed: () {
        if (isTracked) {
          // Book is already tracked - mark progress
          _markShamorZachorProgress(state.book.title);
        } else {
          // Book is not tracked - add to tracking
          _addBookToShamorZachorTracking(state.book);
        }
      },
      icon: isTracked
          ? Image.asset(
              'assets/icon/shamor_zachor_with_v.png',
              width: 24,
              height: 24,
            )
          : const Icon(FluentIcons.add_circle_24_regular, size: 24),
      tooltip:
          isTracked ? 'סמן כנלמד בשמור וזכור' : 'הוסף למעקב לימוד בשמור וזכור',
    );
  }

  /// Add book to Shamor Zachor tracking
  Future<void> _addBookToShamorZachorTracking(Book book) async {
    try {
      final dataProvider = context.read<ShamorZachorDataProvider>();

      final bookTitle = book.title;

      // 1. Get book path from library or database
      String? bookPath = book.filePath;

      if (bookPath == null) {
        final location = await BookLocator.locateBook(bookTitle);
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
              final repository = dbProvider.repository;
              if (repository != null) {
                final dbBook = await repository.getBookByTitle(bookTitle);
                if (dbBook != null) {
                  final category =
                      await repository.getCategory(dbBook.categoryId);
                  if (category != null) {
                    final categoryParts = <String>[];
                    dynamic currentCategory = category;
                    while (currentCategory != null) {
                      categoryParts.insert(0, currentCategory.title);
                      if (currentCategory.parentId != null) {
                        currentCategory = await repository
                            .getCategory(currentCategory.parentId!);
                      } else {
                        break;
                      }
                    }
                    categoryPath = categoryParts.join('/');
                  }
                }
              }
            } catch (e) {
              debugPrint('Error getting category from DB: $e');
            }
          }
        }

        if (categoryPath.isNotEmpty) {
          final libraryPath =
              Settings.getValue<String>('key-library-path') ?? '.';
          bookPath =
              '$libraryPath${Platform.pathSeparator}אוצריא${Platform.pathSeparator}$categoryPath${Platform.pathSeparator}$bookTitle.txt';
          debugPrint('Book path from DB: $bookPath');
        }
      }

      if (bookPath == null) {
        UiSnack.showError('לא נמצא נתיב לספר');
        return;
      }

      debugPrint('Adding book to tracking - Path: $bookPath');

      // 2. Use the actual book title as-is (don't modify it)
      // The title should match exactly what's in the DB
      String cleanBookName = bookTitle;

      // 3. Show loading indicator
      UiSnack.show('מוסיף ספר למעקב...');

      // 4. Add book via provider (only needs book name)
      await dataProvider.addCustomBook(
        bookName: cleanBookName,
      );

      // 5. Success message
      UiSnack.show('הספר "$cleanBookName" נוסף למעקב בהצלחה!');

      // 6. Update UI to reflect the change
      setState(() {});
    } catch (e, stackTrace) {
      debugPrint('Error adding book to Shamor Zachor: $e');
      debugPrint('Stack trace: $stackTrace');
      UiSnack.showError('שגיאה בהוספת הספר למעקב: ${e.toString()}');
    }
  }

  /// פונקציות עזר לטיפול בלחיצות על כפתורים בתפריט הנפתח
  void _handlePdfButtonPress(BuildContext context, TextBookLoaded state) async {
    final currentIndex = state.positionsListener.itemPositions.value.isNotEmpty
        ? state.positionsListener.itemPositions.value.first.index
        : 0;
    widget.tab.index = currentIndex;

    final library = await DataRepository.instance.library;
    if (!context.mounted) return;

    final book = library.findBookByTitle(state.book.title, PdfBook);
    if (book == null) {
      return;
    }

    final index = await textToPdfPage(state.book, currentIndex);

    if (!context.mounted) return;

    openBook(context, book, index ?? 1, '', ignoreHistory: true);
  }

  void _handleBookmarkPress(BuildContext context, TextBookLoaded state) async {
    final index = state.positionsListener.itemPositions.value.first.index;
    final toc = state.book.tableOfContents;
    final bookmarkBloc = context.read<BookmarkBloc>();
    String ref = await refFromIndex(index, toc);
    // הוספת שם הספר לכותרת
    ref = addBookTitleToRef(ref, state.book.title);
    if (!mounted || !context.mounted) return;

    final bookmarkAdded = bookmarkBloc.addBookmark(
      ref: ref,
      book: state.book,
      index: index,
      commentatorsToShow: state.activeCommentators,
    );

    UiSnack.showQuick(
        bookmarkAdded ? 'הסימניה נוספה בהצלחה' : 'הסימניה כבר קיימת');
  }

  Widget _buildBody(
    BuildContext context,
    TextBookLoaded state,
    bool wideScreen,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) => MediaQuery.of(context).size.width < 600
          ? Stack(
              children: [
                _buildHTMLViewer(state),
                Container(
                  color: Theme.of(context).colorScheme.surface,
                  child: _buildTabBar(state),
                ),
              ],
            )
          : Row(
              children: [
                _buildTabBar(state),
                if (state.showLeftPane)
                  ResizableDragHandle(
                    isVertical: true,
                    hitSize: 4,
                    onDragDelta: (delta) {
                      final newWidth =
                          (_sidebarWidth.value - delta).clamp(200.0, 600.0);
                      _sidebarWidth.value = newWidth;
                    },
                    onDragEnd: () {
                      context
                          .read<SettingsBloc>()
                          .add(UpdateSidebarWidth(_sidebarWidth.value));
                    },
                  ),
                Expanded(child: _buildHTMLViewer(state)),
              ],
            ),
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
            _savePerBookSettingsDirectly(context, currentState,
                fontSize: currentState.fontSize);
          }
        },
        child: NotificationListener<UserScrollNotification>(
          onNotification: (scrollNotification) {
            if (!(state.pinLeftPane ||
                (Settings.getValue<bool>('key-pin-sidebar') ?? false))) {
              Future.microtask(() {
                if (!mounted || !context.mounted) return;
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
            },
            child: TextBookScaffold(
              content: state.content,
              openBookCallback: widget.openBookCallback,
              openLeftPaneTab: _openLeftPaneTab,
              onSelectedTextChanged: _onSelectedTextChanged,
              searchTextController: TextEditingValue(text: state.searchText),
              tab: widget.tab,
              initialSidebarTabIndex: _sidebarTabIndex,
              pageShapeKey: _pageShapeKey,
              pageShapePrintBoundaryKey: _pageShapePrintBoundaryKey,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(TextBookLoaded state) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (state.showLeftPane && !Platform.isAndroid && !_isInitialFocusDone) {
        final hasSearchText = state.searchText.trim().isNotEmpty;
        if (hasSearchText) {
          if (tabController.index == (_hasAltTitles ? 2 : 1)) {
            textSearchFocusNode.requestFocus();
          } else if (tabController.index == 0) {
            navigationSearchFocusNode.requestFocus();
          }
        }
        _isInitialFocusDone = true;
      }
    });
    return ValueListenableBuilder<double>(
      valueListenable: _sidebarWidth,
      builder: (context, width, child) => AnimatedSize(
        duration: const Duration(milliseconds: 300),
        child: SizedBox(
          width: state.showLeftPane ? width : 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(1, 0, 4, 0),
            child: Column(
              children: [
                SizedBox(
                  height: 44,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).dividerColor,
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TabBar(
                            controller: tabController,
                            tabs: [
                              const Tab(
                                icon: Icon(FluentIcons.navigation_24_regular,
                                    size: 16),
                                iconMargin: EdgeInsets.only(bottom: 1),
                                height: 44,
                                child: Text('ניווט',
                                    style: TextStyle(fontSize: 11)),
                              ),
                              if (_hasAltTitles)
                                const Tab(
                                  icon: Icon(FluentIcons.list_24_regular,
                                      size: 16),
                                  iconMargin: EdgeInsets.only(bottom: 1),
                                  height: 44,
                                  child: Text('כותרות',
                                      style: TextStyle(fontSize: 11)),
                                ),
                              const Tab(
                                icon: Icon(FluentIcons.search_24_regular,
                                    size: 16),
                                iconMargin: EdgeInsets.only(bottom: 1),
                                height: 44,
                                child: Text('חיפוש',
                                    style: TextStyle(fontSize: 11)),
                              ),
                            ],
                            labelColor: Theme.of(context).colorScheme.primary,
                            unselectedLabelColor: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                            indicatorColor:
                                Theme.of(context).colorScheme.primary,
                            dividerColor: Colors.transparent,
                          ),
                        ),
                        if (MediaQuery.of(context).size.width >= 600)
                          IconButton(
                            onPressed:
                                (Settings.getValue<bool>('key-pin-sidebar') ??
                                        false)
                                    ? null
                                    : () => context.read<TextBookBloc>().add(
                                          TogglePinLeftPane(!state.pinLeftPane),
                                        ),
                            icon: AnimatedRotation(
                              turns: (state.pinLeftPane ||
                                      (Settings.getValue<bool>(
                                              'key-pin-sidebar') ??
                                          false))
                                  ? -0.125
                                  : 0.0,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(
                                (state.pinLeftPane ||
                                        (Settings.getValue<bool>(
                                                'key-pin-sidebar') ??
                                            false))
                                    ? FluentIcons.pin_24_filled
                                    : FluentIcons.pin_24_regular,
                              ),
                            ),
                            color: (state.pinLeftPane ||
                                    (Settings.getValue<bool>(
                                            'key-pin-sidebar') ??
                                        false))
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            isSelected: state.pinLeftPane ||
                                (Settings.getValue<bool>('key-pin-sidebar') ??
                                    false),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: tabController,
                    children: [
                      _buildTocViewer(context, state),
                      if (_hasAltTitles)
                        AltTocSidebarView(
                          book: widget.tab.book,
                          closeLeftPaneCallback: () => context
                              .read<TextBookBloc>()
                              .add(const ToggleLeftPane(false)),
                          scrollController: state.scrollController,
                        ),
                      CallbackShortcuts(
                        bindings: <ShortcutActivator, VoidCallback>{
                          LogicalKeySet(
                            LogicalKeyboardKey.control,
                            LogicalKeyboardKey.keyF,
                          ): () {
                            context.read<TextBookBloc>().add(
                                  const ToggleLeftPane(true),
                                );
                            // Adjust index based on whether alt titles are shown
                            tabController.index = _hasAltTitles ? 2 : 1;
                            textSearchFocusNode.requestFocus();
                          },
                        },
                        child: _buildSearchView(context, state),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchView(BuildContext context, TextBookLoaded state) {
    return TextBookSearchView(
      focusNode: textSearchFocusNode,
      data: state.content.join('\n'),
      scrollControler: state.scrollController,
      // הוא מעביר את טקסט החיפוש מה-state הנוכחי אל תוך רכיב החיפוש
      initialQuery: state.searchText,
      initialSearchOptions: widget.tab.searchOptions,
      initialAlternativeWords: widget.tab.alternativeWords,
      initialSpacingValues: widget.tab.spacingValues,
      initialSearchMode: widget.tab.searchMode,
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

// החלף את כל המחלקה הזו בקובץ text_book_screen.TXT

Widget _buildFullFileEditorButton(BuildContext context, TextBookLoaded state) {
  final shortcut =
      Settings.getValue<String>('key-shortcut-edit-section') ?? 'ctrl+e';
  return IconButton(
    onPressed: () => _handleFullFileEditorPress(context, state),
    icon: const Icon(FluentIcons.document_edit_24_regular),
    tooltip: 'ערוך את הספר (${shortcut.toUpperCase()})',
  );
}

void _handleTextEditorPress(BuildContext context, TextBookLoaded state) {
  final positions = state.positionsListener.itemPositions.value;
  if (positions.isEmpty) return;

  final currentIndex = positions.first.index;
  context.read<TextBookBloc>().add(OpenEditor(index: currentIndex));
}

void _handleFullFileEditorPress(BuildContext context, TextBookLoaded state) {
  context.read<TextBookBloc>().add(OpenFullFileEditor());
}

bool _handleGlobalKeyEvent(KeyEvent event, BuildContext context,
    TextBookLoaded state, TextBookTab tab) {
  // קריאת קיצורים מההגדרות
  final editSectionShortcut =
      Settings.getValue<String>('key-shortcut-edit-section') ?? 'ctrl+e';
  final searchInBookShortcut =
      Settings.getValue<String>('key-shortcut-search-in-book') ?? 'ctrl+f';
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

  // עריכת קטע
  if (ShortcutHelper.matchesShortcut(event, editSectionShortcut)) {
    if (!state.isEditorOpen) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _handleFullFileEditorPress(context, state);
      } else {
        _handleTextEditorPress(context, state);
      }
      return true;
    }
  }

  // חיפוש בספר
  if (ShortcutHelper.matchesShortcut(event, searchInBookShortcut)) {
    context.read<TextBookBloc>().add(const ToggleLeftPane(true));
    final tabController = context
        .findAncestorStateOfType<_TextBookViewerBlocState>()
        ?.tabController;
    if (tabController != null) {
      tabController.index = 1;
    }
    return true;
  }

  // הדפסה
  if (ShortcutHelper.matchesShortcut(event, printShortcut)) {
    final settingsState = context.read<SettingsBloc>().state;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PrintingScreen(
          data: Future.value(state.content.join('\n')),
          bookId: state.book.title,
          links: state.links,
          activeCommentators: state.activeCommentators,
          startLine: state.visibleIndices.first,
          removeNikud: state.removeNikud,
          removeTaamim: !settingsState.showTeamim,
          tableOfContents: state.tableOfContents,
        ),
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
    _addNoteFromKeyboard(context, state);
    return true;
  }

  // מעבר ל-PDF
  if (ShortcutHelper.matchesShortcut(event, togglePdfShortcut)) {
    _togglePdfView(context, state, tab);
    return true;
  }

  // קיצורים קבועים (לא ניתנים להתאמה אישית)
  if (event is KeyDownEvent && HardwareKeyboard.instance.isControlPressed) {
    switch (event.logicalKey) {
      // הגדל את גודל הטקסט (Ctrl++ או Ctrl+=)
      case LogicalKeyboardKey.equal:
      case LogicalKeyboardKey.add:
        final newSize = min(50.0, state.fontSize + 3);
        context.read<TextBookBloc>().add(UpdateFontSize(newSize));
        _savePerBookSettingsDirectly(context, state, fontSize: newSize);
        return true;

      // הקטן את גודל הטקסט (Ctrl+-)
      case LogicalKeyboardKey.minus:
        final newSize = max(15.0, state.fontSize - 3);
        context.read<TextBookBloc>().add(UpdateFontSize(newSize));
        _savePerBookSettingsDirectly(context, state, fontSize: newSize);
        return true;

      // איפוס גודל טקסט (Ctrl+0)
      case LogicalKeyboardKey.digit0:
        context.read<TextBookBloc>().add(const UpdateFontSize(25.0));
        _savePerBookSettingsDirectly(context, state, fontSize: 25.0);
        return true;
    }
  }

  // ניווט עם Ctrl+Home ו-Ctrl+End
  if (event is KeyDownEvent && HardwareKeyboard.instance.isControlPressed) {
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

  // מקשי פונקציה ללא Ctrl
  if (event is KeyDownEvent && !HardwareKeyboard.instance.isControlPressed) {
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

/// Helper function to save per-book settings directly from global functions
Future<void> _savePerBookSettingsDirectly(
  BuildContext context,
  TextBookLoaded state, {
  double? fontSize,
  bool? showSplitView,
  bool? removeNikud,
}) async {
  final settingsBloc = context.read<SettingsBloc>();
  if (!settingsBloc.state.enablePerBookSettings) {
    return;
  }

  // טעינת ההגדרות הקיימות
  final existingSettings = await TextBookPerBookSettings.load(state.book.title);

  // קבלת ברירות המחדל הגלובליות
  final defaultFontSize = settingsBloc.state.fontSize;
  final defaultRemoveNikud = settingsBloc.state.defaultRemoveNikud;
  final defaultShowSplitView =
      Settings.getValue<bool>('key-splited-view') ?? false;

  // בניית הגדרות חדשות - רק שדות ששונו מברירת המחדל
  double? newFontSize = existingSettings?.fontSize;
  bool? newCommentatorsBelow = existingSettings?.commentatorsBelow;
  bool? newRemoveNikud = existingSettings?.removeNikud;

  // עדכון רק השדה שהשתנה
  if (fontSize != null) {
    // אם הערך שווה לברירת המחדל, מוחקים את השדה
    newFontSize = (fontSize == defaultFontSize) ? null : fontSize;
  }

  if (showSplitView != null) {
    final commentatorsBelow = !showSplitView;
    // אם הערך שווה לברירת המחדל, מוחקים את השדה
    newCommentatorsBelow =
        (showSplitView == defaultShowSplitView) ? null : commentatorsBelow;
  }

  if (removeNikud != null) {
    // אם הערך שווה לברירת המחדל, מוחקים את השדה
    newRemoveNikud = (removeNikud == defaultRemoveNikud) ? null : removeNikud;
  }

  // אם כל השדות null, מוחקים את הקובץ כולו
  if (newFontSize == null &&
      newCommentatorsBelow == null &&
      newRemoveNikud == null) {
    await TextBookPerBookSettings.delete(state.book.title);
    return;
  }

  // שמירת ההגדרות המעודכנות
  final settings = TextBookPerBookSettings(
    fontSize: newFontSize,
    commentatorsBelow: newCommentatorsBelow,
    removeNikud: newRemoveNikud,
  );

  await settings.save(state.book.title);
}

/// Helper function to add bookmark from keyboard shortcut
void _addBookmarkFromKeyboard(
    BuildContext context, TextBookLoaded state) async {
  final index = state.positionsListener.itemPositions.value.first.index;
  final toc = state.book.tableOfContents;
  final bookmarkBloc = context.read<BookmarkBloc>();
  String ref = await refFromIndex(index, toc);
  // הוספת שם הספר לכותרת
  ref = addBookTitleToRef(ref, state.book.title);

  if (!context.mounted) return;

  final bookmarkAdded = bookmarkBloc.addBookmark(
    ref: ref,
    book: state.book,
    index: index,
    commentatorsToShow: state.activeCommentators,
  );

  UiSnack.showQuick(
      bookmarkAdded ? 'הסימניה נוספה בהצלחה' : 'הסימניה כבר קיימת');
}

/// Helper function to add note from keyboard shortcut
Future<void> _addNoteFromKeyboard(
    BuildContext context, TextBookLoaded state) async {
  // משתמש בשורה הנבחרת אם קיימת, אחרת בשורה הראשונה הנראית
  final currentIndex = state.selectedIndex ??
      (state.visibleIndices.isNotEmpty ? state.visibleIndices.first : 0);
  // לא צריך טקסט נבחר - ההערה חלה על כל השורה
  final textBookBloc = context.read<TextBookBloc>();

  // קבלת הטקסט המזהה של השורה (כמו שיוצג ככותרת ההערה)
  final referenceText = extractDisplayTextFromLines(
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
  context.read<PersonalNotesBloc>().add(StartCreatingPersonalNote(
        bookId: state.book.title,
        lineNumber: currentIndex + 1,
        referenceText: referenceText,
        initialContent: draft?.content ?? '',
        initialFormat: draft?.contentFormat ?? PersonalNoteContentFormat.plain,
      ));

  // פתח את ה-split view אם הוא סגור
  if (!state.showSplitView) {
    textBookBloc.add(const ToggleSplitView(true));
  }
}

void _openEditorDialog(BuildContext context, TextBookLoaded state) async {
  if (state.editorIndex == null || state.editorSectionId == null) return;

  final settings = EditorSettingsHelper.getSettings();

  // Reload the content from file system to ensure fresh data
  String freshContent = '';
  try {
    // Try to reload content from file system
    final dataProvider = FileSystemData.instance;
    freshContent = await dataProvider.getBookText(
      state.book.title,
      category: state.book.categoryPath,
      fileType: state.book.fileType,
    );
  } catch (e) {
    debugPrint('Failed to load fresh content: $e');
    // Fall back to cached content
    freshContent = state.editorText ?? '';
  }

  if (!context.mounted) return;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => BlocProvider.value(
      value: context.read<TextBookBloc>(),
      child: TextSectionEditorDialog(
        bookId: state.book.title,
        category: state.book.categoryPath,
        fileType: state.book.fileType,
        sectionIndex: state.editorIndex!,
        sectionId: state.editorSectionId!,
        initialContent:
            freshContent.isNotEmpty ? freshContent : state.editorText ?? '',
        hasLinksFile: state.hasLinksFile,
        hasDraft: state.hasDraft,
        settings: settings,
      ),
    ),
  );

  if (!context.mounted) return;

  // Close editor when dialog is dismissed
  context.read<TextBookBloc>().add(const CloseEditor());
}

void _togglePdfView(
    BuildContext context, TextBookLoaded state, TextBookTab tab) async {
  final currentIndex = state.positionsListener.itemPositions.value.isNotEmpty
      ? state.positionsListener.itemPositions.value.first.index
      : 0;
  tab.index = currentIndex;

  final library = await DataRepository.instance.library;
  if (!context.mounted) return;

  final book = library.findBookByTitle(state.book.title, PdfBook);
  if (book == null) {
    return;
  }

  final index = await textToPdfPage(
    state.book,
    currentIndex,
  );

  if (!context.mounted) return;

  openBook(context, book, index ?? 1, '', ignoreHistory: true);
}
