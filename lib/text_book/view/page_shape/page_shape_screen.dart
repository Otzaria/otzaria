import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/resizable_drag_handle.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:collection/collection.dart';
import 'dart:async';

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
    if (state is! TextBookLoaded) return;

    final config = PageShapeSettingsManager.loadConfiguration(
      state.book.title,
      heCategories: state.book.heCategories,
    );
    _columnVisibility =
        PageShapeSettingsManager.getColumnVisibility(state.book.title);

    final Map<String, String?> commentators;
    if (config != null) {
      // יש הגדרה שמורה - להשתמש בה (גם אם ריקה)
      commentators = config;
    } else {
      // אין הגדרה שמורה בכלל - השתמש בברירות מחדל
      commentators = await DefaultCommentators.getDefaults(state.book, links: state.links);
    }

    if (mounted) {
      setState(() {
        _leftCommentator = commentators['left'];
        _rightCommentator = commentators['right'];
        _bottomCommentator = commentators['bottom'];
        _bottomRightCommentator = commentators['bottomRight'];
        _isLoadingConfig = false;
      });
    }
  }

  /// הסתרת טור
  void _hideColumn(String column) {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;

    setState(() {
      _columnVisibility[column] = false;
    });
    
    // שמירה גלובלית אלא אם יש הגדרות פר-ספר
    final hasBookSettings = PageShapeSettingsManager.hasBookSpecificSettings(state.book.title);
    PageShapeSettingsManager.saveColumnVisibility(
        state.book.title, _columnVisibility, saveAsGlobal: !hasBookSettings);
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
              icon: const Icon(Icons.book_outlined),
              label: const Text('בחר מפרש'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onHideColumn,
              icon: const Icon(Icons.visibility_off_outlined, size: 18),
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
    if (state is! TextBookLoaded) return;

    // קבלת רשימת המפרשים הזמינים
    final availableCommentators = state.links
        .where((link) =>
            link.connectionType == 'commentary' ||
            link.connectionType == 'targum')
        .map((link) => utils.getTitleFromPath(link.path2))
        .toSet()
        .toList();

    if (availableCommentators.isEmpty) return;

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
    if (_isLoadingConfig) {
      return const Scaffold(
        body: LoadingIndicator(),
      );
    }

    return TextBookStateBuilder(
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
                            _leftWidth = ((_leftWidth ?? 0) - delta).clamp(
                                80.0, MediaQuery.of(context).size.width * 0.4);
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
                            _rightWidth = ((_rightWidth ?? 0) + delta).clamp(
                                80.0, MediaQuery.of(context).size.width * 0.4);
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
                      _bottomHeight =
                          ((_bottomHeight ?? 0) - details.delta.dy)
                              .clamp(80.0, MediaQuery.of(context).size.height * 0.5);
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
                                        commentatorName: _bottomCommentator!,
                                        openBookCallback:
                                            widget.openBookCallback,
                                        isBottom: true,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Expanded(
                                    child: _CommentaryPane(
                                      commentatorName: _bottomRightCommentator!,
                                      openBookCallback: widget.openBookCallback,
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
                                      commentatorName: _bottomCommentator!,
                                      openBookCallback: widget.openBookCallback,
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
    _loadCommentary();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // הגדרת המאזין רק פעם אחת
    if (_blocSubscription == null) {
      _setupBlocListener();
    }
  }

  @override
  void didUpdateWidget(_CommentaryPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.commentatorName != widget.commentatorName) {
      _loadCommentary();
    }
    _updateHighlightSettings();
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
    setState(() => _isLoading = true);

    try {
      final book = TextBook(title: widget.commentatorName);
      final bookContent = await book.text;
      final lines = bookContent.split('\n');

      if (!mounted) return;

      // טעינת הקישורים הרלוונטיים למפרש זה
      final state = context.read<TextBookBloc>().state;
      if (state is TextBookLoaded) {
        // סינון קישורים לפי שם המפרש ולפי סוג הקישור (commentary/targum)
        _relevantLinks = state.links.where((link) {
          final linkTitle = utils.getTitleFromPath(link.path2);
          return linkTitle == widget.commentatorName &&
              (link.connectionType == 'commentary' ||
                  link.connectionType == 'targum');
        }).toList();
      }

      if (mounted) {
        setState(() {
          _content = lines;
          _isLoading = false;
          _lastSyncedIndex = null; // איפוס לסנכרון ראשוני
        });

        // סנכרון ראשוני
        if (state is TextBookLoaded) {
          _syncWithMainText(state);
        }
      }
    } catch (e) {
      debugPrint('Error loading commentary ${widget.commentatorName}: $e');
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

    // קביעת האינדקס הנוכחי בטקסט הראשי
    int currentMainIndex;
    if (state.selectedIndex != null) {
      currentMainIndex = state.selectedIndex!;
    } else if (state.visibleIndices.isNotEmpty) {
      currentMainIndex = state.visibleIndices.first;
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
        return BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            // מפרשים תחתונים משתמשים בגופן מההגדרות, עליונים בגופן הרגיל
            final bottomFont =
                Settings.getValue<String>('page_shape_bottom_font') ??
                    AppFonts.defaultFont;
            final fontFamily = widget.isBottom
                ? bottomFont
                : settingsState.commentatorsFontFamily;
            final commentaryFontSize = PageShapeSettingsManager.getCommentaryFontSize();
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
            );
          },
        );
      },
    );
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
