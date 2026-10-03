import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/book_common/utils/category_settings_utils.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria/widgets/dialogs/category_commentators_dialog.dart';
import 'package:otzaria/widgets/lists/filter_chips_widget.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';

@visibleForTesting
const Key commentatorEraChipsGroupKey = Key('commentator_era_chips_group');

@visibleForTesting
const Key commentatorTypeChipsGroupKey = Key('commentator_type_chips_group');

@visibleForTesting
const Key commentatorChipAxesDividerKey = Key('commentator_chip_axes_divider');

class CommentatorsSelectionPanel extends StatefulWidget {
  final List<CommentatorGroup> groups;
  final List<String> selectedCommentators;
  final ValueChanged<List<String>> onSelectionChanged;
  final VoidCallback? onSelectionApplied;
  final String bookTitle;
  final Widget? emptyState;

  /// מפרשים "נדירים" שמוסתרים מהרשימה, אלא אם הם ב-[lineRelevantCommentators].
  final Set<String> rareCommentators;

  /// מפרשים נדירים שכן יוצגו כי השורה הנוכחית כוללת קישור מהם.
  final Set<String> lineRelevantCommentators;

  /// מפתחות צ׳יפי הסינון לפי *סוג* הקישור, המוצגים משמאל לצ׳יפי הדורות.
  /// ריק = ציר הסוגים אינו מוצג כלל.
  final List<String> typeChipKeys;

  final Set<String> selectedTypeChips;

  final ValueChanged<Set<String>>? onTypeChipsChanged;

  /// תווית להצגה עבור מפתח סוג. ברירת המחדל: המפתח עצמו.
  final String Function(String key)? typeChipLabelBuilder;

  /// שמות המפרשים שיש להם קישור מכל סוג. בחירת צ׳יפ סוג מצמצמת את רשימת
  /// המפרשים לאלה בלבד, בדיוק כפי שצ׳יפ דור מצמצם אותה. ריק = אין צמצום.
  final Map<String, Set<String>> commentatorsByType;

  /// שרשרת הקטגוריות של הספר. כשיש קטגוריות, מוצג כפתור "קבע כמפרשים
  /// קבועים לקטגוריה" בכותרת הרשימה (issue #866).
  final String? heCategories;

  /// נקרא אחרי קביעת מפרשים לקטגוריה — לניקוי הבחירה הפר-ספרית הנוכחית.
  final VoidCallback? onCategoryDefaultsSaved;

  const CommentatorsSelectionPanel({
    super.key,
    required this.groups,
    required this.selectedCommentators,
    required this.onSelectionChanged,
    required this.bookTitle,
    this.onSelectionApplied,
    this.emptyState,
    this.rareCommentators = const {},
    this.lineRelevantCommentators = const {},
    this.typeChipKeys = const [],
    this.selectedTypeChips = const {},
    this.onTypeChipsChanged,
    this.typeChipLabelBuilder,
    this.commentatorsByType = const {},
    this.heCategories,
    this.onCategoryDefaultsSaved,
  });

  @override
  State<CommentatorsSelectionPanel> createState() =>
      _CommentatorsSelectionPanelState();
}

class _CommentatorsSelectionPanelState
    extends State<CommentatorsSelectionPanel> {
  static const String _torahShebichtavTitle = '__TITLE_TORAH_SHEBICHTAV__';
  static const String _chazalTitle = '__TITLE_CHAZAL__';
  static const String _rishonimTitle = '__TITLE_RISHONIM__';
  static const String _acharonimTitle = '__TITLE_ACHARONIM__';
  static const String _modernTitle = '__TITLE_MODERN__';
  static const String _ungroupedTitle = '__TITLE_UNGROUPED__';
  static const String _torahShebichtavButton = '__BUTTON_TORAH_SHEBICHTAV__';
  static const String _chazalButton = '__BUTTON_CHAZAL__';
  static const String _rishonimButton = '__BUTTON_RISHONIM__';
  static const String _acharonimButton = '__BUTTON_ACHARONIM__';
  static const String _modernButton = '__BUTTON_MODERN__';
  static const String _ungroupedButton = '__BUTTON_UNGROUPED__';

  final TextEditingController _searchController = TextEditingController();
  List<String> _selectedTopics = [];
  List<String> _commentatorsList = [];
  List<String> _torahShebichtav = [];
  List<String> _chazal = [];
  List<String> _rishonim = [];
  List<String> _acharonim = [];
  List<String> _modern = [];
  List<String> _ungrouped = [];

  @override
  void initState() {
    super.initState();
    _update();
  }

  @override
  void didUpdateWidget(CommentatorsSelectionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groups != widget.groups ||
        oldWidget.bookTitle != widget.bookTitle ||
        !setEquals(oldWidget.rareCommentators, widget.rareCommentators) ||
        !setEquals(
          oldWidget.lineRelevantCommentators,
          widget.lineRelevantCommentators,
        ) ||
        !setEquals(oldWidget.selectedTypeChips, widget.selectedTypeChips) ||
        !_sameCommentatorsByType(
          oldWidget.commentatorsByType,
          widget.commentatorsByType,
        )) {
      _update();
    }
  }

  /// השוואה עמוקה. `mapEquals` היה משווה את ה-Set-ים בזהות, ומאחר שהמפה
  /// נבנית מחדש בכל build הוא תמיד החזיר false ו-_update רץ בכל rebuild.
  bool _sameCommentatorsByType(
    Map<String, Set<String>> a,
    Map<String, Set<String>> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null || !setEquals(entry.value, other)) return false;
    }
    return true;
  }

  /// מפרש נדיר מוסתר מהרשימה אלא אם השורה הנוכחית כוללת קישור מהם.
  bool _isCommentatorVisible(String title) {
    if (!widget.rareCommentators.contains(title)) return true;
    return widget.lineRelevantCommentators.contains(title);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// שמות המפרשים המותרים לפי צ׳יפי הסוג שנבחרו. null = אין סינון סוג.
  Set<String>? _titlesAllowedByType() {
    if (widget.selectedTypeChips.isEmpty || widget.commentatorsByType.isEmpty) {
      return null;
    }
    final allowed = <String>{};
    for (final type in widget.selectedTypeChips) {
      allowed.addAll(widget.commentatorsByType[type] ?? const {});
    }
    return allowed;
  }

  Future<List<String>> _filterGroup(List<String> group) async {
    final allowedByType = _titlesAllowedByType();
    final filteredByQuery = group
        .where(_isCommentatorVisible)
        .where((title) => allowedByType?.contains(title) ?? true)
        .where((title) => title.contains(_searchController.text));

    if (_selectedTopics.isEmpty) {
      return filteredByQuery.toList();
    }

    final filtered = <String>[];
    for (final title in filteredByQuery) {
      for (final topic in _selectedTopics) {
        if (await hasTopic(title, topic)) {
          filtered.add(title);
          break;
        }
      }
    }

    return filtered;
  }

  Future<void> _update() async {
    final torahShebichtav = await _filterGroup(
      CommentatorGroup.groupByTitle(widget.groups, 'תורה שבכתב').commentators,
    );
    final chazal = await _filterGroup(
      CommentatorGroup.groupByTitle(widget.groups, 'חז"ל').commentators,
    );
    final rishonim = await _filterGroup(
      CommentatorGroup.groupByTitle(widget.groups, 'ראשונים').commentators,
    );
    final acharonim = await _filterGroup(
      CommentatorGroup.groupByTitle(widget.groups, 'אחרונים').commentators,
    );
    final modern = await _filterGroup(
      CommentatorGroup.groupByTitle(widget.groups, 'מחברי זמננו').commentators,
    );
    final ungrouped = await _filterGroup(
      CommentatorGroup.groupByTitle(widget.groups, 'שאר מפרשים').commentators,
    );

    final merged = <String>[];

    if (torahShebichtav.isNotEmpty) {
      merged.add(_torahShebichtavTitle);
      merged.add(_torahShebichtavButton);
      merged.addAll(torahShebichtav);
    }
    if (chazal.isNotEmpty) {
      merged.add(_chazalTitle);
      merged.add(_chazalButton);
      merged.addAll(chazal);
    }
    if (rishonim.isNotEmpty) {
      merged.add(_rishonimTitle);
      merged.add(_rishonimButton);
      merged.addAll(rishonim);
    }
    if (acharonim.isNotEmpty) {
      merged.add(_acharonimTitle);
      merged.add(_acharonimButton);
      merged.addAll(acharonim);
    }
    if (modern.isNotEmpty) {
      merged.add(_modernTitle);
      merged.add(_modernButton);
      merged.addAll(modern);
    }
    if (ungrouped.isNotEmpty) {
      merged.add(_ungroupedTitle);
      merged.add(_ungroupedButton);
      merged.addAll(ungrouped);
    }

    if (!mounted) return;

    setState(() {
      _torahShebichtav = torahShebichtav;
      _chazal = chazal;
      _rishonim = rishonim;
      _acharonim = acharonim;
      _modern = modern;
      _ungrouped = ungrouped;
      _commentatorsList = merged;
    });
  }

  void _emitSelection(List<String> commentators) {
    widget.onSelectionChanged(_orderSelection(commentators));
    widget.onSelectionApplied?.call();
  }

  List<String> _selectionOrder() {
    return [
      ..._torahShebichtav,
      ..._chazal,
      ..._rishonim,
      ..._acharonim,
      ..._modern,
      ..._ungrouped,
    ];
  }

  List<String> _orderSelection(List<String> commentators) {
    final unique = commentators.toSet();
    final ordered = <String>[];
    final order = _selectionOrder();

    for (final commentator in order) {
      if (unique.remove(commentator)) {
        ordered.add(commentator);
      }
    }

    if (unique.isNotEmpty) {
      ordered.addAll(unique);
    }

    return ordered;
  }

  void _toggleSingleCommentator(String commentator, bool selected) {
    if (selected) {
      _emitSelection([...widget.selectedCommentators, commentator]);
      return;
    }

    _emitSelection(
      widget.selectedCommentators.where((item) => item != commentator).toList(),
    );
  }

  void _toggleGroup(List<String> group, bool selected) {
    final current = List<String>.from(widget.selectedCommentators);
    if (selected) {
      for (final commentator in group) {
        if (!current.contains(commentator)) {
          current.add(commentator);
        }
      }
      _emitSelection(current);
      return;
    }

    current.removeWhere(group.contains);
    _emitSelection(current);
  }

  void _toggleAllVisible(bool selected) {
    final items = _visibleCommentators.toList();

    if (selected) {
      _emitSelection({...widget.selectedCommentators, ...items}.toList());
      return;
    }

    _emitSelection(
      widget.selectedCommentators
          .where((item) => !items.contains(item))
          .toList(),
    );
  }

  String _titleTextForToken(String item) {
    switch (item) {
      case _torahShebichtavTitle:
        return 'תורה שבכתב';
      case _chazalTitle:
        return 'חז"ל';
      case _rishonimTitle:
        return 'ראשונים';
      case _acharonimTitle:
        return 'אחרונים';
      case _modernTitle:
        return 'מחברי זמננו';
      case _ungroupedTitle:
        return 'שאר מפרשים';
      default:
        return '';
    }
  }

  /// צ׳יפי הדורות ("תורה שבכתב", "ראשונים"...) ו"על <הספר>" — ציר הסינון
  /// שמימין. מוצג רק דור שיש לו מפרשים בפועל.
  List<String> _eraChipItems() => [
    if (CommentatorGroup.groupByTitle(
      widget.groups,
      'תורה שבכתב',
    ).commentators.isNotEmpty)
      'תורה שבכתב',
    if (CommentatorGroup.groupByTitle(
      widget.groups,
      'חז"ל',
    ).commentators.isNotEmpty)
      'חז"ל',
    if (CommentatorGroup.groupByTitle(
      widget.groups,
      'ראשונים',
    ).commentators.isNotEmpty)
      'ראשונים',
    if (CommentatorGroup.groupByTitle(
      widget.groups,
      'אחרונים',
    ).commentators.isNotEmpty)
      'אחרונים',
    if (CommentatorGroup.groupByTitle(
      widget.groups,
      'מחברי זמננו',
    ).commentators.isNotEmpty)
      'מחברי זמננו',
    'על ${widget.bookTitle}',
  ];

  /// שורת הצ׳יפים: דורות מימין, סוגי קישור משמאל — שני צירי סינון נפרדים,
  /// בעיצוב זהה לשורת הצ׳יפים בפאנל הקישורים.
  Widget _buildChipsRow(BuildContext context) {
    final types = widget.typeChipKeys;
    final typeLabel = widget.typeChipLabelBuilder ?? (String key) => key;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceSM,
        AppTokens.spaceXS,
        AppTokens.spaceSM,
        AppTokens.spaceXS,
      ),
      // IntrinsicHeight נותן לקו המפריד גובה גם כשציר אחד גולש לשתי שורות
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Expanded ולא Flexible: חצי-חצי קבוע, כדי שהקו המפריד יישאר
            // במרכז ולא ינוע לפי רוחב התוכן של כל ציר.
            Expanded(
              child: _buildChipGroup(
                key: commentatorEraChipsGroupKey,
                items: _eraChipItems(),
                selected: _selectedTopics,
                labelBuilder: (item) => item,
                onSelectionChanged: (list) {
                  _selectedTopics = list;
                  _update();
                },
              ),
            ),
            if (types.isNotEmpty) ...[
              const VerticalDivider(
                key: commentatorChipAxesDividerKey,
                // width הוא הרוחב הכולל והקו מצויר במרכזו — כך נוצר ריווח
                // משני צדיו וצ׳יפ בקצה הציר אינו נצמד אליו.
                width: AppTokens.spaceSM * 2 + 1,
                thickness: 1,
                indent: AppTokens.spaceXS,
                endIndent: AppTokens.spaceXS,
              ),
              Expanded(
                child: _buildChipGroup(
                  key: commentatorTypeChipsGroupKey,
                  items: types,
                  selected: widget.selectedTypeChips.toList(),
                  labelBuilder: typeLabel,
                  onSelectionChanged: (list) =>
                      widget.onTypeChipsChanged?.call(list.toSet()),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChipGroup({
    required Key key,
    required List<String> items,
    required List<String> selected,
    required String Function(String item) labelBuilder,
    required ValueChanged<List<String>> onSelectionChanged,
  }) {
    return KeyedSubtree(
      key: key,
      child: FilterChipsSelector<String>(
        items: items,
        selectedItems: selected,
        labelBuilder: labelBuilder,
        wrapAlignment: WrapAlignment.center,
        wrapSpacing: AppTokens.spaceXS,
        runSpacing: AppTokens.spaceXS,
        padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceXS),
        onSelectionChanged: onSelectionChanged,
        chipBuilder: (context, item, isSelected) => Chip(
          label: Text(labelBuilder(item)),
          backgroundColor: isSelected
              ? Theme.of(context).colorScheme.secondary
              : null,
          labelStyle: TextStyle(
            color: isSelected
                ? Theme.of(context).colorScheme.onSecondary
                : null,
            fontSize: 10,
          ),
          labelPadding: EdgeInsets.zero,
          padding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 2,
          ),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  Iterable<String> get _visibleCommentators => _commentatorsList.where(
    (item) => !item.startsWith('__TITLE_') && !item.startsWith('__BUTTON_'),
  );

  /// האם כל המפרשים המוצגים כרגע מסומנים.
  bool get _allVisibleSelected {
    var hasVisible = false;
    for (final commentator in _visibleCommentators) {
      hasVisible = true;
      if (!widget.selectedCommentators.contains(commentator)) return false;
    }
    return hasVisible;
  }

  /// תיבת סימון קומפקטית לשורת מפרש — ה-trailing של שורת עץ הניווט.
  Widget _selectionCheckbox({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Checkbox(
      value: value,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onChanged: (checked) => onChanged(checked ?? false),
    );
  }

  /// כפתור "קבע כמפרשים קבועים לקטגוריה" — מוצג רק כשלספר יש קטגוריות.
  Widget? _buildCategoryDefaultsButton(BuildContext context) {
    if (parseBookCategories(widget.heCategories).isEmpty) return null;
    return IconButton(
      tooltip: 'קבע כמפרשים קבועים לקטגוריה',
      icon: const Icon(FluentIcons.save_24_regular, size: 18),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: () => showCategoryCommentatorsDialog(
        context: context,
        bookTitle: widget.bookTitle,
        heCategories: widget.heCategories,
        selectedCommentators: widget.selectedCommentators,
        onSaved: widget.onCategoryDefaultsSaved,
      ),
    );
  }

  /// מזהה שורת "הצג את כל ..." ומחזיר את התווית והקבוצה שלה.
  ({String label, List<String> commentators})? _groupForButtonToken(
    String item,
  ) {
    switch (item) {
      case _torahShebichtavButton:
        return (label: 'הצג את כל התורה שבכתב', commentators: _torahShebichtav);
      case _chazalButton:
        return (label: 'הצג את כל חז"ל', commentators: _chazal);
      case _rishonimButton:
        return (label: 'הצג את כל הראשונים', commentators: _rishonim);
      case _acharonimButton:
        return (label: 'הצג את כל האחרונים', commentators: _acharonim);
      case _modernButton:
        return (label: 'הצג את כל מחברי זמננו', commentators: _modern);
      case _ungroupedButton:
        return (label: 'הצג את כל שאר המפרשים', commentators: _ungrouped);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.groups.every((group) => group.commentators.isEmpty)) {
      return widget.emptyState ??
          const Center(
            child: Text(
              'אין מפרשים',
            ),
          );
    }

    final delegate = NavPanelSearchDelegate(
      controller: _searchController,
      hintText: 'סינון מפרשים...',
      onChanged: (_) => _update(),
      onClear: _update,
    );
    final hasVisibleCommentators = _commentatorsList.isNotEmpty;
    final isSearchEmpty =
        !hasVisibleCommentators && _searchController.text.trim().isNotEmpty;
    final leadingItemCount = hasVisibleCommentators
        ? 2
        : (isSearchEmpty ? 2 : 1);

    return Column(
      children: [
        _buildChipsRow(context),
        Expanded(
          child: NavPanelCollapsibleSearch(
            delegate: delegate,
            child: NavTreeFocusGroup(
              child: ListView.builder(
                padding: kNavTreeListPadding,
                // הכותרת תמיד נגללת; "הצג את כל" או מצב ריק נוסף כשיש צורך.
                itemCount: _commentatorsList.length + leadingItemCount,
                itemBuilder: (context, listIndex) {
                  if (listIndex == 0) {
                    return NavTreeHeader(
                      title: 'מפרשים על ${widget.bookTitle}',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const NavPanelSearchToggle(),
                          ?_buildCategoryDefaultsButton(context),
                        ],
                      ),
                    );
                  }
                  if (isSearchEmpty && listIndex == 1) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 24.0),
                      child: OtzariaEmptyState(
                        isCompact: true,
                        icon: OtzariaIcons.search_in_the_library_24_regular,
                        title: 'לא נמצאו מפרשים תואמים',
                      ),
                    );
                  }
                  if (hasVisibleCommentators && listIndex == 1) {
                    final allVisibleSelected = _allVisibleSelected;
                    return NavTreeGroupCard(
                      isGroupStart: true,
                      isGroupEnd: true,
                      child: NavTreeTile.category(
                        title: 'הצג את כל המפרשים',
                        level: 0,
                        isSelected: allVisibleSelected,
                        trailing: _selectionCheckbox(
                          value: allVisibleSelected,
                          onChanged: _toggleAllVisible,
                        ),
                        onTap: () => _toggleAllVisible(!allVisibleSelected),
                      ),
                    );
                  }
                  final index = listIndex - leadingItemCount;
                  final item = _commentatorsList[index];

                  // כותרת דור — יושבת על רקע החלונית, מחוץ לכרטיס הקבוצה.
                  if (item.startsWith('__TITLE_')) {
                    return NavTreeHeader(title: _titleTextForToken(item));
                  }

                  final groupToken = _groupForButtonToken(item);
                  final isGroupStart =
                      index == 0 ||
                      _commentatorsList[index - 1].startsWith('__TITLE_');
                  final isGroupEnd =
                      index == _commentatorsList.length - 1 ||
                      _commentatorsList[index + 1].startsWith('__TITLE_');

                  if (groupToken != null) {
                    final selected = groupToken.commentators.every(
                      widget.selectedCommentators.contains,
                    );
                    return NavTreeGroupCard(
                      isGroupStart: isGroupStart,
                      isGroupEnd: isGroupEnd,
                      child: NavTreeTile.category(
                        title: groupToken.label,
                        level: 0,
                        isSelected: selected,
                        trailing: _selectionCheckbox(
                          value: selected,
                          onChanged: (checked) => _toggleGroup(
                            groupToken.commentators,
                            checked,
                          ),
                        ),
                        onTap: () => _toggleGroup(
                          groupToken.commentators,
                          !selected,
                        ),
                      ),
                    );
                  }

                  final selected = widget.selectedCommentators.contains(
                    item,
                  );
                  return NavTreeGroupCard(
                    isGroupStart: isGroupStart,
                    isGroupEnd: isGroupEnd,
                    child: NavTreeTile.book(
                      title: item,
                      level: 0,
                      isSelected: selected,
                      trailing: _selectionCheckbox(
                        value: selected,
                        onChanged: (checked) =>
                            _toggleSingleCommentator(item, checked),
                      ),
                      onTap: () => _toggleSingleCommentator(item, !selected),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
