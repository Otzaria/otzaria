import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/search/saved_alternatives_store.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// ווידג'ט לניהול אפשרויות חיפוש מתקדמות לכל מילה בנפרד.
class AdvancedSearchControls extends StatefulWidget {
  final SearchingTab tab;
  final VoidCallback? onEmptySubmit;
  final ValueNotifier<bool>? inputFocusNotifier;

  /// האם להציג את תיבות "ניקוד"/"טעמים" — רק במסלולים שמריצים חיפוש
  /// אינדקס. חיפוש בתוך ספר פתוח רץ מקומית ואינו תומך בהתאמת ניקוד,
  /// והצגת הפקד שם הייתה בחירה שנבלעת בלי השפעה.
  final bool supportsVocalized;
  final TextEditingController? queryController;
  final FocusNode? searchFieldFocusNode;
  final Map<String, Map<String, bool>>? searchOptions;
  final Map<String, bool>? globalSearchOptions;
  final ValueNotifier<bool>? useGlobalSearchOptions;
  final Map<int, List<String>>? alternativeWords;
  final Map<String, String>? spacingValues;
  final ValueNotifier<int>? searchOptionsChanged;
  final ValueNotifier<int>? alternativeWordsChanged;
  final ValueNotifier<int>? spacingValuesChanged;
  final bool enableSavedAlternatives;

  const AdvancedSearchControls({
    super.key,
    required this.tab,
    this.onEmptySubmit,
    this.inputFocusNotifier,
    this.supportsVocalized = false,
    this.queryController,
    this.searchFieldFocusNode,
    this.searchOptions,
    this.globalSearchOptions,
    this.useGlobalSearchOptions,
    this.alternativeWords,
    this.spacingValues,
    this.searchOptionsChanged,
    this.alternativeWordsChanged,
    this.spacingValuesChanged,
    this.enableSavedAlternatives = true,
  });

  @override
  State<AdvancedSearchControls> createState() => _AdvancedSearchControlsState();
}

class _AdvancedSearchControlsState extends State<AdvancedSearchControls> {
  final TextEditingController _alternativeWordController =
      TextEditingController();
  final Map<String, TextEditingController> _spacingControllers = {};
  final Map<String, FocusNode> _spacingFocusNodes = {};
  final FocusNode _alternativeWordFocusNode = FocusNode();
  final List<String> _currentAlternatives = [];

  String? _currentWord;
  int? _wordIndex;
  List<String> _words = [];

  // כל מילות-המנוע שהבחירה בשדה חופפת. בסמן נקודתי — מילה בודדת;
  // בבחירת טווח — כל מה שהבחירה תופסת. תיבות האפשרויות חלות על כולן.
  List<QueryWordSpan> _selectedSpans = [];

  TextEditingController get _queryController =>
      widget.queryController ?? widget.tab.queryController;
  FocusNode get _searchFieldFocusNode =>
      widget.searchFieldFocusNode ?? widget.tab.searchFieldFocusNode;
  Map<String, Map<String, bool>> get _searchOptions =>
      widget.searchOptions ?? widget.tab.searchOptions;
  Map<String, bool> get _globalSearchOptions =>
      widget.globalSearchOptions ?? widget.tab.globalSearchOptions;
  ValueNotifier<bool> get _useGlobalSearchOptions =>
      widget.useGlobalSearchOptions ?? widget.tab.useGlobalSearchOptions;
  Map<int, List<String>> get _alternativeWords =>
      widget.alternativeWords ?? widget.tab.alternativeWords;
  Map<String, String> get _spacingValues =>
      widget.spacingValues ?? widget.tab.spacingValues;
  ValueNotifier<int> get _searchOptionsChanged =>
      widget.searchOptionsChanged ?? widget.tab.searchOptionsChanged;
  ValueNotifier<int> get _alternativeWordsChanged =>
      widget.alternativeWordsChanged ?? widget.tab.alternativeWordsChanged;
  ValueNotifier<int> get _spacingValuesChanged =>
      widget.spacingValuesChanged ?? widget.tab.spacingValuesChanged;

  @override
  void initState() {
    super.initState();
    _queryController.addListener(_onQueryChanged);
    _searchFieldFocusNode.addListener(_onFocusChanged);
    _useGlobalSearchOptions.addListener(_onGlobalModeChanged);
    _alternativeWordFocusNode.addListener(_updateInputFocusState);
    _analyzeCurrentWord();
  }

  @override
  void dispose() {
    _queryController.removeListener(_onQueryChanged);
    _searchFieldFocusNode.removeListener(_onFocusChanged);
    _useGlobalSearchOptions.removeListener(_onGlobalModeChanged);
    _alternativeWordFocusNode.removeListener(_updateInputFocusState);
    _alternativeWordController.dispose();
    _alternativeWordFocusNode.dispose();
    for (final controller in _spacingControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _spacingFocusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _onGlobalModeChanged() {
    if (mounted) setState(() {});
  }

  void _onQueryChanged() {
    if (mounted) _analyzeCurrentWord();
  }

  void _onFocusChanged() {
    if (mounted) _analyzeCurrentWord();
  }

  void _updateInputFocusState() {
    if (widget.inputFocusNotifier == null) return;
    final hasSpacingFocus = _spacingFocusNodes.values.any(
      (node) => node.hasFocus,
    );
    widget.inputFocusNotifier!.value =
        _alternativeWordFocusNode.hasFocus || hasSpacingFocus;
  }

  void _analyzeCurrentWord() {
    final text = _queryController.text;
    final selection = _queryController.selection;

    if (text.isEmpty || selection.baseOffset < 0) {
      if (_currentWord != null || _selectedSpans.isNotEmpty) {
        setState(() {
          _currentWord = null;
          _wordIndex = null;
          _selectedSpans = [];
          _currentAlternatives.clear();
        });
      }
      return;
    }

    // משתמשים באותה פיצול כמו מנוע החיפוש (`splitQueryWords`),
    // כך שמפתחות `${_currentWord}_$_wordIndex` ואינדקסי `alternativeWords` /
    // `spacingValues` שנשמרים פר-מילה יתאימו לחיפוש בפועל.
    // ללא יישור זה, שאילתות כמו `רמב"ם` מצרות מפתחות שאינם נקראים.
    _words = SearchQueryBuilder.splitQueryWords(text);

    // המיפוי מהבחירה למילים — דרך queryWordSpans, שמאתר כל מילת-מנוע
    // בטקסט הגולמי (כולל ׳/״ עבריים בשדה ומקטעים משני-אורך כמו
    // `רמב''ם`, שמקבלים את גבולות המקטע כולו).
    final spans = SearchQueryBuilder.queryWordSpans(text);
    final base = selection.baseOffset;
    final extent = selection.extentOffset < 0 ? base : selection.extentOffset;
    final selStart = base < extent ? base : extent;
    final selEnd = base < extent ? extent : base;

    final List<QueryWordSpan> selected;
    if (selStart == selEnd) {
      // סמן נקודתי — המילה הבודדת שהסמן בתוכה
      final span = spans.cast<QueryWordSpan?>().firstWhere(
        (s) => selStart >= s!.start && selStart <= s.end,
        orElse: () => null,
      );
      selected = span == null ? const [] : [span];
    } else {
      // בחירת טווח — כל מילה שהבחירה חופפת בפועל
      selected = spans
          .where((s) => s.end > selStart && s.start < selEnd)
          .toList();
    }

    final anchor = selected.isNotEmpty ? selected.first : null;
    // השוואה לפי המפתח המלא `word_index` — אינדקס לבדו יחמיץ שינוי טקסט
    // של מילה לא-ראשונה בטווח, וישאיר מפתח ישן לכתיבת האפשרויות.
    final changed = !listEquals(
      selected.map((s) => '${s.word}_${s.index}').toList(),
      _selectedSpans.map((s) => '${s.word}_${s.index}').toList(),
    );

    if (changed) {
      setState(() {
        _selectedSpans = selected;
        _wordIndex = anchor?.index;
        _currentWord = anchor?.word;
        _updateLocalStateForWord(anchor?.index);
      });
    }
  }

  void _updateLocalStateForWord(int? index) {
    if (index == null) {
      _currentAlternatives.clear();
      return;
    }

    _currentAlternatives.clear();
    final alts = _alternativeWords[index];
    if (alts != null) {
      _currentAlternatives.addAll(alts);
    }
    // כשהמתג דלוק — החלופות השמורות של המילה מוצגות ברשימה כרגילות
    if (widget.enableSavedAlternatives &&
        widget.tab.useSavedAlternatives &&
        index < _words.length) {
      final word = _words[index];
      for (final alt in SavedAlternativesStore.alternativesFor(word)) {
        if (alt != word && !_currentAlternatives.contains(alt)) {
          _currentAlternatives.add(alt);
        }
      }
    }

    final wordsCount = _words.where((w) => w.isNotEmpty).length;
    if (index < wordsCount - 1) {
      final key = '$index-${index + 1}';
      final spacing = _spacingValues[key] ?? '';
      _getSpacingController(index, index + 1).text = spacing;
    }
  }

  TextEditingController _getSpacingController(int leftIndex, int rightIndex) {
    final key = '$leftIndex-$rightIndex';
    return _spacingControllers.putIfAbsent(key, () => TextEditingController());
  }

  FocusNode _getSpacingFocusNode(int leftIndex, int rightIndex) {
    final key = '$leftIndex-$rightIndex';
    return _spacingFocusNodes.putIfAbsent(key, () {
      final node = FocusNode();
      node.addListener(_updateInputFocusState);
      return node;
    });
  }

  void _navigateToWord(int newIndex) {
    if (newIndex < 0 || newIndex >= _words.length) return;

    // queryWordSpans מחזיר טווח לכל מילת-מנוע בטקסט הגולמי; מילה
    // שאינה ניתנת לאיתור מדויק (נורמליזציה משנת-אורך) מקבלת את גבולות
    // המקטע שלה — הצבת הסמן באמצע הטווח נכונה בשני המקרים.
    final spans = SearchQueryBuilder.queryWordSpans(
      _queryController.text,
    );
    if (newIndex >= spans.length) return;
    final span = spans[newIndex];
    _queryController.selection = TextSelection.collapsed(
      offset: span.start + (span.end - span.start) ~/ 2,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWordSelected = _currentWord != null && _wordIndex != null;
    final useGlobal = _useGlobalSearchOptions.value;
    // תיבות האפשרויות פעילות אם במצב גלובלי או אם נבחרה מילה
    final optionsEnabled = useGlobal || isWordSelected;
    // מרווח/מילה חילופית עובדים על מילה בודדת בלבד — מנוטרלים בבחירת טווח
    final perWordInputsEnabled = isWordSelected && _selectedSpans.length <= 1;

    // המתגים ממוקמים לצד שורת הניווט; ברוחב צר יורדים לשורה נפרדת
    final navigationWithToggle = LayoutBuilder(
      builder: (context, constraints) {
        final toggles = Wrap(
          spacing: 8,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: [
            _buildSavedAlternativesToggle(),
            _buildScopeToggle(),
          ],
        );
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildNavigationRow(isWordSelected),
              const SizedBox(height: 4),
              toggles,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: _buildNavigationRow(isWordSelected)),
            toggles,
          ],
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        navigationWithToggle,
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            'אפשרויות מילה',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildOptionChips(optionsEnabled),
        if (perWordInputsEnabled) ...[
          const SizedBox(height: 12),
          _buildInputColumn(perWordInputsEnabled),
        ],
        const SizedBox(height: 4),
        _buildSaveDefaultsRow(),
      ],
    );
  }

  /// מתג הרחבת החיפוש בחלופות השמורות — כבוי בכל חיפוש חדש.
  Widget _buildSavedAlternativesToggle() {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled =
        widget.enableSavedAlternatives && widget.tab.useSavedAlternatives;

    return Tooltip(
      message: enabled
          ? 'החיפוש יורחב במילים החילופיות שנשמרו עבור מילות השאילתה'
          : 'הפעל כדי להרחיב את החיפוש במילים החילופיות שנשמרו',
      child: Container(
        decoration: BoxDecoration(
          color: AppSurfaces.togglePill(colorScheme, active: enabled),
          borderRadius: AppTokens.borderRadiusAll,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'חלופות שמורות',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: enabled
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            Transform.scale(
              scale: 0.75,
              child: Switch(
                value: enabled,
                onChanged: (value) {
                  setState(() {
                    widget.tab.useSavedAlternatives = value;
                    _updateLocalStateForWord(_wordIndex);
                  });
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// תפריט נפתח לסימון אילו אפשרויות מופעלות כברירת מחדל בחיפוש חדש,
  /// ולצדו לחצן שמאפס את האפשרויות הנוכחיות לברירת המחדל השמורה.
  Widget _buildSaveDefaultsRow() {
    final defaults = SearchDefaults.loadDefaults();
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Wrap(
        spacing: 4,
        children: [
          MenuAnchor(
            menuChildren: [
              // "ניקוד"/"טעמים" מוצעות רק במסלולים שתומכים בחיפוש מנוקד —
              // כברירת מחדל הן מגבילות כל חיפוש חדש לטקסטים מנוקדים בלבד.
              for (final key in [
                ...SearchQueryBuilder.availableWordOptionKeys,
                ...SearchQueryBuilder.advancedOnlyWordOptionKeys,
                if (widget.supportsVocalized)
                  ...SearchQueryBuilder.vocalizedWordOptionKeys,
              ])
                CheckboxMenuButton(
                  value: defaults[key] ?? false,
                  closeOnActivate: false,
                  onChanged: (checked) {
                    setState(() {
                      SearchDefaults.saveDefaults({
                        ...defaults,
                        key: checked ?? false,
                      });
                      // שינוי ברירת מחדל מוחל מיד גם על הריבוע בחלונית הפתוחה
                      _globalSearchOptions[key] = checked ?? false;
                    });
                    _searchOptionsChanged.value++;
                  },
                  child: Text(key),
                ),
            ],
            builder: (context, controller, _) => Tooltip(
              message: 'סמן אילו אפשרויות יופעלו אוטומטית בכל חיפוש חדש',
              child: ActionButton.ghost(
                text: 'ברירת מחדל לחיפוש חדש',
                icon: FluentIcons.options_24_regular,
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              ),
            ),
          ),
          Tooltip(
            message: 'החזרת האפשרויות המסומנות למצב ברירת המחדל השמורה',
            child: ActionButton.ghost(
              text: 'חזרה לברירת מחדל',
              icon: FluentIcons.arrow_reset_24_regular,
              onPressed: () {
                setState(() {
                  _globalSearchOptions
                    ..clear()
                    ..addAll(SearchDefaults.loadDefaults());
                  _searchOptions.clear();
                });
                _searchOptionsChanged.value++;
              },
            ),
          ),
        ],
      ),
    );
  }

  /// מתג קומפקטי לבחירת היקף ההגדרות: גלובלי לכל המילים או פר-מילה.
  Widget _buildScopeToggle() {
    final colorScheme = Theme.of(context).colorScheme;
    final useGlobal = _useGlobalSearchOptions.value;

    return Tooltip(
      message: useGlobal
          ? 'ההגדרות חלות על כל המילים בשאילתה ולא משתנות בעת שינוי המילים'
          : 'ההגדרות נשמרות לכל מילה בנפרד',
      child: Container(
        decoration: BoxDecoration(
          color: AppSurfaces.togglePill(colorScheme, active: useGlobal),
          borderRadius: AppTokens.borderRadiusAll,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'זהה לכל המילים',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: useGlobal
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            Transform.scale(
              scale: 0.75,
              child: Switch(
                value: useGlobal,
                onChanged: (value) {
                  _useGlobalSearchOptions.value = value;
                  _searchOptionsChanged.value++;
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationRow(bool isEnabled) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(FluentIcons.chevron_left_24_regular),
          onPressed: isEnabled && _wordIndex! > 0
              ? () => _navigateToWord(_wordIndex! - 1)
              : null,
          tooltip: 'מילה קודמת',
        ),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isEnabled
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: AppTokens.borderRadiusAll,
            ),
            child: Text(
              !isEnabled
                  ? 'בחר מילה'
                  : _selectedSpans.length > 1
                  ? '${_selectedSpans.length} מילים נבחרו'
                  : _currentWord!,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isEnabled
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(FluentIcons.chevron_right_24_regular),
          onPressed: isEnabled && _wordIndex! < _words.length - 1
              ? () => _navigateToWord(_wordIndex! + 1)
              : null,
          tooltip: 'מילה הבאה',
        ),
      ],
    );
  }

  Widget _buildInputColumn(bool isEnabled) {
    final spacingController = _wordIndex != null
        ? _getSpacingController(_wordIndex!, _wordIndex! + 1)
        : null;

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Opacity(
                opacity: isEnabled ? 1.0 : 0.5,
                child: RtlTextField(
                  enabled: isEnabled,
                  controller: spacingController,
                  focusNode: isEnabled && _wordIndex != null
                      ? _getSpacingFocusNode(_wordIndex!, _wordIndex! + 1)
                      : null,
                  decoration: InputDecoration(
                    labelText: 'מרווח למילה הבאה',
                    hintText: '0-30',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(
                        FluentIcons.dismiss_24_regular,
                        size: 20,
                      ),
                      onPressed: isEnabled && _wordIndex != null
                          ? () {
                              final key = '${_wordIndex!}-${_wordIndex! + 1}';
                              _spacingValues.remove(key);
                              _spacingValuesChanged.value++;
                              _getSpacingController(
                                _wordIndex!,
                                _wordIndex! + 1,
                              ).clear();
                            }
                          : null,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^([0-9]|[12][0-9]|30)$'),
                    ),
                  ],
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.right,
                  onChanged: (text) {
                    if (isEnabled &&
                        _wordIndex != null &&
                        text.trim().isNotEmpty) {
                      final key = '${_wordIndex!}-${_wordIndex! + 1}';
                      _spacingValues[key] = text.trim();
                      _spacingValuesChanged.value++;
                    }
                  },
                  onSubmitted: (text) {
                    if (text.trim().isNotEmpty && _wordIndex != null) {
                      final key = '${_wordIndex!}-${_wordIndex! + 1}';
                      _spacingValues[key] = text.trim();
                      _spacingValuesChanged.value++;
                      widget.onEmptySubmit?.call();
                    } else {
                      widget.onEmptySubmit?.call();
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: RtlTextField(
                controller: _alternativeWordController,
                focusNode: _alternativeWordFocusNode,
                enabled: isEnabled,
                decoration: InputDecoration(
                  labelText: 'מילה חילופית',
                  hintText: 'הקלד מילה...',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  prefixIcon: IconButton(
                    icon: const Icon(FluentIcons.add_24_regular, size: 20),
                    onPressed: isEnabled ? _addAlternative : null,
                  ),
                ),
                style: const TextStyle(fontSize: 14),
                textAlign: TextAlign.right,
                onSubmitted: (text) {
                  if (text.trim().isNotEmpty) {
                    _addAlternative();
                  } else {
                    widget.onEmptySubmit?.call();
                  }
                },
              ),
            ),
          ],
        ),
        if (_currentAlternatives.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildAlternativeWordsList(),
        ],
      ],
    );
  }

  Widget _buildAlternativeWordsList() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 100),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _currentAlternatives.length,
        itemBuilder: (context, index) {
          return ListTile(
            dense: true,
            title: Text(
              _currentAlternatives[index],
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14),
            ),
            trailing: IconButton(
              icon: const Icon(FluentIcons.delete_24_regular, size: 18),
              onPressed: () => _removeAlternative(index),
            ),
          );
        },
      ),
    );
  }

  void _addAlternative() {
    final text = _alternativeWordController.text.trim();
    if (text.isEmpty || _wordIndex == null) return;

    setState(() {
      if (!_currentAlternatives.contains(text)) {
        _currentAlternatives.add(text);
      }
    });

    _alternativeWords.putIfAbsent(_wordIndex!, () => []);
    if (!_alternativeWords[_wordIndex!]!.contains(text)) {
      _alternativeWords[_wordIndex!]!.add(text);
    }
    _alternativeWordsChanged.value++;
    // כל חלופה שנוספת נשמרת גם במאגר הגלובלי עבור המילה הנוכחית
    SavedAlternativesStore.addAlternative(_currentWord!, text);
    _alternativeWordController.clear();
  }

  void _removeAlternative(int index) {
    if (_wordIndex == null) return;
    final word = _currentAlternatives[index];

    setState(() {
      _currentAlternatives.removeAt(index);
    });

    _alternativeWords[_wordIndex!]?.remove(word);
    if (_alternativeWords[_wordIndex!]?.isEmpty ?? false) {
      _alternativeWords.remove(_wordIndex!);
    }
    _alternativeWordsChanged.value++;
    // הסרה מוחקת את החלופה גם מהמאגר הגלובלי של המילה הנוכחית
    if (_currentWord != null) {
      SavedAlternativesStore.removeAlternative(_currentWord!, word);
    }
  }

  /// הסברים לאפשרויות שהמשמעות שלהן אינה מובנת מהשם לבדו.
  static const Map<String, String> _optionTooltips = {
    SearchQueryBuilder.matchNikudOptionKey:
        'התאמת ניקוד: ניקוד שיוקלד במילה יידרש להופיע בטקסט. החיפוש מוגבל לטקסטים מנוקדים.',
    SearchQueryBuilder.matchTaamimOptionKey:
        'התאמת טעמי המקרא: טעם שיוקלד במילה יידרש להופיע בטקסט. החיפוש מוגבל לטקסטים מוטעמים.',
    'קידומות ארמיות':
        'קידומות ארמיות (ד/כד/מד/אד...) לפני המילה: מלכא ימצא גם דמלכא, כדמלכא.',
    'סיומות ארמיות':
        'שקילות אות סופית ארמית: ה↔א (מלכה↔מלכא) ו-ם↔ן (חכמים↔חכמין).',
    'התעלם מגרשיים':
        'גרש/גרשיים שהוקלדו במילה לא יידרשו בטקסט: רמב"ם ימצא גם רמבם, ולהפך.',
    'תרגום ארמי':
        'הרחבת המילה בתרגומיה מהמילון הארמי-עברי, בשני הכיוונים (איתא↔יש).',
    'ראשי תיבות':
        'פענוח ראשי-תיבות בשני הכיוונים: רמב"ם ימצא גם "רבי משה בן מיימון", ולהפך. פועל כשהשאילתה היא ראשי-התיבות או הפענוח בשלמותו.',
  };

  /// תיבות אפשרויות המילה כ-FilterChips — אותו מראה כמו בחיפוש הרגיל.
  /// במצב גלובלי הסימון חל על כל המילים; במצב פר-מילה על המילה הנבחרת.
  Widget _buildOptionChips(bool isEnabled) {
    final options = [
      ...SearchQueryBuilder.availableWordOptionKeys,
      ...SearchQueryBuilder.advancedOnlyWordOptionKeys,
      if (widget.supportsVocalized)
        ...SearchQueryBuilder.vocalizedWordOptionKeys,
    ];

    final useGlobal = _useGlobalSearchOptions.value;

    Widget buildChip(String option) {
      bool isChecked = false;
      if (isEnabled) {
        if (useGlobal) {
          isChecked = _globalSearchOptions[option] ?? false;
        } else {
          // מסומן רק אם כל המילים הנבחרות מסומנות — אחרת מצב מעורב מוצג ככבוי
          isChecked =
              _selectedSpans.isNotEmpty &&
              _selectedSpans.every(
                (s) => _searchOptions['${s.word}_${s.index}']?[option] ?? false,
              );
        }
      }

      final chip = FilterChip(
        label: Text(option),
        visualDensity: VisualDensity.compact,
        selected: isChecked,
        onSelected: isEnabled
            ? (selected) {
                setState(() {
                  if (useGlobal) {
                    _globalSearchOptions[option] = selected;
                  } else {
                    for (final s in _selectedSpans) {
                      final key = '${s.word}_${s.index}';
                      _searchOptions.putIfAbsent(key, () => {});
                      _searchOptions[key]![option] = selected;
                    }
                  }
                });
                _searchOptionsChanged.value++;
              }
            : null,
      );
      final tooltip = _optionTooltips[option];
      return tooltip == null ? chip : Tooltip(message: tooltip, child: chip);
    }

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: options.map(buildChip).toList(),
      ),
    );
  }
}
