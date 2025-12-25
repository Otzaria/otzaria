import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/constants/fonts.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_settings_dialog.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/text_book/view/page_shape/utils/default_commentators.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/text_book/view/page_shape/utils/commentary_sync_helper.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'dart:async';

/// רוחב קבוע לחלון פרשנויות
const double _kCommentaryPaneWidthFactor = 0.17;

/// רוחב התווית המסובבת + ריווחים (20 תווית + 4 ריווח + 6 פדינג)
const double _kCommentaryLabelAndSpacingWidth = 30.0;

/// מסך תצוגת צורת דף - מציג את הטקסט המרכזי עם פרשנויות מסביב
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadConfiguration();
  }

  Future<void> _loadConfiguration() async {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;

    final config = PageShapeSettingsManager.loadConfiguration(state.book.title);

    if (config != null) {
      if (mounted) {
        setState(() {
          _leftCommentator = config['left'];
          _rightCommentator = config['right'];
          _bottomCommentator = config['bottom'];
          _bottomRightCommentator = config['bottomRight'];
        });
      }
    } else {
      // אם אין הגדרה קיימת, השתמש בברירות מחדל
      final defaults = await DefaultCommentators.getDefaults(state.book);
      if (mounted) {
        setState(() {
          _leftCommentator = defaults['left'];
          _rightCommentator = defaults['right'];
          _bottomCommentator = defaults['bottom'];
          _bottomRightCommentator = defaults['bottomRight'];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TextBookBloc, TextBookState>(
      builder: (context, state) {
        if (state is! TextBookLoaded) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          body: Stack(
            children: [
              Column(
                children: [
                  // Main Content Row - השורה עם הטקסט הראשי
                  Expanded(
                    child: Row(
                      children: [
                        // Left Commentary with label (label on outer edge - first in RTL)
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
                            width: MediaQuery.of(context).size.width *
                                _kCommentaryPaneWidthFactor,
                            child: _CommentaryPane(
                              commentatorName: _leftCommentator!,
                              openBookCallback: widget.openBookCallback,
                            ),
                          ),
                          const _ResizableDivider(
                            isVertical: true,
                          ),
                        ],
                        // Main Text - השורה עם הטקסט הראשי
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
                        if (_rightCommentator != null) ...[
                          const _ResizableDivider(
                            isVertical: true,
                          ),
                          SizedBox(
                            width: MediaQuery.of(context).size.width *
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
                        ],
                      ],
                    ),
                  ),
                  // Bottom Commentary - תופסת כרבע על 27% מהמסך
                  if (_bottomCommentator != null ||
                      _bottomRightCommentator != null) ...[
                    // קווים מתחת לפרשנויות הצדדיות - מבדיל הריווח
                    SizedBox(
                      height: 16,
                      child: Row(
                        children: [
                          // קו מתחת לפרשן השמאלי
                          if (_leftCommentator != null)
                            SizedBox(
                              width: MediaQuery.of(context).size.width *
                                      _kCommentaryPaneWidthFactor +
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
                            ),
                          const Spacer(),
                          // קו מתחת לפרשן הימני
                          if (_rightCommentator != null)
                            SizedBox(
                              width: MediaQuery.of(context).size.width *
                                      _kCommentaryPaneWidthFactor +
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
                            ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.27,
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
                                        const _ResizableDivider(
                                          isVertical: true,
                                        ),
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
                                          commentatorName: _bottomCommentator!,
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
              // Settings button - כפתור הגדרות צף בפינה של המסך
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(230),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(25),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.settings, size: 18),
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    onPressed: () async {
                      final hadChanges = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => PageShapeSettingsDialog(
                          availableCommentators: state.availableCommentators,
                          bookTitle: state.book.title,
                          currentLeft: _leftCommentator,
                          currentRight: _rightCommentator,
                          currentBottom: _bottomCommentator,
                          currentBottomRight: _bottomRightCommentator,
                        ),
                      );
                      // טעינה מחדש אם היו שינויים
                      if (hadChanges == true && mounted) {
                        _loadConfiguration();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// חלונית פרשן - מציגה ומסנכרנת את הפירוש על הפרשן
class _CommentaryPane extends StatefulWidget {
  final String commentatorName;
  final Function(OpenedTab) openBookCallback;
  final bool isBottom; // האם זה פרשן תחתון

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
  }

  @override
  void dispose() {
    _blocSubscription?.cancel();
    super.dispose();
  }

  /// הגדרת מאזין לשינויים ב-Bloc
  void _setupBlocListener() {
    _blocSubscription = context.read<TextBookBloc>().stream.listen((state) {
      if (state is TextBookLoaded && mounted) {
        _syncWithMainText(state);
      }
    });
  }

  Future<void> _loadCommentary() async {
    setState(() => _isLoading = true);

    try {
      final book = TextBook(title: widget.commentatorName);
      final bookContent = await book.text;
      final lines = bookContent.split('\n');

      if (!mounted) return;

      // טעינת הקישורים הרלוונטיים לפרשן זה
      final state = context.read<TextBookBloc>().state;
      if (state is TextBookLoaded) {
        // סינון קישורים רק של הפרשן ורק מסוג הקישור (commentary/targum)
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

  /// סנכרון הפרשן עם הטקסט הראשי
  void _syncWithMainText(TextBookLoaded state) {
    // אם אין תוכן או אין קישורים - אין מה לסנכרן
    if (_content == null || _content!.isEmpty || _relevantLinks.isEmpty) {
      return;
    }

    // קבלת האינדקס הנוכחי מהטקסט הראשי
    int currentMainIndex;
    if (state.selectedIndex != null) {
      currentMainIndex = state.selectedIndex!;
    } else if (state.visibleIndices.isNotEmpty) {
      currentMainIndex = state.visibleIndices.first;
    } else {
      return; // אין מידע על מיקום נוכחי
    }

    // חישוב האינדקס הלוגי (על פיסוק בטקסט)
    final logicalIndex = CommentarySyncHelper.getLogicalIndex(
      currentMainIndex,
      state.content,
    );

    // מציאת הקישור הטוב ביותר
    final bestLink = CommentarySyncHelper.findBestLink(
      linksForCommentary: _relevantLinks,
      logicalMainIndex: logicalIndex,
    );

    // חישוב האינדקס היעד בפרשן
    final targetIndex = CommentarySyncHelper.getCommentaryTargetIndex(bestLink);

    // אם אין קישור - לא מצליחים את הפרשן
    if (targetIndex == null) {
      return;
    }

    // אם כבר סונכרנו לאינדקס הזה - לא צריך לעדכן עוד
    if (targetIndex == _lastSyncedIndex) {
      return;
    }

    // גלילה למיקום הנכון בפרשן
    if (targetIndex >= 0 &&
        targetIndex < _content!.length &&
        _scrollController.isAttached) {
      _scrollController.scrollTo(
        index: targetIndex,
        duration: const Duration(milliseconds: 300),
        alignment: 0.0, // בראש הקובץ
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

    return BlocBuilder<TextBookBloc, TextBookState>(
      builder: (context, state) {
        if (state is! TextBookLoaded) {
          return const SizedBox();
        }

        return BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            // פרשנויות תחתונות משתמשות בפונט מההגדרות, צדדיות בפונט הרגיל
            final bottomFont =
                Settings.getValue<String>('page_shape_bottom_font') ??
                    AppFonts.defaultFont;
            final fontFamily = widget.isBottom
                ? bottomFont
                : settingsState.commentatorsFontFamily;
            return SimpleTextViewer(
              content: _content!,
              fontSize: 16, // גודל קבוע לפרשנויות בצורת דף
              fontFamily: fontFamily,
              openBookCallback: widget.openBookCallback,
              scrollController: _scrollController,
              positionsListener: _positionsListener,
              isMainText: false,
              bookTitle: widget.commentatorName, // להעברה לחיפוש נכון
            );
          },
        );
      },
    );
  }
}

class _ResizableDivider extends StatefulWidget {
  final bool isVertical;

  /// אם null, המפריד יהיה רק ויזואלי ללא אפשרות גרירה
  final Function(double)? onDrag;

  const _ResizableDivider({
    required this.isVertical,
    // ignore: unused_element_parameter
    this.onDrag,
  });

  @override
  State<_ResizableDivider> createState() => _ResizableDividerState();
}

class _ResizableDividerState extends State<_ResizableDivider> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    // אם אין onDrag, מציגים מפריד פשוט ללא אינטראקציה
    if (widget.onDrag == null) {
      return Container(
        width: widget.isVertical ? 8 : null,
        height: widget.isVertical ? null : 8,
        color: Colors.transparent,
      );
    }

    return MouseRegion(
      cursor: widget.isVertical
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onPanUpdate: (details) {
          widget.onDrag!(
            widget.isVertical ? details.delta.dx : details.delta.dy,
          );
        },
        child: Container(
          width: widget.isVertical ? 8 : null,
          height: widget.isVertical ? null : 8,
          color: _isHovered
              ? Colors.grey.withValues(alpha: 0.3)
              : Colors.transparent,
          child: _isHovered
              ? Center(
                  child: Container(
                    width: widget.isVertical ? 2 : null,
                    height: widget.isVertical ? null : 2,
                    color: Colors.grey,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
