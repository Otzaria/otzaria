import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/rendering.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/models/search_terms_model.dart';
import 'package:otzaria/search/view/tantivy_full_text_search.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/search/utils/regex_patterns.dart';
import 'package:otzaria/search/view/search_options_dropdown.dart';

class _PlusButton extends StatefulWidget {
  final bool active;
  final VoidCallback onTap;

  const _PlusButton({
    required this.active,
    required this.onTap,
  });

  @override
  State<_PlusButton> createState() => _PlusButtonState();
}

// כפתור המרווח המופיע בריחוף
class _SpacingButton extends StatefulWidget {
  final VoidCallback onTap;

  const _SpacingButton({
    required this.onTap,
  });

  @override
  State<_SpacingButton> createState() => _SpacingButtonState();
}

class _PlusButtonState extends State<_PlusButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final bool isHighlighted = widget.active || _isHovering;
    final primaryColor = Theme.of(context).primaryColor;

    // MouseRegion מזהה ריחוף עכבר
    return Tooltip(
      message: 'הוסף מילה חלופית',
      waitDuration: const Duration(milliseconds: 500),
      showDuration: const Duration(milliseconds: 1500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            // אנימציה למעבר חלק
            duration: const Duration(milliseconds: 200),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: isHighlighted
                  ? primaryColor
                  : primaryColor.withValues(alpha: 0.5),
              shape: BoxShape.circle,
              boxShadow: [
                if (isHighlighted)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            child: const Icon(
              FluentIcons.add_24_regular,
              size: 12,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _SpacingButtonState extends State<_SpacingButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Tooltip(
      message: 'הגדר ריווח בין מילים',
      waitDuration: const Duration(milliseconds: 500),
      showDuration: const Duration(milliseconds: 1500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: _isHovering
                  ? primaryColor
                  : primaryColor.withValues(alpha: 0.7),
              shape: BoxShape.circle,
              boxShadow: [
                if (_isHovering)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            child: const Icon(
              FluentIcons.arrow_swap_24_regular,
              size: 12,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// תיבה צפה למרווח בין מילים
class _SpacingField extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onRemove;
  final VoidCallback? onFocusLost;
  final bool requestFocus;

  const _SpacingField({
    required this.controller,
    required this.onRemove,
    this.onFocusLost,
    this.requestFocus = true,
  });

  @override
  State<_SpacingField> createState() => _SpacingFieldState();
}

class _SpacingFieldState extends State<_SpacingField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // רק אם נדרש לבקש פוקוס (בועות חדשות)
    if (widget.requestFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focus.requestFocus();
        }
      });
    }
    _focus.addListener(_onFocusChanged);
    widget.controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onFocusChanged() {
    if (mounted) {
      setState(() {});
    }
    if (!_focus.hasFocus && widget.controller.text.trim().isEmpty) {
      widget.onFocusLost?.call();
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    widget.controller.removeListener(_onTextChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool hasText = widget.controller.text.trim().isNotEmpty;
    final bool hasFocus = _focus.hasFocus;
    final bool isFloating = hasFocus || hasText; // התנאי להצפת התווית
    final bool isInactive = !hasFocus && hasText;

    final floatingLabelStyle = TextStyle(
      color: hasFocus ? theme.primaryColor : theme.hintColor,
      fontSize: 12,
      backgroundColor: theme.scaffoldBackgroundColor,
    );
    final placeholderStyle = TextStyle(
      color: theme.hintColor.withValues(alpha: 0.8),
      fontSize: 12,
    );

    return AnimatedOpacity(
      opacity: isInactive ? 0.5 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: Stack(
        clipBehavior: Clip.none, // מאפשר לתווית לצאת מגבולות ה-Stack
        children: [
          // 1. קופסת הקלט עצמה (השכבה התחתונה)
          Container(
            width: 45, // רוחב צר למספר 1-2 ספרות
            height: 40,
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hasFocus ? theme.primaryColor : theme.dividerColor,
                width: hasFocus ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: hasFocus ? 0.15 : 0.08),
                  blurRadius: hasFocus ? 6 : 3,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(FluentIcons.dismiss_24_regular, size: 14),
                    onPressed: widget.onRemove,
                    splashRadius: 16,
                    padding: const EdgeInsets.only(left: 4, right: 2),
                    constraints: const BoxConstraints(),
                  ),
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focus,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      decoration: const InputDecoration(
                        // הסרנו את labelText מכאן
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.only(right: 4, bottom: 4),
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                        fontWeight: FontWeight.w200, // גופן צר לטקסט שנכתב
                      ),
                      textAlign: TextAlign.right,
                      onSubmitted: (v) {
                        if (v.trim().isEmpty) widget.onRemove();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. התווית הצפה (השכבה העליונה)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeInOut,
            // מיקום דינמי: למעלה או באמצע
            top: isFloating ? -10 : 10,
            right: isFloating ? 8 : 12,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 150),
              style: isFloating ? floatingLabelStyle : placeholderStyle,
              child: Container(
                // קונטיינר זה יוצר את אפקט ה"חיתוך" של הגבול
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: const Text(
                  'מרווח',
                  style: TextStyle(
                    fontWeight: FontWeight.w100, // גופן צר במיוחד
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlternativeField extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onRemove;
  final VoidCallback? onFocusLost;
  final bool requestFocus; // פרמטר חדש לקביעה אם לבקש פוקוס

  const _AlternativeField({
    required this.controller,
    required this.onRemove,
    this.onFocusLost,
    this.requestFocus = true, // ברירת מחדל - כן לבקש פוקוס
  });

  @override
  State<_AlternativeField> createState() => _AlternativeFieldState();
}

class _AlternativeFieldState extends State<_AlternativeField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // רק אם נדרש לבקש פוקוס (בועות חדשות)
    if (widget.requestFocus) {
      debugPrint('🎯 Requesting focus for new alternative field');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focus.requestFocus();
        }
      });
    } else {
      debugPrint('🚫 NOT requesting focus for existing alternative field');
    }
    _focus.addListener(_onFocusChanged);
    widget.controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onFocusChanged() {
    if (mounted) {
      setState(() {});
    }
    if (!_focus.hasFocus && widget.controller.text.trim().isEmpty) {
      widget.onFocusLost?.call();
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    widget.controller.removeListener(_onTextChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool hasText = widget.controller.text.trim().isNotEmpty;
    final bool hasFocus = _focus.hasFocus;
    final bool isFloating = hasFocus || hasText; // התנאי להצפת התווית
    final bool isInactive = !hasFocus && hasText;

    final floatingLabelStyle = TextStyle(
      color: hasFocus ? theme.primaryColor : theme.hintColor,
      fontSize: 12,
      backgroundColor: theme.scaffoldBackgroundColor,
    );
    final placeholderStyle = TextStyle(
      color: theme.hintColor.withValues(alpha: 0.8),
      fontSize: 12,
    );

    return AnimatedOpacity(
      opacity: isInactive ? 0.5 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: Stack(
        clipBehavior: Clip.none, // מאפשר לתווית לצאת מגבולות ה-Stack
        children: [
          // 1. קופסת הקלט עצמה (השכבה התחתונה)
          Container(
            width: 60, // רוחב צר למילה של כ-4 תווים
            height: 40,
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hasFocus ? theme.primaryColor : theme.dividerColor,
                width: hasFocus ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: hasFocus ? 0.15 : 0.08),
                  blurRadius: hasFocus ? 6 : 3,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(FluentIcons.dismiss_24_regular, size: 14),
                    onPressed: widget.onRemove,
                    splashRadius: 16,
                    padding: const EdgeInsets.only(left: 4, right: 2),
                    constraints: const BoxConstraints(),
                  ),
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focus,
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(
                            SearchRegexPatterns.spacesFilter),
                      ],
                      decoration: const InputDecoration(
                        // הסרנו את labelText מכאן
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.only(right: 4, bottom: 4),
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                        fontWeight: FontWeight.w200, // גופן צר לטקסט שנכתב
                      ),
                      textAlign: TextAlign.right,
                      onSubmitted: (v) {
                        if (v.trim().isEmpty) widget.onRemove();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. התווית הצפה (השכבה העליונה)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeInOut,
            // מיקום דינמי
            top: isFloating ? -10 : 10,
            right: isFloating ? 8 : 15,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 150),
              style: isFloating ? floatingLabelStyle : placeholderStyle,
              child: Container(
                // קונטיינר זה יוצר את אפקט ה"חיתוך" של הגבול
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: const Text(
                  'מילה חילופית',
                  style: TextStyle(
                    fontWeight: FontWeight.w100, // גופן צר במיוחד
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EnhancedSearchField extends StatefulWidget {
  final dynamic widget;

  const EnhancedSearchField({
    super.key,
    required this.widget,
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
// ignore: library_private_types_in_public_api
final GlobalKey<_EnhancedSearchFieldState> enhancedSearchFieldKey = GlobalKey<_EnhancedSearchFieldState>();

class _EnhancedSearchFieldState extends State<EnhancedSearchField> {
  SearchQuery _searchQuery = SearchQuery();
  final GlobalKey _textFieldKey = GlobalKey();
  final GlobalKey _stackKey = GlobalKey();
  final List<Offset> _wordPositions = [];
  final Map<int, List<TextEditingController>> _alternativeControllers = {};
  final Map<int, List<OverlayEntry>> _alternativeOverlays = {};
  OverlayEntry? _searchOptionsOverlay;

  final Map<String, OverlayEntry> _spacingOverlays = {};
  final Map<String, TextEditingController> _spacingControllers = {};

  final List<double> _wordLeftEdges = [];
  final List<double> _wordRightEdges = [];

  static const double _kSearchFieldMinWidth = 300;
  static const double _kControlHeight = 48;

  static const double _kPlusYOffset = 10; // משמש לחישוב מיקום מילים
  static const double _kSpacingYOffset = 53;

  String _spaceKey(int left, int right) => '$left-$right';

  @override
  void initState() {
    super.initState();
    widget.tab.queryController.addListener(_onTextChanged);
    // מאזין לשינויי מיקום הסמן
    widget.tab.searchFieldFocusNode
        .addListener(_onCursorPositionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateWordPositions();
    });
  }

  @override
  void deactivate() {
    debugPrint('⏸️ EnhancedSearchField deactivating - clearing overlays');
    _clearAllOverlays();
    super.deactivate();
  }

  @override
  void dispose() {
    debugPrint('🗑️ EnhancedSearchField disposing');
    _clearAllOverlays();
    widget.tab.queryController.removeListener(_onTextChanged);
    widget.tab.searchFieldFocusNode
        .removeListener(_onCursorPositionChanged);
    _disposeControllers(); // במצב dispose אנחנו רוצים למחוק הכל
    // ניקוי אפשרויות החיפוש כשסוגרים את המסך
    widget.tab.searchOptions.clear();
    super.dispose();
  }

  // שמירת נתונים לפני ניקוי
  void _saveDataToTab() {
    // שמירת מילים חילופיות
    widget.tab.alternativeWords.clear();
    for (int termIndex in _alternativeControllers.keys) {
      final alternatives = _alternativeControllers[termIndex]!
          .map((controller) => controller.text.trim())
          .where((text) => text.isNotEmpty)
          .toList();
      if (alternatives.isNotEmpty) {
        widget.tab.alternativeWords[termIndex] = alternatives;
      }
    }

    // שמירת מרווחים
    widget.tab.spacingValues.clear();
    for (String key in _spacingControllers.keys) {
      final spacingText = _spacingControllers[key]!.text.trim();
      if (spacingText.isNotEmpty) {
        widget.tab.spacingValues[key] = spacingText;
      }
    }
  }

  // שחזור נתונים מה-tab
  void _restoreDataFromTab() {
    // ניקוי controllers קיימים לפני השחזור
    _disposeControllers();

    // עדכון ה-searchQuery מהטקסט הנוכחי
    final text = widget.tab.queryController.text;
    if (text.isNotEmpty) {
      _searchQuery = SearchQuery.fromString(text);
    }

    // שחזור מילים חילופיות
    for (final entry in widget.tab.alternativeWords.entries) {
      final termIndex = entry.key;
      final alternatives = entry.value;

      _alternativeControllers[termIndex] = alternatives.map((alt) {
        final controller = TextEditingController(text: alt);
        controller.addListener(() => _updateAlternativeWordsInTab());
        return controller;
      }).toList();
    }

    // שחזור מרווחים
    for (final entry in widget.tab.spacingValues.entries) {
      final key = entry.key;
      final value = entry.value;

      final controller = TextEditingController(text: value);
      controller.addListener(() => _updateSpacingInTab());
      _spacingControllers[key] = controller;
    }
  }

  // הצגת בועות שחוזרו
  void _showRestoredBubbles() {
    // הצגת מילים חילופיות
    for (final entry in _alternativeControllers.entries) {
      final termIndex = entry.key;
      final controllers = entry.value;
      for (int j = 0; j < controllers.length; j++) {
        if (termIndex < _wordPositions.length) {
          _showAlternativeOverlay(termIndex, j, requestFocus: false);
        }
      }
    }

    // הצגת מרווחים
    for (final key in _spacingControllers.keys) {
      final parts = key.split('-');
      if (parts.length == 2) {
        final leftIndex = int.tryParse(parts[0]);
        final rightIndex = int.tryParse(parts[1]);
        if (leftIndex != null &&
            rightIndex != null &&
            leftIndex < _wordPositions.length &&
            rightIndex < _wordPositions.length) {
          _showSpacingOverlay(leftIndex, rightIndex, requestFocus: false);
        }
      }
    }
  }

  // ניקוי נתונים לא רלוונטיים כשהמילים משתנות
  void _cleanupIrrelevantData(Set<String> newWords) {
    // ניקוי אפשרויות חיפוש למילים שלא קיימות יותר
    final searchOptionsKeysToRemove = <String>[];
    for (final key in widget.tab.searchOptions.keys) {
      final parts = key.split('_');
      if (parts.isNotEmpty) {
        final word = parts[0];
        if (!newWords.contains(word)) {
          searchOptionsKeysToRemove.add(key);
        }
      }
    }

    for (final key in searchOptionsKeysToRemove) {
      widget.tab.searchOptions.remove(key);
    }
  }

  // עדכון אפשרויות החיפוש לפי המיפוי החדש
  void _remapSearchOptions(Map<int, int> wordMapping, List<String> newWords) {
    // ניצור עותק של האפשרויות הישנות ונתייחס אליו כאל Map מהסוג הנכון
    final oldSearchOptions =
        Map<String, Map<String, bool>>.from(widget.tab.searchOptions);
    final newSearchOptions = <String, Map<String, bool>>{};

    // נעבור על כל האפשרויות הישנות
    for (final entry in oldSearchOptions.entries) {
      final oldKey = entry.key; // לדוגמה: "מילה_1"
      final optionsMap = entry.value; // מפת האפשרויות של המילה
      final parts = oldKey.split('_');

      // נוודא שהמפתח תקין (מכיל מילה ואינדקס)
      if (parts.length >= 2) {
        // נחלץ את האינדקס הישן מהמפתח
        final oldIndex = int.tryParse(parts.last);

        // אם הצלחנו לקרוא את האינדקס הישן, והוא קיים במפת המיפוי שלנו
        if (oldIndex != null && wordMapping.containsKey(oldIndex)) {
          // נמצא את האינדקס החדש של המילה
          final newIndex = wordMapping[oldIndex]!;

          // נוודא שהאינדקס החדש תקין ביחס לרשימת המילים החדשה
          if (newIndex < newWords.length) {
            final newWord = newWords[newIndex];

            // ✅ כאן התיקון המרכזי: נייצר מפתח חדש עם המילה החדשה והאינדקס החדש
            final newKey = '${newWord}_$newIndex';

            // נוסיף את האפשרויות למפה החדשה שיצרנו
            newSearchOptions[newKey] = optionsMap;
          }
        }
        // אם המילה נמחקה (ולא נמצאת ב-wordMapping), אנחנו פשוט מתעלמים מהאפשרויות שלה, וזה תקין.
      }
    }

    // לבסוף, נחליף את מפת האפשרויות הישנה במפה החדשה והמעודכנת שבנינו
    widget.tab.searchOptions.clear();
    widget.tab.searchOptions.addAll(newSearchOptions);
  }

  void _clearAllOverlays(
      {bool keepSearchDrawer = false, bool keepFilledBubbles = false}) {
    debugPrint(
        '🧹 CLEAR OVERLAYS: ${DateTime.now()} - keepSearchDrawer: $keepSearchDrawer, keepFilledBubbles: $keepFilledBubbles');
    // ניקוי אלטרנטיבות - רק אם לא ביקשנו לשמור בועות מלאות או אם הן ריקות
    if (!keepFilledBubbles) {
      debugPrint(
          '🧹 Clearing ${_alternativeOverlays.length} alternative overlay groups');
      for (final entries in _alternativeOverlays.values) {
        for (final entry in entries) {
          entry.remove();
        }
      }
      _alternativeOverlays.clear();
    } else {
      // שמירה רק על בועות עם טקסט
      final keysToRemove = <int>[];
      for (final termIndex in _alternativeOverlays.keys) {
        final controllers = _alternativeControllers[termIndex] ?? [];
        final overlays = _alternativeOverlays[termIndex] ?? [];

        final indicesToRemove = <int>[];
        for (int i = 0; i < controllers.length; i++) {
          if (controllers[i].text.trim().isEmpty) {
            if (i < overlays.length) {
              overlays[i].remove();
              indicesToRemove.add(i);
            }
          }
        }

        // הסרה בסדר הפוך כדי לא לפגוע באינדקסים
        for (int i = indicesToRemove.length - 1; i >= 0; i--) {
          final indexToRemove = indicesToRemove[i];
          if (indexToRemove < overlays.length) {
            overlays.removeAt(indexToRemove);
          }
          if (indexToRemove < controllers.length) {
            controllers[indexToRemove].dispose();
            controllers.removeAt(indexToRemove);
          }
        }

        if (overlays.isEmpty) {
          keysToRemove.add(termIndex);
        }
      }

      for (final key in keysToRemove) {
        _alternativeOverlays.remove(key);
        _alternativeControllers.remove(key);
      }
    }

    // ניקוי מרווחים - רק אם לא ביקשנו לשמור בועות מלאות או אם הן ריקות
    if (!keepFilledBubbles) {
      debugPrint('🧹 Clearing ${_spacingOverlays.length} spacing overlays');
      for (final entry in _spacingOverlays.values) {
        entry.remove();
      }
      _spacingOverlays.clear();
    } else {
      // שמירה רק על בועות עם טקסט
      final keysToRemove = <String>[];
      for (final key in _spacingOverlays.keys) {
        final controller = _spacingControllers[key];
        if (controller == null || controller.text.trim().isEmpty) {
          _spacingOverlays[key]?.remove();
          keysToRemove.add(key);
        }
      }

      for (final key in keysToRemove) {
        _spacingOverlays.remove(key);
        _spacingControllers[key]?.dispose();
        _spacingControllers.remove(key);
      }
    }

    // סגירת מגירת האפשרויות רק אם לא ביקשנו לשמור אותה
    if (!keepSearchDrawer) {
      _searchOptionsOverlay?.remove();
      _searchOptionsOverlay = null;
    }
  }

  void _disposeControllers({bool keepFilledControllers = false}) {
    if (!keepFilledControllers) {
      // מחיקה מלאה של כל ה-controllers
      for (final controllers in _alternativeControllers.values) {
        for (final controller in controllers) {
          controller.dispose();
        }
      }
      _alternativeControllers.clear();
      for (final controller in _spacingControllers.values) {
        controller.dispose();
      }
      _spacingControllers.clear();
    } else {
      // מחיקה רק של controllers ריקים
      final alternativeKeysToRemove = <int>[];
      for (final entry in _alternativeControllers.entries) {
        final termIndex = entry.key;
        final controllers = entry.value;
        final indicesToRemove = <int>[];

        for (int i = 0; i < controllers.length; i++) {
          if (controllers[i].text.trim().isEmpty) {
            controllers[i].dispose();
            indicesToRemove.add(i);
          }
        }

        // הסרה בסדר הפוך
        for (int i = indicesToRemove.length - 1; i >= 0; i--) {
          controllers.removeAt(indicesToRemove[i]);
        }

        if (controllers.isEmpty) {
          alternativeKeysToRemove.add(termIndex);
        }
      }

      for (final key in alternativeKeysToRemove) {
        _alternativeControllers.remove(key);
      }

      // מחיקת spacing controllers ריקים
      final spacingKeysToRemove = <String>[];
      for (final entry in _spacingControllers.entries) {
        if (entry.value.text.trim().isEmpty) {
          entry.value.dispose();
          spacingKeysToRemove.add(entry.key);
        }
      }

      for (final key in spacingKeysToRemove) {
        _spacingControllers.remove(key);
      }
    }
  }

  void _onTextChanged() {
    // בודקים אם המגירה הייתה פתוחה לפני השינוי
    final bool drawerWasOpen = _searchOptionsOverlay != null;

    final text = widget.tab.queryController.text;

    // אם שדה החיפוש התרוקן, נקה הכל ונסגור את המגירה
    if (text.trim().isEmpty) {
      _clearAllOverlays();
      _disposeControllers();
      widget.tab.searchOptions.clear();
      widget.tab.alternativeWords.clear();
      widget.tab.spacingValues.clear();
      if (drawerWasOpen) {
        _hideSearchOptionsOverlay();
        _notifyDropdownClosed();
      }
      setState(() {
        _searchQuery = SearchQuery();
      });
      return;
    }

    // בדיקה אם זה שינוי קטן (מחיקת/הוספת אות אחת) או שינוי גדול (מחיקת/הוספת מילה שלמה)
    final newWords =
        text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final oldWords = _searchQuery.terms.map((t) => t.word).toList();

    final bool isMinorChange = _isMinorTextChange(oldWords, newWords);

    debugPrint('🔄 Text change detected: ${isMinorChange ? "MINOR" : "MAJOR"}');
    debugPrint('   Old words: $oldWords');
    debugPrint('   New words: $newWords');
    debugPrint(
        '   Current search options: ${widget.tab.searchOptions.keys.toList()}');

    if (isMinorChange) {
      // שינוי קטן - שמור על כל הסימונים והבועות
      debugPrint('✅ Preserving all markings and bubbles');
      _handleMinorTextChange(text, drawerWasOpen);
    } else {
      // שינוי גדול - נקה סימונים שלא רלוונטיים יותר
      debugPrint('🔄 Remapping markings and bubbles');
      _handleMajorTextChange(text, newWords, drawerWasOpen);
    }
  }

  // בדיקה אם זה שינוי קטן (רק שינוי באותיות בתוך מילים קיימות)
  bool _isMinorTextChange(List<String> oldWords, List<String> newWords) {
    // אם מספר המילים השתנה, זה תמיד שינוי גדול
    // (מחיקת או הוספת מילה שלמה)
    if (oldWords.length != newWords.length) {
      return false;
    }

    // אם מספר המילים זהה, בדוק שינויים בתוך המילים
    for (int i = 0; i < oldWords.length && i < newWords.length; i++) {
      final oldWord = oldWords[i];
      final newWord = newWords[i];

      // אם המילים זהות, זה בסדר
      if (oldWord == newWord) continue;

      // בדיקה אם זה שינוי קטן (הוספה/הסרה של אות אחת או שתיים)
      final lengthDiff = (oldWord.length - newWord.length).abs();
      if (lengthDiff > 2) {
        return false; // שינוי גדול מדי
      }

      // בדיקה אם המילה החדשה מכילה את רוב האותיות של המילה הישנה
      final similarity = _calculateWordSimilarity(oldWord, newWord);
      if (similarity < 0.7) {
        return false; // המילים שונות מדי
      }
    }

    return true;
  }

  // חישוב דמיון בין שתי מילים (אלגוריתם Levenshtein distance מפושט)
  double _calculateWordSimilarity(String word1, String word2) {
    if (word1.isEmpty && word2.isEmpty) return 1.0;
    if (word1.isEmpty || word2.isEmpty) return 0.0;
    if (word1 == word2) return 1.0;

    // חישוב מרחק עריכה פשוט
    final maxLength = word1.length > word2.length ? word1.length : word2.length;
    int distance = (word1.length - word2.length).abs();

    // ספירת תווים שונים באותו מיקום
    final minLength = word1.length < word2.length ? word1.length : word2.length;
    for (int i = 0; i < minLength; i++) {
      if (word1[i] != word2[i]) {
        distance++;
      }
    }

    // החזרת ציון דמיון (1.0 = זהות מלאה, 0.0 = שונות מלאה)
    return 1.0 - (distance / maxLength);
  }

  // טיפול בשינוי קטן - שמירה על כל הסימונים
  void _handleMinorTextChange(String text, bool drawerWasOpen) {
    // מנקים רק את הבועות הריקות, שומרים על הכל
    _clearAllOverlays(keepSearchDrawer: drawerWasOpen, keepFilledBubbles: true);

    // שמירת אפשרויות החיפוש הקיימות ומילים ישנות לפני יצירת SearchQuery חדש
    final oldSearchOptions =
        Map<String, dynamic>.from(widget.tab.searchOptions);
    final oldWords = _searchQuery.terms.map((t) => t.word).toList();

    setState(() {
      _searchQuery = SearchQuery.fromString(text);
      // לא קוראים ל-_updateAlternativeControllers כדי לא לפגוע במיפוי הקיים
    });

    // עדכון אפשרויות החיפוש לפי המילים החדשות (שמירה על אפשרויות קיימות)
    _updateSearchOptionsForMinorChange(oldSearchOptions, oldWords, text);

    debugPrint(
        '✅ After minor change - search options: ${widget.tab.searchOptions.keys.toList()}');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateWordPositions();
      _showAllExistingBubbles();

      if (drawerWasOpen) {
        _updateSearchOptionsOverlay();
      }
    });
  }

  // עדכון אפשרויות החיפוש בשינוי קטן - שמירה על אפשרויות קיימות
  void _updateSearchOptionsForMinorChange(Map<String, dynamic> oldSearchOptions,
      List<String> oldWords, String newText) {
    final newWords = newText
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    debugPrint('🔧 Updating search options for minor change:');
    debugPrint('   Old search options: ${oldSearchOptions.keys.toList()}');
    debugPrint('   Old words: $oldWords');
    debugPrint('   New words: $newWords');

    // אם מספר המילים זהה, פשוט נעדכן את המפתחות לפי המילים החדשות
    if (newWords.length == oldWords.length) {
      debugPrint('   Same number of words - updating keys');
      widget.tab.searchOptions.clear();

      for (final entry in oldSearchOptions.entries) {
        final key = entry.key;
        final value = entry.value;
        final parts = key.split('_');

        if (parts.length >= 2) {
          final oldWord = parts[0];
          final option = parts.sublist(1).join('_');

          // מציאת האינדקס של המילה הישנה
          final oldWordIndex = oldWords.indexOf(oldWord);
          if (oldWordIndex != -1 && oldWordIndex < newWords.length) {
            // עדכון המפתח עם המילה החדשה
            final newWord = newWords[oldWordIndex];
            final newKey = '${newWord}_$option';
            widget.tab.searchOptions[newKey] = value;
            debugPrint('🔄 Updated search option: $key -> $newKey');
          }
        }
      }
    } else {
      // אם מספר המילים השתנה, נשמור רק אפשרויות של מילים שעדיין קיימות
      debugPrint(
          '   Different number of words - preserving existing words only');
      widget.tab.searchOptions.clear();

      for (final entry in oldSearchOptions.entries) {
        final key = entry.key;
        final value = entry.value;
        final parts = key.split('_');

        if (parts.length >= 2) {
          final word = parts[0];

          // אם המילה עדיין קיימת ברשימה החדשה, נשמור את האפשרות
          if (newWords.contains(word)) {
            widget.tab.searchOptions[key] = value;
            debugPrint('🔄 Preserved search option: $key');
          } else {
            debugPrint('❌ Removed search option for deleted word: $key');
          }
        }
      }
    }
  }

  // טיפול בשינוי גדול - ניקוי סימונים לא רלוונטיים
  void _handleMajorTextChange(
      String text, List<String> newWords, bool drawerWasOpen) {
    // מיפוי מילים ישנות למילים חדשות לפי דמיון
    final wordMapping = _mapOldWordsToNew(newWords);
    debugPrint('🗺️ Word mapping: $wordMapping');

    // עדכון controllers ו-overlays לפי המיפוי החדש
    _remapControllersAndOverlays(wordMapping);

    // עדכון אפשרויות החיפוש לפי המיפוי החדש
    _remapSearchOptions(wordMapping, newWords);

    // ניקוי נתונים לא רלוונטיים
    _cleanupIrrelevantData(newWords.toSet());

    // לא צריך לקרוא ל-_clearAllOverlays כי כבר ניקינו הכל ב-_remapControllersAndOverlays

    setState(() {
      _searchQuery = SearchQuery.fromString(text);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateWordPositions();
      debugPrint('🎈 Showing remapped bubbles after major change');
      _showAllExistingBubbles();

      if (drawerWasOpen) {
        _updateSearchOptionsOverlay();
      }
    });
  }

  // מיפוי מילים ישנות למילים חדשות
  Map<int, int> _mapOldWordsToNew(List<String> newWords) {
    final oldWords = _searchQuery.terms.map((t) => t.word).toList();
    final Map<int, int> mapping = {};

    // שלב 1: מיפוי מילים זהות לחלוטין
    for (int oldIndex = 0; oldIndex < oldWords.length; oldIndex++) {
      for (int newIndex = 0; newIndex < newWords.length; newIndex++) {
        if (mapping.containsValue(newIndex)) continue;

        if (oldWords[oldIndex] == newWords[newIndex]) {
          mapping[oldIndex] = newIndex;
          break;
        }
      }
    }

    // שלב 2: מיפוי מילים דומות (לטיפול במחיקת/הוספת אותיות)
    for (int oldIndex = 0; oldIndex < oldWords.length; oldIndex++) {
      if (mapping.containsKey(oldIndex)) continue; // כבר נמפה

      final oldWord = oldWords[oldIndex];
      double bestSimilarity = 0.0;
      int bestNewIndex = -1;

      for (int newIndex = 0; newIndex < newWords.length; newIndex++) {
        if (mapping.containsValue(newIndex)) continue;

        final newWord = newWords[newIndex];
        final similarity = _calculateWordSimilarity(oldWord, newWord);

        // סף נמוך יותר לדמיון כדי לתפוס גם שינויים קטנים
        if (similarity > bestSimilarity && similarity > 0.3) {
          bestSimilarity = similarity;
          bestNewIndex = newIndex;
        }
      }

      if (bestNewIndex != -1) {
        mapping[oldIndex] = bestNewIndex;
      }
    }

    return mapping;
  }

  // עדכון controllers ו-overlays לפי המיפוי החדש
  void _remapControllersAndOverlays(Map<int, int> wordMapping) {
    // שמירת controllers ישנים
    final oldAlternativeControllers =
        Map<int, List<TextEditingController>>.from(_alternativeControllers);
    final oldSpacingControllers =
        Map<String, TextEditingController>.from(_spacingControllers);

    // ניקוי כל ה-overlays הישנים לפני המיפוי
    debugPrint('🧹 Clearing all old overlays before remapping');
    for (final entries in _alternativeOverlays.values) {
      for (final entry in entries) {
        entry.remove();
      }
    }
    _alternativeOverlays.clear();

    for (final entry in _spacingOverlays.values) {
      entry.remove();
    }
    _spacingOverlays.clear();

    // ניקוי המפות הנוכחיות
    _alternativeControllers.clear();
    _spacingControllers.clear();

    // מיפוי controllers של מילים חלופיות
    for (final entry in oldAlternativeControllers.entries) {
      final oldIndex = entry.key;
      final controllers = entry.value;

      if (wordMapping.containsKey(oldIndex)) {
        final newIndex = wordMapping[oldIndex]!;
        _alternativeControllers[newIndex] = controllers;
      } else {
        // אם המילה לא נמפתה, נמחק את ה-controllers
        for (final controller in controllers) {
          controller.dispose();
        }
      }
    }

    // מיפוי controllers של מרווחים
    for (final entry in oldSpacingControllers.entries) {
      final oldKey = entry.key;
      final controller = entry.value;
      final parts = oldKey.split('-');

      if (parts.length == 2) {
        final oldLeft = int.tryParse(parts[0]);
        final oldRight = int.tryParse(parts[1]);

        if (oldLeft != null &&
            oldRight != null &&
            wordMapping.containsKey(oldLeft) &&
            wordMapping.containsKey(oldRight)) {
          final newLeft = wordMapping[oldLeft]!;
          final newRight = wordMapping[oldRight]!;
          final newKey = _spaceKey(newLeft, newRight);
          _spacingControllers[newKey] = controller;
        } else {
          // אם המרווח לא רלוונטי יותר, נמחק את ה-controller
          controller.dispose();
        }
      }
    }

    // עדכון המילים החלופיות ב-tab
    _updateAlternativeWordsInTab();
    // עדכון המרווחים ב-tab
    _updateSpacingInTab();
  }

  // הצגת כל הבועות הקיימות
  void _showAllExistingBubbles() {
    debugPrint(
        '🎈 Showing existing bubbles - word positions: ${_wordPositions.length}');

    // הצגת alternatives מה-SearchQuery
    for (int i = 0; i < _searchQuery.terms.length; i++) {
      for (int j = 0; j < _searchQuery.terms[i].alternatives.length; j++) {
        if (i < _wordPositions.length) {
          _showAlternativeOverlay(i, j, requestFocus: false);
        } else {
          debugPrint(
              '⚠️ Skipping SearchQuery alternative at invalid position: $i');
        }
      }
    }

    // הצגת alternatives קיימים שנשמרו
    final invalidControllerKeys = <int>[];
    for (final entry in _alternativeControllers.entries) {
      final termIndex = entry.key;
      final controllers = entry.value;

      // בדיקה שהאינדקס תקין
      if (termIndex >= _wordPositions.length) {
        debugPrint(
            '⚠️ Marking invalid alternative controllers for removal: $termIndex');
        invalidControllerKeys.add(termIndex);
        // מחיקת controllers לא תקינים
        for (final controller in controllers) {
          controller.dispose();
        }
        continue;
      }

      for (int j = 0; j < controllers.length; j++) {
        if (controllers[j].text.trim().isNotEmpty) {
          debugPrint(
              '🎈 Showing alternative bubble at position $termIndex, alt $j');
          _showAlternativeOverlay(termIndex, j, requestFocus: false);
        }
      }
    }

    // הסרת controllers לא תקינים
    for (final key in invalidControllerKeys) {
      _alternativeControllers.remove(key);
    }

    // הצגת spacing overlays קיימים
    final invalidSpacingKeys = <String>[];
    for (final entry in _spacingControllers.entries) {
      final key = entry.key;
      final controller = entry.value;
      if (controller.text.trim().isNotEmpty) {
        final parts = key.split('-');
        if (parts.length == 2) {
          final leftIndex = int.tryParse(parts[0]);
          final rightIndex = int.tryParse(parts[1]);
          if (leftIndex != null &&
              rightIndex != null &&
              leftIndex < _wordPositions.length &&
              rightIndex < _wordPositions.length) {
            debugPrint(
                '🎈 Showing spacing bubble between $leftIndex and $rightIndex');
            _showSpacingOverlay(leftIndex, rightIndex, requestFocus: false);
          } else {
            debugPrint(
                '⚠️ Marking invalid spacing controller for removal: $key');
            invalidSpacingKeys.add(key);
            controller.dispose();
          }
        }
      }
    }

    // הסרת spacing controllers לא תקינים
    for (final key in invalidSpacingKeys) {
      _spacingControllers.remove(key);
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
              'DEBUG: Restoring cursor position in update: ${currentSelection.baseOffset}');
          widget.tab.queryController.selection = currentSelection;
        }
      });
    }
  }

  void _calculateWordPositions() {
    if (_textFieldKey.currentContext == null) return;

    RenderEditable? editable;
    void findEditable(RenderObject child) {
      if (child is RenderEditable) {
        editable = child;
      } else {
        child.visitChildren(findEditable);
      }
    }

    _textFieldKey.currentContext!
        .findRenderObject()!
        .visitChildren(findEditable);
    if (editable == null) return;

    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null) return;
    final stackOrigin = stackBox.localToGlobal(Offset.zero);

    _wordPositions.clear();
    _wordLeftEdges.clear();
    _wordRightEdges.clear();

    final text = widget.tab.queryController.text;
    if (text.isEmpty) {
      setState(() {});
      return;
    }

    final words = text.trim().split(RegExp(r'\s+'));
    int idx = 0;
    for (final w in words) {
      if (w.isEmpty) continue;
      final start = text.indexOf(w, idx);
      if (start == -1) continue;
      final end = start + w.length;

      final pts = editable!.getEndpointsForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      );
      if (pts.isEmpty) continue;

      final leftLocalX = pts.first.point.dx;
      final rightLocalX = pts.last.point.dx;

      final leftGlobal = editable!.localToGlobal(Offset(leftLocalX, 0));
      final rightGlobal = editable!.localToGlobal(Offset(rightLocalX, 0));

      _wordLeftEdges.add(leftGlobal.dx - stackOrigin.dx);
      _wordRightEdges.add(rightGlobal.dx - stackOrigin.dx);

      final centerLocalX = (leftLocalX + rightLocalX) / 2;
      final local = Offset(
        centerLocalX,
        editable!.size.height + _kPlusYOffset,
      );
      final global = editable!.localToGlobal(local);
      _wordPositions.add(global - stackOrigin);

      idx = end;
    }

    if (text.isNotEmpty && _wordPositions.isEmpty) {
// החישוב נכשל למרות שיש טקסט. ננסה שוב ב-frame הבא.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // ודא שהווידג'ט עדיין קיים
          _calculateWordPositions();
        }
      });
      return; // צא מהפונקציה כדי לא לקרוא ל-setState עם מידע שגוי
    }

    setState(() {});
  }

  // פונקציה ציבורית להוספת מילה חילופית - נגישה מבחוץ
  void addAlternativeWord(int termIndex) {
    _addAlternative(termIndex);
  }

  void _addAlternative(int termIndex) {
    setState(() {
      _alternativeControllers.putIfAbsent(termIndex, () => []);
      if (_alternativeControllers[termIndex]!.length >= 3) {
        return;
      }
      final newIndex = _alternativeControllers[termIndex]!.length;
      final controller = TextEditingController();
      // הוספת listener לעדכון המידע ב-tab כשהטקסט משתנה
      controller.addListener(() => _updateAlternativeWordsInTab());
      _alternativeControllers[termIndex]!.add(controller);
      _showAlternativeOverlay(termIndex, newIndex, requestFocus: true);
    });
    _updateAlternativeWordsInTab();
  }

  void _removeAlternative(int termIndex, int altIndex) {
    setState(() {
      if (_alternativeOverlays.containsKey(termIndex) &&
          altIndex < _alternativeOverlays[termIndex]!.length) {
        _alternativeOverlays[termIndex]![altIndex].remove();
        _alternativeOverlays[termIndex]!.removeAt(altIndex);
      }
      if (_alternativeControllers.containsKey(termIndex) &&
          altIndex < _alternativeControllers[termIndex]!.length) {
        _alternativeControllers[termIndex]![altIndex].dispose();
        _alternativeControllers[termIndex]!.removeAt(altIndex);
      }
      _refreshAlternativeOverlays(termIndex);
    });
    // עדכון המידע ב-tab אחרי הסרת החלופה
    _updateAlternativeWordsInTab();
  }

  void _checkAndRemoveEmptyField(int termIndex, int altIndex) {
    if (_alternativeControllers.containsKey(termIndex) &&
        altIndex < _alternativeControllers[termIndex]!.length &&
        _alternativeControllers[termIndex]![altIndex].text.trim().isEmpty) {
      _removeAlternative(termIndex, altIndex);
    }
  }

  void _refreshAlternativeOverlays(int termIndex) {
    if (!_alternativeOverlays.containsKey(termIndex)) return;
    for (final overlay in _alternativeOverlays[termIndex]!) {
      overlay.remove();
    }
    _alternativeOverlays[termIndex]!.clear();
    for (int i = 0; i < _alternativeControllers[termIndex]!.length; i++) {
      _showAlternativeOverlay(termIndex, i, requestFocus: false);
    }
  }

  void _showAlternativeOverlay(int termIndex, int altIndex,
      {bool requestFocus = false}) {
    debugPrint(
        '🎈 Showing alternative overlay: term=$termIndex, alt=$altIndex');

    // בדיקה שהאינדקסים תקינים
    if (termIndex >= _wordPositions.length ||
        !_alternativeControllers.containsKey(termIndex) ||
        altIndex >= _alternativeControllers[termIndex]!.length) {
      debugPrint('❌ Invalid indices for alternative overlay');
      return;
    }

    // בדיקה שהבועה לא מוצגת כבר
    final existingOverlays = _alternativeOverlays[termIndex];
    if (existingOverlays != null &&
        altIndex < existingOverlays.length &&
        mounted && // ודא שה-State עדיין קיים
        Overlay.of(context).mounted && // ודא שה-Overlay קיים
        existingOverlays[altIndex].mounted) {
      // ודא שהבועה הספציפית הזו עדיין על המסך
      debugPrint('⚠️ Alternative overlay already exists and mounted');
      return; // אם הבועה כבר קיימת ומוצגת, אל תעשה כלום
    }

    final overlayState = Overlay.of(context);
    final RenderBox? textFieldBox =
        _textFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (textFieldBox == null) return;
    final textFieldGlobalPosition = textFieldBox.localToGlobal(Offset.zero);
    final wordRelativePosition = _wordPositions[termIndex];
    final overlayPosition = textFieldGlobalPosition + wordRelativePosition;
    final controller = _alternativeControllers[termIndex]![altIndex];
    final entry = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: overlayPosition.dx -
              35, // מרכוז התיבה (70/2 = 35) מתחת לכפתור ה-+
          top: overlayPosition.dy + 15 + (altIndex * 45.0),
          child: _AlternativeField(
            controller: controller,
            onRemove: () => _removeAlternative(termIndex, altIndex),
            onFocusLost: () => _checkAndRemoveEmptyField(termIndex, altIndex),
            requestFocus: requestFocus, // העברת הפרמטר
          ),
        );
      },
    );
    _alternativeOverlays.putIfAbsent(termIndex, () => []).add(entry);
    overlayState.insert(entry);
  }

  // _buildPlusButton הוסר - עכשיו משתמשים בכפתור בדיאלוג

  void _showSpacingOverlay(int leftIndex, int rightIndex,
      {bool requestFocus = false}) {
    final key = _spaceKey(leftIndex, rightIndex);
    debugPrint('🎈 Showing spacing overlay: $key');
    if (_spacingOverlays.containsKey(key)) {
      debugPrint('⚠️ Spacing overlay already exists: $key');
      return;
    }

    // בדיקה שהאינדקסים תקינים
    if (leftIndex >= _wordRightEdges.length ||
        rightIndex >= _wordLeftEdges.length) {
      return;
    }

    final overlayState = Overlay.of(context);
    final RenderBox? textFieldBox =
        _textFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (textFieldBox == null) return;
    final textFieldGlobal = textFieldBox.localToGlobal(Offset.zero);
    final midpoint = Offset(
      (_wordRightEdges[leftIndex] + _wordLeftEdges[rightIndex]) / 2,
      _wordPositions[leftIndex].dy - _kSpacingYOffset,
    );
    final overlayPos = textFieldGlobal + midpoint;
    final controller = _spacingControllers.putIfAbsent(key, () {
      final newController = TextEditingController();
      // הוספת listener לעדכון המידע ב-tab כשהטקסט משתנה
      newController.addListener(() => _updateSpacingInTab());
      return newController;
    });
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: overlayPos.dx - 22.5, // מרכוז התיבה החדשה (45/2 = 22.5)
        top: overlayPos.dy - 50,
        child: _SpacingField(
          controller: controller,
          onRemove: () => _removeSpacingOverlay(key),
          onFocusLost: () => _removeSpacingOverlayIfEmpty(key),
          requestFocus: requestFocus, // העברת הפרמטר
        ),
      ),
    );
    _spacingOverlays[key] = entry;
    overlayState.insert(entry);
  }

  void _removeSpacingOverlay(String key) {
    _spacingOverlays[key]?.remove();
    _spacingOverlays.remove(key);
    _spacingControllers[key]?.dispose();
    _spacingControllers.remove(key);
    // עדכון המידע ב-tab אחרי הסרת המרווח
    _updateSpacingInTab();
  }

  void _removeSpacingOverlayIfEmpty(String key) {
    if (_spacingControllers[key]?.text.trim().isEmpty ?? true) {
      _removeSpacingOverlay(key);
    }
  }

  // _buildSpacingButtons הוסר - עכשיו משתמשים בבקר בדיאלוג

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
                        right:
                            BorderSide(color: Colors.grey.shade400, width: 1),
                        bottom:
                            BorderSide(color: Colors.grey.shade400, width: 1),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(
                          left: 48.0, right: 16.0, top: 8.0, bottom: 8.0),
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
    final cursorPosition =
        widget.tab.queryController.selection.baseOffset;

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
        return {
          'word': word,
          'index': i,
          'start': wordStart,
          'end': wordEnd,
        };
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
          '${wordInfo['word']}_${wordInfo['index']}'), // מפתח ייחודי לעדכון
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

  void _updateAlternativeWordsInTab() {
    // עדכון המילים החילופיות ב-tab
    widget.tab.alternativeWords.clear();
    for (int termIndex in _alternativeControllers.keys) {
      final alternatives = _alternativeControllers[termIndex]!
          .map((controller) => controller.text.trim())
          .where((text) => text.isNotEmpty)
          .toList();
      if (alternatives.isNotEmpty) {
        widget.tab.alternativeWords[termIndex] = alternatives;
      }
    }
    // עדכון התצוגה
    widget.tab.alternativeWordsChanged.value++;
    widget.tab.searchOptionsChanged.value++;
  }

  void _updateSpacingInTab() {
    // עדכון המרווחים ב-tab
    widget.tab.spacingValues.clear();
    for (String key in _spacingControllers.keys) {
      final spacingText = _spacingControllers[key]!.text.trim();
      if (spacingText.isNotEmpty) {
        widget.tab.spacingValues[key] = spacingText;
      }
    }
    // עדכון התצוגה
    widget.tab.searchOptionsChanged.value++;
    widget.tab.spacingValuesChanged.value++;
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<NavigationBloc, NavigationState>(
          listener: (context, state) {
            debugPrint('🔄 Navigation changed to: ${state.currentScreen}');

            // תמיד נקה בועות כשמשנים מסך - זה יפתור את הבאג
            // שבו בועות נשארות כשעוברים ממסך אחד לשני (לא דרך החיפוש)
            _clearAllOverlays();

            // אם עוזבים את מסך החיפוש - שמור נתונים
            if (state.currentScreen != Screen.search) {
              debugPrint('📤 Leaving search screen, saving data');
              _saveDataToTab();
            }
            // אם חוזרים למסך החיפוש - שחזר נתונים והצג בועות
            else if (state.currentScreen == Screen.search) {
              debugPrint('📥 Returning to search screen, restoring data');
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _restoreDataFromTab(); // 1. שחזר את תוכן הבועות מהזיכרון
                // עיכוב נוסף כדי לוודא שהטקסט מעודכן
                Future.delayed(const Duration(milliseconds: 50), () {
                  // השאר את העיכוב הקטן הזה
                  if (mounted) {
                    _calculateWordPositions(); // 2. חשב מיקומים (עכשיו זה יעבוד)
                    _showRestoredBubbles(); // 3. הצג את הבועות המשוחזרות
                  }
                });
              });
            }
          },
        ),
        // הוספת listener לשינויי tabs - למקרה שהבעיה קשורה לכך
        BlocListener<TabsBloc, TabsState>(
          listener: (context, state) {
            debugPrint(
                '📑 Tabs changed - current tab index: ${state.currentTabIndex}');
            // אם עברנו לטאב שאינו search tab, נקה בועות
            if (state.currentTabIndex < state.tabs.length) {
              final currentTab = state.tabs[state.currentTabIndex];
              if (currentTab.runtimeType.toString() != 'SearchingTab') {
                debugPrint('📤 Switched to non-search tab, clearing overlays');
                _clearAllOverlays();
              }
            }
          },
        ),
      ],
      child: Stack(
        key: _stackKey,
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
                  child: TextField(
                    key: _textFieldKey,
                    focusNode: widget.tab.searchFieldFocusNode,
                    controller: widget.tab.queryController,
                    onTap: () {
                      // עדכון המגירה כשלוחצים בשדה הטקסט
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_searchOptionsOverlay != null) {
                          _updateSearchOptionsOverlay();
                        }
                      });
                    },
                    onChanged: (text) {
                      // עדכון המגירה כשהטקסט משתנה
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_searchOptionsOverlay != null) {
                          _updateSearchOptionsOverlay();
                        }
                      });
                    },
                    onSubmitted: (e) {
                      context
                          .read<HistoryBloc>()
                          .add(AddHistory(widget.tab));
                      context.read<SearchBloc>().add(UpdateSearchQuery(e.trim(),
                          customSpacing: widget.tab.spacingValues,
                          alternativeWords: widget.tab.alternativeWords,
                          searchOptions: widget.tab.searchOptions));
                      widget.tab.isLeftPaneOpen.value = false;
                    },
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: "חפש כאן..",
                      labelText: "לחיפוש הקש אנטר או לחץ על סמל החיפוש",
                      prefixIcon: IconButton(
                        onPressed: () {
                          context
                              .read<HistoryBloc>()
                              .add(AddHistory(widget.tab));
                          context.read<SearchBloc>().add(UpdateSearchQuery(
                              widget.tab.queryController.text.trim(),
                              customSpacing: widget.tab.spacingValues,
                              alternativeWords:
                                  widget.tab.alternativeWords,
                              searchOptions: widget.tab.searchOptions));
                        },
                        icon: const Icon(FluentIcons.search_24_regular),
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(FluentIcons.dismiss_24_regular),
                        onPressed: () {
                              // ניקוי מלא של כל הנתונים
                              widget.tab.queryController.clear();
                              widget.tab.searchOptions.clear();
                              widget.tab.alternativeWords.clear();
                              widget.tab.spacingValues.clear();
                              _clearAllOverlays();
                              _disposeControllers();
                              setState(() {
                                _searchQuery = SearchQuery();
                                _wordPositions.clear();
                                _wordLeftEdges.clear();
                                _wordRightEdges.clear();
                              });
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
    );
  }
}

