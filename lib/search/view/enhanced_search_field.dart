import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/utils/category_query_parser.dart';
import 'package:otzaria/search/view/tantivy_full_text_search.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/search/view/search_options_dropdown.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

class EnhancedSearchField extends StatefulWidget {
  final dynamic widget;

  /// האם להציג את כפתור החיפוש המובנה בתוך השדה.
  final bool showInlineSearchButton;

  /// callback חיצוני שיופעל במקום לוגיקת החיפוש הפנימית כשמוגדר.
  /// משמש בדיאלוג החיפוש המתקדם כך ש-Enter מוליך לחיפוש הנכון.
  final VoidCallback? onSubmit;

  /// ווידג'ט נוסף שיוצג בתוך ה-suffixIcon (לפני כפתור המחיקה).
  /// משמש להוספת כפתורים כגון היסטוריה, בלי לגרום לחפיפה עם תוכן הטקסט.
  final Widget? trailingAction;

  const EnhancedSearchField({
    super.key,
    required this.widget,
    this.showInlineSearchButton = true,
    this.onSubmit,
    this.trailingAction,
  });

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
  final GlobalKey _searchOptionsOverlayKey = GlobalKey();
  OverlayEntry? _searchOptionsOverlay;
  double _searchOptionsOverlayHeight = 0;
  late final FocusNode _keyboardListenerFocusNode;
  late final FocusNode _textFieldKeyboardListenerFocusNode;

  static const double _kSearchFieldMinWidth = 300;
  static const double _kControlHeight = 48;

  @override
  void initState() {
    super.initState();
    _keyboardListenerFocusNode = FocusNode(
      debugLabel: 'enhanced_search_field_keyboard_listener',
      skipTraversal: true,
      canRequestFocus: false,
    );
    _textFieldKeyboardListenerFocusNode = FocusNode(
      debugLabel: 'enhanced_search_field_textfield_listener',
      skipTraversal: true,
      canRequestFocus: false,
    );
    _attachTabListeners(widget.tab);
  }

  void _attachTabListeners(SearchingTab tab) {
    tab.queryController.addListener(_onTextChanged);
    tab.searchFieldFocusNode.addListener(_onCursorPositionChanged);
  }

  void _detachTabListeners(SearchingTab tab) {
    tab.queryController.removeListener(_onTextChanged);
    tab.searchFieldFocusNode.removeListener(_onCursorPositionChanged);
  }

  @override
  void didUpdateWidget(covariant EnhancedSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tab, widget.tab)) {
      _detachTabListeners(oldWidget.tab);
      _attachTabListeners(widget.tab);
    }
  }

  @override
  void deactivate() {
    _hideSearchOptionsOverlay();
    super.deactivate();
  }

  @override
  void dispose() {
    _hideSearchOptionsOverlay();
    _detachTabListeners(widget.tab);
    _keyboardListenerFocusNode.dispose();
    _textFieldKeyboardListenerFocusNode.dispose();
    // בכוונה לא מנקים כאן את אפשרויות הטאב: הטאב שייך לבעליו (דיאלוג
    // החיפוש או טאב תוצאות חי), וה-dispose של השדה רץ לפני זה של הדיאלוג
    // — ניקוי כאן היה מרוקן את האפשרויות רגע לפני שהדיאלוג זוכר אותן
    // לסשן, ובטאב חי היה מוחק אפשרויות של חיפוש פעיל.
    super.dispose();
  }

  void _onTextChanged() {
    final bool drawerWasOpen = _searchOptionsOverlay != null;
    final text = widget.tab.queryController.text;

    // אם שדה החיפוש התרוקן, נקה את האפשרויות הפר-מיליות (המפתחות שלהן
    // נגזרים ממילים שכבר אינן) ונסגור את המגירה. האפשרויות הגלובליות
    // אינן תלויות בשאילתה ונשארות — הן נזרעות מברירת המחדל/הסשן ומחיקתן
    // כאן הייתה מוחקת את הסימונים בכל התרוקנות של השדה.
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
              _searchOptionsOverlayHeight == 0
                  ? 120.0
                  : _searchOptionsOverlayHeight,
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
                    key: _searchOptionsOverlayKey,
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
        _measureOverlayHeight();
      }
    });

    // וידוא שה-overlay מוכן לקבל לחיצות
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ה-overlay כעת מוכן לקבל לחיצות
    });
  }

  void _measureOverlayHeight() {
    final overlayBox =
        _searchOptionsOverlayKey.currentContext?.findRenderObject()
            as RenderBox?;
    // ייתכן ש-currentContext תקין אך ה-RenderBox עדיין לא עבר layout (למשל
    // אם ה-overlay נסגר/offstage באותו פריים) — אז size אינו מדיד.
    if (overlayBox == null || !overlayBox.hasSize) {
      return;
    }

    final newHeight = overlayBox.size.height;
    if ((_searchOptionsOverlayHeight - newHeight).abs() < 0.5) {
      return;
    }

    _searchOptionsOverlayHeight = newHeight;
    _searchOptionsOverlay?.markNeedsBuild();
  }

  // המילה הנוכחית (לפי מיקום הסמן), במונחי splitQueryWords של המנוע:
  // ה-word וה-index חייבים להתאים למפתחות "{word}_{index}" שבונה
  // advanced_search_controls, אחרת האפשרויות ייקשרו למילה הלא-נכונה.
  // המיפוי לטווחים בטקסט הגולמי — כולל סמן על `דין` בתוך `בית-דין`
  // ומקטעים שהנורמליזציה שינתה את אורכם (`רמב''ם`) — ב-queryWordSpans.
  Map<String, dynamic>? _getCurrentWordInfo() {
    final text = widget.tab.queryController.text;
    final cursorPosition = widget.tab.queryController.selection.baseOffset;

    if (text.isEmpty || cursorPosition < 0) return null;

    for (final span in SearchQueryBuilder.queryWordSpans(text)) {
      if (cursorPosition >= span.start && cursorPosition <= span.end) {
        return {
          'word': span.word,
          'index': span.index,
          'start': span.start,
          'end': span.end,
        };
      }
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
          style: TextStyle(fontSize: 12),
          textAlign: TextAlign.center,
        ),
      );
    }

    return SearchOptionsRow(
      isVisible: true,
      currentWord: wordInfo['word'],
      wordIndex: wordInfo['index'],
      wordOptions: widget.tab.searchOptions,
      showAdvancedOnlyOptions:
          widget.tab.searchBloc.state.configuration.searchMode ==
          SearchMode.advanced,
      onOptionsChanged: _onSearchOptionsChanged,
      key: ValueKey(
        '${wordInfo['word']}_${wordInfo['index']}',
      ), // מפתח ייחודי לעדכון
    );
  }

  void _hideSearchOptionsOverlay() {
    _searchOptionsOverlay?.remove();
    _searchOptionsOverlay = null;
    _searchOptionsOverlayHeight = 0;
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
    // אם קיים callback חיצוני (למשל מהדיאלוג), משתמשים בו במקום לוגיקת החיפוש הפנימית
    if (widget.onSubmit != null) {
      widget.onSubmit!();
      return;
    }

    String query = widget.tab.queryController.text.trim();
    if (query.isNotEmpty) {
      // תחביר קטגוריה: `מונח@קטגוריה` מצמצם את החיפוש לקטגוריה לפי שם.
      final parsedCategory = parseCategoryQuery(
        query,
        context.read<LibraryBloc>().state.library,
      );
      if (parsedCategory.hasCategoryToken && !parsedCategory.categoryFound) {
        UiSnack.showError(
          LibraryMessages.categoryOrBookNotFound(parsedCategory.notFoundNames),
        );
        return;
      }
      query = parsedCategory.query;
      if (query.isEmpty) return;

      // אם הוקלד תחביר `@`, מנקים אותו מהשדה — ההיסטוריה שומרת את טקסט השדה,
      // והשחזור ממנה אינו מפענח `@` מחדש (אחרת יחפש מילולית "שלום@תורה").
      if (widget.tab.queryController.text != query) {
        widget.tab.queryController.value = TextEditingValue(
          text: query,
          selection: TextSelection.collapsed(offset: query.length),
        );
      }

      // חיפוש רגיל עובד על טקסט ללא ניקוד; כשאפשרות "ניקוד"/"טעמים" מסומנת
      // (במצב מתקדם, גלובלית או פר-מילה) הסימנים שהוקלדו הם חלק מהשאילתה —
      // המנוע דורש אותם — ואסור למחוק. הבדיקה על מפות המקור, כי האפשרויות
      // האפקטיביות נבנות מהשאילתה אחרי המחיקה.
      final fieldConfig = widget.tab.searchBloc.state.configuration;
      final vocalizedSearch =
          fieldConfig.searchMode == SearchMode.advanced &&
          (widget.tab.useGlobalSearchOptions.value
              ? SearchQueryBuilder.globalOptionsRequestVocalized(
                  widget.tab.globalSearchOptions,
                )
              : SearchQueryBuilder.optionsRequestVocalized(
                  widget.tab.searchOptions,
                ));
      if (!vocalizedSearch && utils.hasNikud(query)) {
        query = utils.removeVolwels(query);
      }

      final searchMode = widget.tab.searchBloc.state.configuration.searchMode;
      final normalizedParameters =
          SearchQueryBuilder.normalizeParametersForMode(
            searchMode,
            customSpacing: widget.tab.spacingValues,
            alternativeWords: widget.tab.alternativeWords,
            searchOptions: widget.tab.effectiveSearchOptions(query: query),
          );
      final normalizedNegativeParameters =
          SearchQueryBuilder.normalizeParametersForMode(
            searchMode,
            customSpacing: widget.tab.negativeSpacingValues,
            alternativeWords: widget.tab.negativeAlternativeWords,
            searchOptions: widget.tab.effectiveNegativeSearchOptions(
              query: widget.tab.negativeQueryController.text,
            ),
          );

      widget.tab.updateTitleFromAppliedQuery(query);
      // תחביר `@קטגוריה`/`@ספר` גובר על scope הקיים של הטאב. מעבירים את
      // ה-scope במפורש להיסטוריה כדי שלא ייאבד עד שה-SearchBloc יעדכן state.
      context.read<HistoryBloc>().add(
        AddHistory(
          widget.tab,
          scopeFacets: parsedCategory.categoryFound
              ? parsedCategory.facets
              : null,
        ),
      );
      if (parsedCategory.categoryFound) {
        context.read<SearchBloc>().add(
          SetFacetsWithoutSearch(parsedCategory.facets!),
        );
      }
      context.read<SearchBloc>().add(
        UpdateSearchQuery(
          query,
          negativeQuery: widget.tab.negativeQueryController.text,
          customSpacing: normalizedParameters.customSpacing,
          alternativeWords: normalizedParameters.alternativeWords,
          searchOptions: normalizedParameters.searchOptions,
          negativeCustomSpacing: normalizedNegativeParameters.customSpacing,
          negativeAlternativeWords:
              normalizedNegativeParameters.alternativeWords,
          negativeSearchOptions: normalizedNegativeParameters.searchOptions,
        ),
      );
      widget.tab.isLeftPaneOpen.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MultiBlocListener(
      listeners: [
        BlocListener<NavigationBloc, NavigationState>(
          listener: (context, state) {
            // סגירת מגירת האפשרויות כשמשנים מסך
            if (_searchOptionsOverlay != null) {
              _hideSearchOptionsOverlay();
            }
          },
        ),
      ],
      child: KeyboardListener(
        focusNode: _keyboardListenerFocusNode,
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
                    focusNode: _textFieldKeyboardListenerFocusNode,
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
                    child: Tooltip(
                      message:
                          'הקלד מילות חיפוש ולחץ Enter או על סמל החיפוש כדי לבצע חיפוש.',
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
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHigh,
                          border: const OutlineInputBorder(),
                          hintText: 'הקלד מילות חיפוש',
                          labelText: 'חיפוש',
                          prefixIcon: widget.showInlineSearchButton
                              ? IconButton(
                                  onPressed: _performSearch,
                                  icon: const Icon(
                                    FluentIcons.search_24_regular,
                                  ),
                                )
                              : const Icon(FluentIcons.search_24_regular),
                          suffixIcon: widget.trailingAction != null
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    widget.trailingAction!,
                                    IconButton(
                                      icon: const Icon(
                                        FluentIcons.dismiss_24_regular,
                                      ),
                                      onPressed: () {
                                        widget.tab.queryController.clear();
                                        widget.tab.searchOptions.clear();
                                        widget.tab.globalSearchOptions.clear();
                                        context.read<SearchBloc>().add(
                                          UpdateSearchQuery(''),
                                        );
                                        context.read<SearchBloc>().add(
                                          UpdateFacetCounts({}),
                                        );
                                      },
                                    ),
                                  ],
                                )
                              : IconButton(
                                  icon: const Icon(
                                    FluentIcons.dismiss_24_regular,
                                  ),
                                  onPressed: () {
                                    widget.tab.queryController.clear();
                                    widget.tab.searchOptions.clear();
                                    widget.tab.globalSearchOptions.clear();
                                    context.read<SearchBloc>().add(
                                      UpdateSearchQuery(''),
                                    );
                                    context.read<SearchBloc>().add(
                                      UpdateFacetCounts({}),
                                    );
                                  },
                                ),
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
