import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/view/tantivy_full_text_search.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/search/view/search_options_dropdown.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';

class EnhancedSearchField extends StatefulWidget {
  final dynamic widget;

  const EnhancedSearchField({super.key, required this.widget});

  SearchingTab get tab {
    // Support both TantivyFullTextSearch and _SearchDialogWrapper
    if (widget is TantivyFullTextSearch) {
      return (widget as TantivyFullTextSearch).tab;
    } else {
      // Assume it's _SearchDialogWrapper or similar with a tab property
      return widget.tab as SearchingTab;
    }
  }

  @override
  State<EnhancedSearchField> createState() => _EnhancedSearchFieldState();
}

// GlobalKey לגישה ל-State מבחוץ
final GlobalKey enhancedSearchFieldKey = GlobalKey();

class _EnhancedSearchFieldState extends State<EnhancedSearchField> {
  final GlobalKey _textFieldKey = GlobalKey();
  OverlayEntry? _searchOptionsOverlay;

  static const double _kSearchFieldMinWidth = 300;
  static const double _kControlHeight = 48;

  @override
  void initState() {
    super.initState();
    widget.tab.queryController.addListener(_onTextChanged);
    widget.tab.searchFieldFocusNode.addListener(_onCursorPositionChanged);
  }

  @override
  void deactivate() {
    debugPrint('⏸️ EnhancedSearchField deactivating - clearing overlays');
    _hideSearchOptionsOverlay();
    super.deactivate();
  }

  @override
  void dispose() {
    debugPrint('🗑️ EnhancedSearchField disposing');
    _hideSearchOptionsOverlay();
    widget.tab.queryController.removeListener(_onTextChanged);
    widget.tab.searchFieldFocusNode.removeListener(_onCursorPositionChanged);
    widget.tab.searchOptions.clear();
    super.dispose();
  }

  void _onTextChanged() {
    final bool drawerWasOpen = _searchOptionsOverlay != null;
    final text = widget.tab.queryController.text;

    // אם שדה החיפוש התרוקן, נקה הכל ונסגור את המגירה
    if (text.trim().isEmpty) {
      widget.tab.searchOptions.clear();
      if (drawerWasOpen) {
        _hideSearchOptionsOverlay();
        _notifyDropdownClosed();
      }
      return;
    }

    // עדכון המגירה אם היא פתוחה
    if (drawerWasOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateSearchOptionsOverlay();
      });
    }
  }

  void _onCursorPositionChanged() {
    // עדכון המגירה כשהסמן זז (אם היא פתוחה)
    if (_searchOptionsOverlay != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateSearchOptionsOverlay();
      });
    }
  }

  void _updateSearchOptionsOverlay() {
    // עדכון המגירה אם היא פתוחה
    if (_searchOptionsOverlay != null) {
      // שמירת מיקום הסמן לפני העדכון
      final currentSelection = widget.tab.queryController.selection;

      _hideSearchOptionsOverlay();
      _showSearchOptionsOverlay();

      // החזרת מיקום הסמן אחרי העדכון
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          debugPrint(
            'DEBUG: Restoring cursor position in update: ${currentSelection.baseOffset}',
          );
          widget.tab.queryController.selection = currentSelection;
        }
      });
    }
  }

  void _showSearchOptionsOverlay() {
    if (_searchOptionsOverlay != null) return;

    final currentSelection = widget.tab.queryController.selection;
    final overlayState = Overlay.of(context);
    final RenderBox? textFieldBox =
        _textFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (textFieldBox == null) return;
    final textFieldGlobalPosition = textFieldBox.localToGlobal(Offset.zero);

    _searchOptionsOverlay = OverlayEntry(
      builder: (context) {
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (PointerDownEvent event) {
            final clickPosition = event.position;
            final textFieldRect = Rect.fromLTWH(
              textFieldGlobalPosition.dx,
              textFieldGlobalPosition.dy,
              textFieldBox.size.width,
              textFieldBox.size.height,
            );

            // אזור המגירה המשוער - אנחנו לא יודעים את הגובה המדויק אז ניקח טווח סביר
            final drawerRect = Rect.fromLTWH(
              textFieldGlobalPosition.dx,
              textFieldGlobalPosition.dy + textFieldBox.size.height,
              textFieldBox.size.width,
              120.0, // גובה משוער מקסימלי לשתי שורות
            );

            if (!textFieldRect.contains(clickPosition) &&
                !drawerRect.contains(clickPosition)) {
              _hideSearchOptionsOverlay();
              _notifyDropdownClosed();
            }
          },
          child: Stack(
            children: [
              Positioned(
                left: textFieldGlobalPosition.dx,
                top: textFieldGlobalPosition.dy + textFieldBox.size.height,
                width: textFieldBox.size.width,
                // ======== התיקון מתחיל כאן ========
                child: AnimatedSize(
                  // 1. עוטפים ב-AnimatedSize
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: Container(
                    // height: 40.0, // 2. מסירים את הגובה הקבוע
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border(
                        left: BorderSide(color: Colors.grey.shade400, width: 1),
                        right: BorderSide(
                          color: Colors.grey.shade400,
                          width: 1,
                        ),
                        bottom: BorderSide(
                          color: Colors.grey.shade400,
                          width: 1,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: 48.0,
                        right: 16.0,
                        top: 8.0,
                        bottom: 8.0,
                      ),
                      child: _buildSearchOptionsContent(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    overlayState.insert(_searchOptionsOverlay!);

    // החזרת מיקום הסמן אחרי יצירת ה-overlay
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.tab.queryController.selection = currentSelection;
      }
    });

    // וידוא שה-overlay מוכן לקבל לחיצות
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ה-overlay כעת מוכן לקבל לחיצות
    });
  }

  // המילה הנוכחית (לפי מיקום הסמן)
  Map<String, dynamic>? _getCurrentWordInfo() {
    final text = widget.tab.queryController.text;
    final cursorPosition = widget.tab.queryController.selection.baseOffset;

    if (text.isEmpty || cursorPosition < 0) return null;

    final words = text.trim().split(RegExp(r'\s+'));
    int currentPos = 0;

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      if (word.isEmpty) continue;

      final wordStart = text.indexOf(word, currentPos);
      if (wordStart == -1) continue;
      final wordEnd = wordStart + word.length;

      if (cursorPosition >= wordStart && cursorPosition <= wordEnd) {
        return {'word': word, 'index': i, 'start': wordStart, 'end': wordEnd};
      }

      currentPos = wordEnd;
    }

    return null;
  }

  Widget _buildSearchOptionsContent() {
    final wordInfo = _getCurrentWordInfo();

    // אם אין מילה נוכחית, נציג הודעה המתאימה
    if (wordInfo == null ||
        wordInfo['word'] == null ||
        wordInfo['word'].isEmpty) {
      return const Center(
        child: Text(
          'הקלד או הצב את הסמן על מילה כלשהיא, כדי לבחור אפשרויות חיפוש',
          style: TextStyle(fontSize: 12, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

    return SearchOptionsRow(
      isVisible: true,
      currentWord: wordInfo['word'],
      wordIndex: wordInfo['index'],
      wordOptions: widget.tab.searchOptions,
      onOptionsChanged: _onSearchOptionsChanged,
      key: ValueKey(
        '${wordInfo['word']}_${wordInfo['index']}',
      ), // מפתח ייחודי לעדכון
    );
  }

  void _hideSearchOptionsOverlay() {
    _searchOptionsOverlay?.remove();
    _searchOptionsOverlay = null;
  }

  void _notifyDropdownClosed() {
    // עדכון מצב הכפתור כשהמגירה נסגרת מבחוץ
    setState(() {
      // זה יגרום לעדכון של הכפתור ב-build
    });
  }

  void _onSearchOptionsChanged() {
    // עדכון התצוגה כשמשתמש משנה אפשרויות
    setState(() {
      // זה יגרום לעדכון של התצוגה
    });

    // עדכון ה-notifier כדי שהתצוגה של מילות החיפוש תתעדכן
    widget.tab.searchOptionsChanged.value++;
  }

  void _performSearch() {
    final query = widget.tab.queryController.text.trim();
    if (query.isNotEmpty) {
      context.read<HistoryBloc>().add(AddHistory(widget.tab));
      context.read<SearchBloc>().add(
            UpdateSearchQuery(
              query,
              customSpacing: widget.tab.spacingValues,
              alternativeWords: widget.tab.alternativeWords,
              searchOptions: widget.tab.searchOptions,
            ),
          );
      widget.tab.isLeftPaneOpen.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<NavigationBloc, NavigationState>(
          listener: (context, state) {
            debugPrint('🔄 Navigation changed to: ${state.currentScreen}');
            // סגירת מגירת האפשרויות כשמשנים מסך
            if (_searchOptionsOverlay != null) {
              _hideSearchOptionsOverlay();
            }
          },
        ),
      ],
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (KeyEvent event) {
          // טיפול ב-Enter גם כשהפוקוס לא בתיבת החיפוש
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.enter &&
              !widget.tab.searchFieldFocusNode.hasFocus) {
            _performSearch();
          }
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: SizedBox(
                width: double.infinity,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: _kSearchFieldMinWidth,
                    minHeight: _kControlHeight,
                  ),
                  child: KeyboardListener(
                    focusNode: FocusNode(),
                    onKeyEvent: (KeyEvent event) {
                      // עדכון המגירה כשמשתמשים בחצים במקלדת
                      if (event is KeyDownEvent) {
                        final isArrowKey =
                            event.logicalKey.keyLabel == 'Arrow Left' ||
                                event.logicalKey.keyLabel == 'Arrow Right' ||
                                event.logicalKey.keyLabel == 'Arrow Up' ||
                                event.logicalKey.keyLabel == 'Arrow Down';

                        if (isArrowKey) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (_searchOptionsOverlay != null) {
                              _updateSearchOptionsOverlay();
                            }
                          });
                        }
                      }
                    },
                    child: RtlTextField(
                      focusNode: widget.tab.searchFieldFocusNode,
                      controller: widget.tab.queryController,
                      onChanged: (text) {
                        // עדכון המגירה כשהטקסט משתנה
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_searchOptionsOverlay != null) {
                            _updateSearchOptionsOverlay();
                          }
                        });
                      },
                      onSubmitted: (e) {
                        _performSearch();
                      },
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        hintText: "חפש כאן...",
                        labelText: "לחיפוש הקש אנטר או לחץ על סמל החיפוש",
                        prefixIcon: IconButton(
                          onPressed: _performSearch,
                          icon: const Icon(FluentIcons.search_24_regular),
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(FluentIcons.dismiss_24_regular),
                          onPressed: () {
                            // ניקוי מלא של כל הנתונים
                            widget.tab.queryController.clear();
                            widget.tab.searchOptions.clear();
                            context
                                .read<SearchBloc>()
                                .add(UpdateSearchQuery(''));
                            // ניקוי ספירות הפאסטים
                            context
                                .read<SearchBloc>()
                                .add(UpdateFacetCounts({}));
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // אזורי ריחוף הוסרו - לא נחוצים יותר
            // כפתורי ה+ וכפתורי המרווח הוסרו - עכשיו משתמשים בבקרים בדיאלוג
          ],
        ),
      ),
    );
  }
}
