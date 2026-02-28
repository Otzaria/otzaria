import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/constants/fonts.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/text_book/view/page_shape/utils/default_commentators.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/text_book/view/page_shape/utils/commentary_sync_helper.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_settings_dialog.dart';
import 'package:otzaria/text_book/widgets/text_book_state_builder.dart';
import 'package:otzaria/widgets/loading_indicator.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/resizable_drag_handle.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/settings/bloc/settings_bloc.dart';
import 'package:otzaria/settings/bloc/settings_state.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:collection/collection.dart';
import 'dart:async';
import 'package:otzaria/core/scaffold_messenger.dart';
import 'package:otzaria/data/book_locator.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';

/// קבועים לחישוב רוחב חלוניות המפרשים
const double _kCommentaryPaneWidthFactor = 0.17;

/// רוחב הכותרת האנכית + רווחים + מפריד (20 לכותרת + 4 לרווח + 8 למפריד)
const double _kCommentaryLabelAndSpacingWidth = 32.0;

/// מסך תצוגת צורת הדף - מציג את הטקסט המרכזי עם מפרשים מסביב
class PageShapeScreen extends StatefulWidget {
  final Function(OpenedTab) openBookCallback;

  const PageShapeScreen({super.key, required this.openBookCallback});

  @override
  State<PageShapeScreen> createState() => _PageShapeScreenState();
}

class _PageShapeScreenState extends State<PageShapeScreen> {
  String? _leftCommentator;
  String? _rightCommentator;
  String? _bottomCommentator;
  String? _bottomRightCommentator;
  bool _isLoadingConfig = true;

  // גדלים לחלוניות - יחושבו לפי גודל המסך
  double? _leftWidth;
  double? _rightWidth;
  double? _bottomHeight;

  // הגדרות הצגת טורים
  Map<String, bool> _columnVisibility = {
    'left': true,
    'right': true,
    'bottom': true,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadConfiguration();
    _loadSizes();
  }

  /// טעינת גדלים שמורים או חישוב ברירות מחדל
  void _loadSizes() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    _leftWidth = Settings.getValue<double>('page_shape_left_width') ??
        screenWidth * 0.17;
    _rightWidth = Settings.getValue<double>('page_shape_right_width') ??
        screenWidth * 0.17;
    _bottomHeight = Settings.getValue<double>('page_shape_bottom_height') ??
        screenHeight * 0.27;

    setState(() {});
  }

  /// שמירת גדלים
  void _saveSizes() {
    if (_leftWidth != null) {
      Settings.setValue<double>('page_shape_left_width', _leftWidth!);
    }
    if (_rightWidth != null) {
      Settings.setValue<double>('page_shape_right_width', _rightWidth!);
    }
    if (_bottomHeight != null) {
      Settings.setValue<double>('page_shape_bottom_height', _bottomHeight!);
    }
  }

  Future<void> _loadConfiguration() async {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) {
      debugPrint(
          '⚠️ PageShape: State is not TextBookLoaded, cannot load configuration');
      return;
    }

    debugPrint('📖 PageShape: Loading configuration for "${state.book.title}"');
    debugPrint('📖 PageShape: heCategories = "${state.book.heCategories}"');

    final config = PageShapeSettingsManager.loadConfiguration(
      state.book.title,
      heCategories: state.book.heCategories,
    );

    _columnVisibility =
        PageShapeSettingsManager.getColumnVisibility(state.book.title);

    final Map<String, String?> commentators;
    if (config != null) {
      debugPrint('📖 PageShape: Found saved configuration: $config');
      // יש הגדרה שמורה - צריך להתאים שמות בסיסיים לשמות מלאים
      // (כי הגדרות קטגוריה שומרות רק שמות בסיסיים כמו "רמב"ן")
      commentators = _resolveCommentatorNames(config, state.links);
      debugPrint('📖 PageShape: Resolved commentators: $commentators');
    } else {
      debugPrint(
          '📖 PageShape: No saved configuration, loading defaults from JSON');
      // אין הגדרה שמורה בכלל - השתמש בברירות מחדל
      commentators =
          await DefaultCommentators.getDefaults(state.book, links: state.links);
      debugPrint('📖 PageShape: Default commentators loaded: $commentators');
    }

    if (mounted) {
      setState(() {
        _leftCommentator = commentators['left'];
        _rightCommentator = commentators['right'];
        _bottomCommentator = commentators['bottom'];
        _bottomRightCommentator = commentators['bottomRight'];
        _isLoadingConfig = false;
      });
      debugPrint('📖 PageShape: Configuration applied successfully');
    }
  }

  /// התאמת שמות מפרשים בסיסיים לשמות מלאים מתוך הקישורים הזמינים
  /// למשל: "רמב"ן" → "רמב"ן על בבא מציעא"
  Map<String, String?> _resolveCommentatorNames(
      Map<String, String?> config, List<Link> links) {
    // קבלת רשימת שמות המפרשים הזמינים
    final availableCommentators = links
        .where((link) => LinkTypes.isCommentaryOrTargum(link.connectionType))
        .map((link) => utils.getTitleFromPath(link.path2))
        .toSet()
        .toList();

    debugPrint('📖 PageShape: Available commentators: $availableCommentators');
    debugPrint('📖 PageShape: Config to resolve: $config');

    return Map.fromEntries(config.entries.map((entry) {
      final resolved =
          _findMatchingCommentator(entry.value, availableCommentators);
      debugPrint('📖 PageShape: Resolving "${entry.value}" → "$resolved"');
      return MapEntry(entry.key, resolved);
    }));
  }

  /// מחפש מפרש שמתאים לשם הנתון (בסיסי או מלא)
  String? _findMatchingCommentator(String? shortName, List<String> available) {
    if (shortName == null) return null;

    // The order of matching is important: exact, then startsWith, then contains.
    return available.firstWhereOrNull((name) => name == shortName) ??
        available.firstWhereOrNull((name) => name.startsWith(shortName)) ??
        available.firstWhereOrNull((name) => name.contains(shortName));
  }

  /// הסתרת טור
  ///
  /// שימו לב: פעולה זו שומרת את ההגדרה גלובלית כברירת מחדל.
  /// אם המשתמש רוצה הגדרות פר-ספר, הוא צריך לפתוח את דיאלוג ההגדרות
  /// ולהפעיל את האופציה "שמירה לספר הנוכחי בלבד".
  void _hideColumn(String column) {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;

    setState(() {
      _columnVisibility[column] = false;
    });

    // שמירה גלובלית - תחול על כל הספרים
    PageShapeSettingsManager.saveColumnVisibility(
        state.book.title, _columnVisibility,
        saveAsGlobal: true);

    // הודעה למשתמש
    UiSnack.show('הטור הוסתר בכל הספרים. ניתן לשנות בהגדרות צורת הדף.');
  }

  /// בניית widget למצב ריק של טור
  Widget _buildEmptyColumnContent({
    required String columnName,
    required VoidCallback onSelectCommentator,
    required VoidCallback onHideColumn,
  }) {
    return Container(
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.5),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: onSelectCommentator,
              icon: const Icon(FluentIcons.book_24_regular),
              label: const Text('בחר מפרש'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onHideColumn,
              icon: const Icon(FluentIcons.eye_off_24_regular, size: 18),
              label: const Text('הסתר טור זה'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// פתיחת דיאלוג בחירת מפרש לטור ספציפי
  Future<void> _openCommentatorSelector(String column) async {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) {
      return;
    }

    // קבלת רשימת המפרשים הזמינים
    final availableCommentators = state.links
        .where((link) => LinkTypes.isCommentaryOrTargum(link.connectionType))
        .map((link) => utils.getTitleFromPath(link.path2))
        .toSet()
        .toList();

    if (availableCommentators.isEmpty) {
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => PageShapeSettingsDialog(
        availableCommentators: availableCommentators,
        bookTitle: state.book.title,
        heCategories: state.book.heCategories,
        currentLeft: _leftCommentator,
        currentRight: _rightCommentator,
        currentBottom: _bottomCommentator,
        currentBottomRight: _bottomRightCommentator,
      ),
    );

    // אם היו שינויים, טען מחדש את ההגדרות
    if (result == true) {
      _loadConfiguration();
    }
  }

  @override
  Widget build(BuildContext context) {
    // עוטפים את המסך ב-BlocListener כדי להאזין לשינויים בטעינת הקישורים
    return BlocListener<TextBookBloc, TextBookState>(
      listenWhen: (previous, current) {
        // אנחנו רוצים להגיב רק כאשר רשימת הקישורים (links) משתנה,
        // למשל כשהיא מסיימת להיטען ועוברת מ-0 קישורים לרשימה מלאה.
        if (previous is TextBookLoaded && current is TextBookLoaded) {
          return previous.links.length != current.links.length;
        }
        // גם אם המצב הקודם לא היה TextBookLoaded ועכשיו כן
        return previous is! TextBookLoaded && current is TextBookLoaded;
      },
      listener: (context, state) {
        if (state is TextBookLoaded && state.links.isNotEmpty) {
          debugPrint(
              '📖 PageShape: Links loaded (${state.links.length}), reloading configuration...');
          // קריאה חוזרת לפונקציה שתשדך את המפרשים השמורים לקישורים שהרגע נטענו
          _loadConfiguration();
        }
      },
      child: _isLoadingConfig
          ? const Scaffold(
              body: LoadingIndicator(),
            )
          : TextBookStateBuilder(
              loadingWidget: const Scaffold(
                body: LoadingIndicator(),
              ),
              builder: (context, state) {
                return Scaffold(
                  body: Column(
                    children: [
                      // Main Content Row - מתרחב לפי השטח הפנוי
                      Expanded(
                        child: Row(
                          children: [
                            // Left Commentary with label (label on outer edge - first in RTL)
                            if (_columnVisibility['left'] == true) ...[
                              if (_leftCommentator != null) ...[
                                SizedBox(
                                  width: 20,
                                  child: Center(
                                    child: RotatedBox(
                                      quarterTurns: 1,
                                      child: Text(
                                        _leftCommentator!,
                                        style: const TextStyle(
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                SizedBox(
                                  width: _leftWidth ??
                                      MediaQuery.of(context).size.width *
                                          _kCommentaryPaneWidthFactor,
                                  child: _CommentaryPane(
                                    commentatorName: _leftCommentator!,
                                    openBookCallback: widget.openBookCallback,
                                  ),
                                ),
                              ] else ...[
                                // מצב ריק - אין מפרש נבחר
                                SizedBox(
                                  width: _leftWidth ??
                                      MediaQuery.of(context).size.width *
                                          _kCommentaryPaneWidthFactor,
                                  child: _buildEmptyColumnContent(
                                    columnName: 'left',
                                    onSelectCommentator: () =>
                                        _openCommentatorSelector('left'),
                                    onHideColumn: () => _hideColumn('left'),
                                  ),
                                ),
                              ],
                              ResizableDragHandle(
                                isVertical: true,
                                showDivider: false,
                                onDragDelta: (delta) {
                                  setState(() {
                                    _leftWidth = ((_leftWidth ?? 0) - delta)
                                        .clamp(
                                            80.0,
                                            MediaQuery.of(context).size.width *
                                                0.4);
                                  });
                                },
                                onDragEnd: _saveSizes,
                              ),
                            ],
                            // Main Text - מתרחב לפי השטח הפנוי
                            Expanded(
                              child: SimpleTextViewer(
                                content: state.content,
                                fontSize: state.fontSize,
                                openBookCallback: widget.openBookCallback,
                                scrollController: state.scrollController,
                                positionsListener: state.positionsListener,
                                isMainText: true,
                              ),
                            ),
                            // Right Commentary with label (label on outer edge - last in RTL)
                            if (_columnVisibility['right'] == true) ...[
                              ResizableDragHandle(
                                isVertical: true,
                                showDivider: false,
                                onDragDelta: (delta) {
                                  setState(() {
                                    _rightWidth = ((_rightWidth ?? 0) + delta)
                                        .clamp(
                                            80.0,
                                            MediaQuery.of(context).size.width *
                                                0.4);
                                  });
                                },
                                onDragEnd: _saveSizes,
                              ),
                              if (_rightCommentator != null) ...[
                                SizedBox(
                                  width: _rightWidth ??
                                      MediaQuery.of(context).size.width *
                                          _kCommentaryPaneWidthFactor,
                                  child: _CommentaryPane(
                                    commentatorName: _rightCommentator!,
                                    openBookCallback: widget.openBookCallback,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                SizedBox(
                                  width: 20,
                                  child: Center(
                                    child: RotatedBox(
                                      quarterTurns: 3,
                                      child: Text(
                                        _rightCommentator!,
                                        style: const TextStyle(
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ] else ...[
                                // מצב ריק - אין מפרש נבחר
                                SizedBox(
                                  width: _rightWidth ??
                                      MediaQuery.of(context).size.width *
                                          _kCommentaryPaneWidthFactor,
                                  child: _buildEmptyColumnContent(
                                    columnName: 'right',
                                    onSelectCommentator: () =>
                                        _openCommentatorSelector('right'),
                                    onHideColumn: () => _hideColumn('right'),
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),

                      // Bottom Commentary
                      if (_bottomCommentator != null ||
                          _bottomRightCommentator != null) ...[
                        // מפריד אופקי לגרירה עם קווים באמצע
                        _HorizontalDragHandle(
                          leftWidth: _leftWidth,
                          rightWidth: _rightWidth,
                          leftCommentator: _leftCommentator,
                          rightCommentator: _rightCommentator,
                          onPanUpdate: (details) {
                            setState(() {
                              _bottomHeight = ((_bottomHeight ?? 0) -
                                      details.delta.dy)
                                  .clamp(80.0,
                                      MediaQuery.of(context).size.height * 0.5);
                            });
                          },
                          onPanEnd: _saveSizes,
                        ),
                        SizedBox(
                          height: _bottomHeight ??
                              MediaQuery.of(context).size.height * 0.27,
                          child: Column(
                            children: [
                              Expanded(
                                child: _bottomRightCommentator != null
                                    ? Row(
                                        children: [
                                          if (_bottomCommentator != null) ...[
                                            SizedBox(
                                              width: 20,
                                              child: Center(
                                                child: RotatedBox(
                                                  quarterTurns: 1,
                                                  child: Text(
                                                    _bottomCommentator!,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: _CommentaryPane(
                                                commentatorName:
                                                    _bottomCommentator!,
                                                openBookCallback:
                                                    widget.openBookCallback,
                                                isBottom: true,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                          ],
                                          Expanded(
                                            child: _CommentaryPane(
                                              commentatorName:
                                                  _bottomRightCommentator!,
                                              openBookCallback:
                                                  widget.openBookCallback,
                                              isBottom: true,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          SizedBox(
                                            width: 20,
                                            child: Center(
                                              child: RotatedBox(
                                                quarterTurns: 3,
                                                child: Text(
                                                  _bottomRightCommentator!,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Row(
                                        children: [
                                          SizedBox(
                                            width: 20,
                                            child: Center(
                                              child: RotatedBox(
                                                quarterTurns: 1,
                                                child: Text(
                                                  _bottomCommentator!,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: _CommentaryPane(
                                              commentatorName:
                                                  _bottomCommentator!,
                                              openBookCallback:
                                                  widget.openBookCallback,
                                              isBottom: true,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// חלונית מפרש - טוענת ומציגה את הספר של המפרש
class _CommentaryPane extends StatefulWidget {
  final String commentatorName;
  final Function(OpenedTab) openBookCallback;
  final bool isBottom; // האם זה מפרש תחתון

  const _CommentaryPane({
    required this.commentatorName,
    required this.openBookCallback,
    this.isBottom = false,
  });

  @override
  State<_CommentaryPane> createState() => _CommentaryPaneState();
}

class _CommentaryPaneState extends State<_CommentaryPane> {
  List<String>? _content;
  bool _isLoading = true;
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _positionsListener =
      ItemPositionsListener.create();
  List<Link> _relevantLinks = [];
  int? _lastSyncedIndex; // האינדקס האחרון שסונכרן
  StreamSubscription<TextBookState>? _blocSubscription;
  Set<int> _highlightedIndices = {}; // אינדקסים להדגשה
  bool _highlightEnabled = false;

  @override
  void initState() {
    super.initState();
    // דוחה את הטעינה כדי לוודא שכל ה-providers מוכנים וה-bloc זמין
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadCommentary();
        _setupBlocListener();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // הסרנו את הקריאה מכאן כדי למנוע כפילות או בעיות context מוקדמות
  }

  @override
  void didUpdateWidget(_CommentaryPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    // אם שם המפרש השתנה, טען מחדש את התוכן
    if (oldWidget.commentatorName != widget.commentatorName) {
      _loadCommentary();
    } else {
      // אם המפרש לא השתנה, רק עדכן הדגשות
      _updateHighlightSettings();
    }
  }

  @override
  void dispose() {
    _blocSubscription?.cancel();
    super.dispose();
  }

  /// עדכון הגדרות הדגשה
  void _updateHighlightSettings() {
    final state = context.read<TextBookBloc>().state;
    if (state is TextBookLoaded) {
      final newHighlightEnabled =
          PageShapeSettingsManager.getHighlightSetting(state.book.title);
      final highlightChanged = newHighlightEnabled != _highlightEnabled;
      _highlightEnabled = newHighlightEnabled;
      // עדכון הדגשות - גם בטעינה ראשונית וגם כשההגדרה משתנה
      if (highlightChanged || _highlightedIndices.isEmpty) {
        _updateHighlights(state);
      }
    }
  }

  /// הגדרת מאזין לשינויים ב-Bloc
  void _setupBlocListener() {
    // טעינת הגדרת הדגשה ראשונית
    _updateHighlightSettings();

    // סנכרון ראשוני עם ה-state הנוכחי
    final currentState = context.read<TextBookBloc>().state;
    if (currentState is TextBookLoaded && mounted) {
      // נדחה מעט כדי לוודא שה-ScrollController מוכן
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _syncWithMainText(currentState);
        }
      });
    }

    _blocSubscription = context.read<TextBookBloc>().stream.listen((state) {
      if (state is TextBookLoaded && mounted) {
        _syncWithMainText(state);
        _updateHighlights(state);
      }
    });
  }

  void _updateHighlights(TextBookLoaded state) {
    if (!_highlightEnabled || state.selectedIndex == null) {
      if (_highlightedIndices.isNotEmpty) {
        setState(() {
          _highlightedIndices = {};
        });
      }
      return;
    }

    // חישוב האינדקס הלוגי
    final logicalIndex = CommentarySyncHelper.getLogicalIndex(
      state.selectedIndex!,
      state.content,
    );
    final mainLineNumber = logicalIndex + 1;

    // מציאת כל הקישורים לשורה זו והמרה ישירה ל-Set
    final newHighlights = _relevantLinks
        .where((link) => link.index1 == mainLineNumber)
        .map((link) => link.index2 - 1)
        .toSet();

    if (!const SetEquality().equals(newHighlights, _highlightedIndices)) {
      setState(() {
        _highlightedIndices = newHighlights;
      });
    }
  }

  Future<void> _loadCommentary() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // המתנה לכך שה-state יהיה TextBookLoaded
      final bloc = context.read<TextBookBloc>();
      var state = bloc.state;

      // אם ה-state עדיין לא TextBookLoaded, נחכה לו
      if (state is! TextBookLoaded) {
        try {
          state = await bloc.stream
              .firstWhere(
                (s) => s is TextBookLoaded,
                orElse: () => state,
              )
              .timeout(const Duration(seconds: 5));
        } catch (e) {
          debugPrint('⚠️ CommentaryPane: Timeout waiting for TextBookLoaded');
        }
      }

      if (!mounted) return;

      if (state is TextBookLoaded) {
        // סינון קישורים לפי שם המפרש ולפי סוג הקישור (COMMENTARY/TARGUM)
        _relevantLinks = state.links.where((link) {
          final linkTitle = utils.getTitleFromPath(link.path2);
          return linkTitle == widget.commentatorName &&
              LinkTypes.isCommentaryOrTargum(link.connectionType);
        }).toList();
      }

      // מציאת הספר המלא של המפרש עם categoryId
      TextBook book;
      final bookLocation = await BookLocator.locateBook(widget.commentatorName);

      if (bookLocation != null &&
          bookLocation.book != null &&
          bookLocation.categoryId != null) {
        // נמצא ספר ב-DB - נשתמש בנתונים שלו
        final dbBook = bookLocation.book!;

        // נצטרך למצוא את ה-categoryPath מה-DB
        final repository = SqliteDataProvider.instance.repository;
        String? categoryPath;
        if (repository != null) {
          try {
            var category = await repository.getCategory(dbBook.categoryId);
            if (category != null) {
              // בניית נתיב הקטגוריה
              final pathParts = <String>[];
              while (category != null) {
                pathParts.insert(0, category.title);
                if (category.parentId != null) {
                  category = await repository.getCategory(category.parentId!);
                } else {
                  break;
                }
              }
              categoryPath = pathParts.join(', ');
            }
          } catch (e) {
            debugPrint('⚠️ CommentaryPane: Error getting category path: $e');
          }
        }

        book = TextBook(
          title: widget.commentatorName,
          categoryId: bookLocation.categoryId,
          categoryPath: categoryPath,
        );
      } else {
        // ננסה למצוא את ה-categoryPath מהקישורים הקיימים
        String? categoryPath;
        if (_relevantLinks.isNotEmpty) {
          // נחלץ את ה-categoryPath מהקישור הראשון
          final firstLinkPath = _relevantLinks.first.path2;
          var normalizedPath = firstLinkPath;
          if (normalizedPath.startsWith('/') ||
              normalizedPath.startsWith('\\')) {
            normalizedPath = normalizedPath.substring(1);
          }

          final lastSeparatorIndex = normalizedPath.lastIndexOf('/');
          if (lastSeparatorIndex != -1) {
            final directoryPath =
                normalizedPath.substring(0, lastSeparatorIndex);
            categoryPath =
                directoryPath.replaceAll('/', ', ').replaceAll('\\', ', ');
          }
        }

        // יצירת ספר עם categoryPath (שיומר ל-categoryId באמצעות hashCode)
        if (categoryPath != null && categoryPath.isNotEmpty) {
          final categoryId = categoryPath.hashCode;
          book = TextBook(
            title: widget.commentatorName,
            categoryPath: categoryPath,
            categoryId: categoryId,
          );
        } else {
          // fallback - ספר ללא categoryId (לא יטען קישורים)
          debugPrint(
              '⚠️ CommentaryPane: No categoryId found for "${widget.commentatorName}"');
          book = TextBook(title: widget.commentatorName);
        }
      }

      // טעינת הטקסט ישירות מה-provider המתאים
      String bookContent;
      if (bookLocation != null &&
          bookLocation.book != null &&
          bookLocation.categoryId != null) {
        // ספר מה-DB - נשתמש ב-DatabaseLibraryProvider
        final dbProvider = LibraryProviderManager.instance.databaseProvider;
        final text = await dbProvider.getBookText(
          widget.commentatorName,
          bookLocation.categoryId!,
          'txt',
        );
        bookContent = text ?? '';
      } else {
        // ספר ממערכת הקבצים - נשתמש ב-book.text
        bookContent = await book.text;
      }

      if (bookContent.isEmpty) {
        debugPrint(
            '❌ CommentaryPane: Book text is empty for "${widget.commentatorName}"');
        throw Exception('Book text is empty for "${widget.commentatorName}"');
      }

      final lines = bookContent.split('\n');

      if (!mounted) return;

      setState(() {
        _content = lines;
        _isLoading = false;
        _lastSyncedIndex = null; // איפוס לסנכרון ראשוני
      });

      // סנכרון ראשוני - נדחה מעט כדי לוודא שה-ScrollController מוכן
      final currentState = state;
      if (currentState is TextBookLoaded) {
        // נחכה שה-widget יבנה ואז נסנכרן
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _syncWithMainText(currentState);
          }
        });
        // ניסיון סנכרון נוסף אחרי זמן קצר (למקרה שה-ScrollController לא היה מוכן)
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && _lastSyncedIndex == null) {
            final bloc = context.read<TextBookBloc>();
            if (bloc.state is TextBookLoaded) {
              _syncWithMainText(bloc.state as TextBookLoaded);
            }
          }
        });
      }
    } catch (e) {
      debugPrint(
          '❌ CommentaryPane: Error loading "${widget.commentatorName}": $e');
      if (mounted) {
        setState(() {
          _content = null;
          _isLoading = false;
        });
      }
    }
  }

  /// סנכרון המפרש עם הטקסט הראשי
  void _syncWithMainText(TextBookLoaded state) {
    // אם אין תוכן או אין קישורים - אין מה לסנכרן
    if (_content == null || _content!.isEmpty || _relevantLinks.isEmpty) {
      return;
    }

    // אם ה-ScrollController עדיין לא מחובר, נדחה את הסנכרון
    if (!_scrollController.isAttached) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _syncWithMainText(state);
        }
      });
      return;
    }

    // קביעת האינדקס הנוכחי בטקסט הראשי
    // נעדיף את visibleIndices כי זה המיקום האמיתי בגלילה
    int currentMainIndex;
    if (state.visibleIndices.isNotEmpty) {
      currentMainIndex = state.visibleIndices.first;
    } else if (state.selectedIndex != null) {
      currentMainIndex = state.selectedIndex!;
    } else {
      return; // אין מידע על מיקום נוכחי
    }

    // חישוב האינדקס הלוגי (עם טיפול בכותרות)
    final logicalIndex = CommentarySyncHelper.getLogicalIndex(
      currentMainIndex,
      state.content,
    );

    // מציאת הקישור הטוב ביותר
    final bestLink = CommentarySyncHelper.findBestLink(
      linksForCommentary: _relevantLinks,
      logicalMainIndex: logicalIndex,
    );

    // חישוב האינדקס היעד במפרש
    final targetIndex = CommentarySyncHelper.getCommentaryTargetIndex(bestLink);

    // אם אין קישור - לא מזיזים את המפרש
    if (targetIndex == null) {
      return;
    }

    // אם כבר סונכרנו לאינדקס הזה - לא צריך לגלול שוב
    if (targetIndex == _lastSyncedIndex) {
      return;
    }

    // גלילה למיקום הנכון במפרש
    if (targetIndex >= 0 &&
        targetIndex < _content!.length &&
        _scrollController.isAttached) {
      _scrollController.scrollTo(
        index: targetIndex,
        duration: const Duration(milliseconds: 300),
        alignment: 0.0, // בראש החלון
      );
      _lastSyncedIndex = targetIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_content == null || _content!.isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Text(
            'לא ניתן לטעון את ${widget.commentatorName}',
            style: const TextStyle(fontSize: 14),
          ),
        ),
      );
    }

    return TextBookStateBuilder(
      loadingWidget: const SizedBox(),
      builder: (context, state) {
        // ניסיון סנכרון נוסף כשה-widget נבנה (במקרה שהסנכרון הראשוני נכשל)
        if (_lastSyncedIndex == null && _scrollController.isAttached) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _syncWithMainText(state);
            }
          });
        }

        return BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            // מפרשים תחתונים משתמשים בגופן מההגדרות, עליונים בגופן הרגיל
            final bottomFont =
                Settings.getValue<String>('page_shape_bottom_font') ??
                    AppFonts.defaultFont;
            final fontFamily = widget.isBottom
                ? bottomFont
                : settingsState.commentatorsFontFamily;
            final commentaryFontSize =
                PageShapeSettingsManager.getCommentaryFontSize();
            return SimpleTextViewer(
              content: _content!,
              fontSize: commentaryFontSize,
              fontFamily: fontFamily,
              openBookCallback: widget.openBookCallback,
              scrollController: _scrollController,
              positionsListener: _positionsListener,
              isMainText: false,
              bookTitle: widget.commentatorName, // לפתיחה בטאב נפרד
              highlightedIndices: _highlightedIndices, // הדגשות מקומיות
              onCommentatorChanged: _reloadCommentary, // callback לרענון
            );
          },
        );
      },
    );
  }

  /// טעינה מחדש של המפרש (אחרי החלפה)
  void _reloadCommentary() {
    // נטען מחדש את ההגדרות מה-parent
    if (mounted) {
      // נאלץ את ה-parent לטעון מחדש את ההגדרות
      final parentState =
          context.findAncestorStateOfType<_PageShapeScreenState>();
      if (parentState != null) {
        parentState._loadConfiguration();
      }
    }
  }
}

/// ידית גרירה אופקית מותאמת אישית עם קווים מתחת למפרשים העליונים
class _HorizontalDragHandle extends StatelessWidget {
  final double? leftWidth;
  final double? rightWidth;
  final String? leftCommentator;
  final String? rightCommentator;
  final ValueChanged<DragUpdateDetails> onPanUpdate;
  final VoidCallback onPanEnd;

  const _HorizontalDragHandle({
    this.leftWidth,
    this.rightWidth,
    this.leftCommentator,
    this.rightCommentator,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  @override
  Widget build(BuildContext context) {
    Widget buildDividerLine(double? width) {
      return SizedBox(
        width: (width ??
                MediaQuery.of(context).size.width *
                    _kCommentaryPaneWidthFactor) +
            _kCommentaryLabelAndSpacingWidth,
        child: Center(
          child: FractionallySizedBox(
            widthFactor: 0.5,
            child: Container(
              height: 1,
              color: Theme.of(context).dividerColor,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 16,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // קווים מתחת למפרשים העליונים - באמצע הרווח
          Row(
            children: [
              if (leftCommentator != null) buildDividerLine(leftWidth),
              const Spacer(),
              if (rightCommentator != null) buildDividerLine(rightWidth),
            ],
          ),
          // אזור גרירה שקוף על כל הרוחב
          Positioned.fill(
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeRow,
              child: GestureDetector(
                onPanUpdate: onPanUpdate,
                onPanEnd: (_) => onPanEnd(),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
