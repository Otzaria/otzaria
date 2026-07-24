import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_commentary_selection.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/text_book/utils/commentator_group_builder.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';

/// סוג שמירת הגדרות מפרשים
enum CommentatorSaveScope {
  book, // לספר הנוכחי בלבד
  category, // לכל הספרים בקטגוריה
}

/// ערך פנימי שמייצג "ללא מפרש" כפריט נבחר בתפריט (מומר ל-null בשמירה).
const String _noneCommentatorValue = '__NONE__';

/// תוכן פאנל הגדרות צורת הדף - בחירת מפרשים לכל מיקום.
/// מוצג בתוך [ContextOverlayPanel] (שמספק כותרת, כפתור סגירה וגלילה),
/// כדי שכל שינוי יוחל על המסך בעדכון חי.
class PageShapeSettingsPanel extends StatefulWidget {
  final List<String> availableCommentators;
  final String bookTitle;
  final String? heCategories; // קטגוריות הספר
  final String? currentLeft;
  final String? currentRight;
  final String? currentBottom;
  final String? currentBottomRight;
  final String? currentWorkspaceId;

  /// נקרא אחרי כל שמירת שינוי, כדי שהמסך יתעדכן מיידית (עדכון חי).
  final VoidCallback? onSettingsChanged;

  /// נקרא אחרי איפוס בחירת המפרשים, כדי שהמסך יטען מחדש את ברירות המחדל.
  final VoidCallback? onReset;

  const PageShapeSettingsPanel({
    super.key,
    required this.availableCommentators,
    required this.bookTitle,
    this.heCategories,
    this.currentLeft,
    this.currentRight,
    this.currentBottom,
    this.currentBottomRight,
    this.currentWorkspaceId,
    this.onSettingsChanged,
    this.onReset,
  });

  @override
  State<PageShapeSettingsPanel> createState() => _PageShapeSettingsPanelState();
}

class _PageShapeSettingsPanelState extends State<PageShapeSettingsPanel> {
  String? _leftCommentator;
  String? _rightSingleCommentator;
  bool _rightUsesMultipleSelection = false;
  List<String> _rightCommentators = [];
  String? _bottomCommentator;
  String? _bottomRightCommentator;
  String _bottomFontFamily = AppFonts.defaultFont;
  double _commentaryFontSize =
      PageShapeSettingsManager.defaultCommentaryFontSize;
  List<CommentatorGroup> _groups = [];
  bool _isLoadingGroups = true;
  bool _highlightRelatedCommentators = false;
  Map<String, bool> _columnVisibility = {
    'left': true,
    'right': true,
    'bottom': true,
    'bottomRight': true,
  };

  PageShapeDisplaySettingsScope _displaySettingsScope =
      PageShapeDisplaySettingsScope.global;

  // הגדרה: היכן לשמור את בחירת המפרשים
  CommentatorSaveScope _commentatorSaveScope = CommentatorSaveScope.book;
  String? _selectedCategory; // הקטגוריה שנבחרה לשמירה
  List<String> _availableCategories = []; // רשימת הקטגוריות הזמינות

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
    _loadCommentatorGroups();
  }

  void _loadCurrentSettings() {
    _displaySettingsScope = PageShapeSettingsManager.getDisplaySettingsScope(
      widget.bookTitle,
      workspaceId: widget.currentWorkspaceId,
    );

    // טעינת קטגוריות זמינות
    _availableCategories = PageShapeSettingsManager.parseCategories(
      widget.heCategories,
    );

    // אם אין קטגוריות, נסה לחלץ מהכותרת
    if (_availableCategories.isEmpty && widget.bookTitle.contains(',')) {
      final firstPart = widget.bookTitle.split(',').first.trim();
      if (firstPart.isNotEmpty) {
        _availableCategories = [firstPart];
      }
    }

    // בדיקה מאיפה נטענו הגדרות המפרשים
    final activeCategory = PageShapeSettingsManager.getActiveCategory(
      widget.heCategories,
    );
    if (activeCategory != null) {
      _commentatorSaveScope = CommentatorSaveScope.category;
      _selectedCategory = activeCategory;
    } else {
      _commentatorSaveScope = CommentatorSaveScope.book;
      _selectedCategory = _availableCategories.isNotEmpty
          ? _availableCategories.first
          : null;
    }

    setState(() {
      _leftCommentator = widget.currentLeft;
      final resolvedRightSelection = resolvePageShapeCommentatorSelection(
        selection: widget.currentRight,
        availableCommentators: widget.availableCommentators,
      );
      _rightUsesMultipleSelection = isPageShapeMultipleCommentatorsMode(
        resolvedRightSelection,
      );
      _rightSingleCommentator = _rightUsesMultipleSelection
          ? null
          : resolvedRightSelection;
      _rightCommentators = resolvePageShapeSelectedCommentators(
        selection: widget.currentRight,
        availableCommentators: widget.availableCommentators,
        excludedCommentators: [
          resolvePageShapeCommentatorSelection(
            selection: widget.currentLeft,
            availableCommentators: widget.availableCommentators,
          ),
          resolvePageShapeCommentatorSelection(
            selection: widget.currentBottom,
            availableCommentators: widget.availableCommentators,
          ),
          resolvePageShapeCommentatorSelection(
            selection: widget.currentBottomRight,
            availableCommentators: widget.availableCommentators,
          ),
        ],
      );
      _bottomCommentator = widget.currentBottom;
      _bottomRightCommentator = widget.currentBottomRight;
      _bottomFontFamily =
          Settings.getValue<String>('page_shape_bottom_font') ??
          AppFonts.defaultFont;
      _commentaryFontSize = PageShapeSettingsManager.getCommentaryFontSize();
      _highlightRelatedCommentators =
          PageShapeSettingsManager.getHighlightSetting(
            widget.bookTitle,
            workspaceId: widget.currentWorkspaceId,
          );
      _columnVisibility = PageShapeSettingsManager.getColumnVisibility(
        widget.bookTitle,
        workspaceId: widget.currentWorkspaceId,
      );
    });
  }

  Future<void> _loadCommentatorGroups() async {
    final eras = await utils.splitByEra(widget.availableCommentators);
    final groups = buildCommentatorGroups(eras, widget.availableCommentators);

    if (mounted) {
      setState(() {
        _groups = groups;
        _isLoadingGroups = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    // שמירת הגדרות מפרשים - לספר או לקטגוריה לפי הבחירה
    final config = {
      'left': _leftCommentator,
      'right': _rightUsesMultipleSelection
          ? encodePageShapeCommentatorsSelection(
              _rightCommentators,
              forceMultipleMode: true,
            )
          : _rightSingleCommentator,
      'bottom': _bottomCommentator,
      'bottomRight': _bottomRightCommentator,
    };

    if (_commentatorSaveScope == CommentatorSaveScope.category &&
        _selectedCategory != null) {
      // שמירה לקטגוריה
      await PageShapeSettingsManager.saveConfiguration(
        widget.bookTitle,
        config,
        saveToCategory: _selectedCategory,
      );
      // מחיקת הגדרות מפרשים ספציפיות לספר אם יש
      await PageShapeSettingsManager.resetBookCommentatorConfig(
        widget.bookTitle,
      );
    } else {
      // שמירה לספר ספציפי
      await PageShapeSettingsManager.saveConfiguration(
        widget.bookTitle,
        config,
      );
    }

    // שמירת הגופן של המפרשים התחתונים בלבד (תמיד גלובלי)
    await Settings.setValue<String>(
      'page_shape_bottom_font',
      _bottomFontFamily,
    );

    // שמירת הגדרת הדגשה - גלובלי או פר-ספר לפי הבחירה
    await PageShapeSettingsManager.saveHighlightSetting(
      widget.bookTitle,
      _highlightRelatedCommentators,
      scope: _displaySettingsScope,
      workspaceId: widget.currentWorkspaceId,
    );

    // שמירת הגדרות visibility - גלובלי או פר-ספר לפי הבחירה
    await PageShapeSettingsManager.saveColumnVisibility(
      widget.bookTitle,
      _columnVisibility,
      scope: _displaySettingsScope,
      workspaceId: widget.currentWorkspaceId,
    );

    // עדכון חי: מודיעים למסך לטעון מחדש את ההגדרות
    widget.onSettingsChanged?.call();
  }

  void _onCommentatorChanged(
    String? value,
    void Function(String?) setter, {
    String? visibilityKey,
  }) {
    setState(() {
      setter(value);
      // אם בחרו מפרש והטור מוסתר - הצג אותו אוטומטית
      if (value != null &&
          visibilityKey != null &&
          _columnVisibility[visibilityKey] == false) {
        _columnVisibility[visibilityKey] = true;
      }
    });
    _saveSettings();
  }

  void _onFontChanged(String value) {
    setState(() {
      _bottomFontFamily = value;
    });
    // גופן מערכת (שאינו מוטמע באפליקציה) חייב להיטען לפני השמירה,
    // אחרת העדכון החי יציג fallback במקום הגופן שנבחר.
    AppFonts.ensureFontLoaded(value).then((_) => _saveSettings());
  }

  void _onRightCommentatorModeChanged(String? value) {
    final isMultipleMode = value == pageShapeMultipleCommentatorsModeValue;

    setState(() {
      _rightUsesMultipleSelection = isMultipleMode;
      _rightSingleCommentator = isMultipleMode ? null : value;
      if ((isMultipleMode || value != null) &&
          _columnVisibility['right'] == false) {
        _columnVisibility['right'] = true;
      }
    });
    _saveSettings();
  }

  void _onFontSizeChanged(double value) {
    setState(() {
      _commentaryFontSize = value;
    });
    PageShapeSettingsManager.saveCommentaryFontSize(
      value,
    ).then((_) => widget.onSettingsChanged?.call());
  }

  void _toggleColumnVisibility(String column, bool visible) {
    setState(() {
      _columnVisibility[column] = visible;
    });
    _saveSettings();
  }

  Future<void> _onDisplayScopeChanged(
    PageShapeDisplaySettingsScope scope,
  ) async {
    if (scope == _displaySettingsScope) return;

    if (scope == PageShapeDisplaySettingsScope.global) {
      final confirm = await showWarningDialog(
        context: context,
        title: 'חזרה להגדרות גלובליות',
        content: 'האם לאפס את הגדרות התצוגה המקומיות ולחזור להגדרות הגלובליות?',
        confirmText: 'אפס',
      );
      if (confirm == true) {
        await _resetDisplaySettingsToGlobal();
      }
      return;
    }

    if (scope == PageShapeDisplaySettingsScope.workspace) {
      await PageShapeSettingsManager.resetBookDisplaySettings(
        widget.bookTitle,
      );
    }

    setState(() {
      _displaySettingsScope = scope;
    });
    await _saveSettings();
  }

  /// איפוס הגדרות תצוגה מקומיות וחזרה לגלובלי (לא משפיע על בחירת מפרשים)
  Future<void> _resetDisplaySettingsToGlobal() async {
    await PageShapeSettingsManager.resetBookDisplaySettings(widget.bookTitle);
    await PageShapeSettingsManager.resetWorkspaceDisplaySettings(
      widget.currentWorkspaceId,
    );
    // טעינה מחדש של הגדרות התצוגה הגלובליות (לא מפרשים!)
    final highlight = PageShapeSettingsManager.getHighlightSetting(
      widget.bookTitle,
    );
    final visibility = PageShapeSettingsManager.getColumnVisibility(
      widget.bookTitle,
    );
    if (!mounted) return;
    setState(() {
      _displaySettingsScope = PageShapeDisplaySettingsScope.global;
      _highlightRelatedCommentators = highlight;
      _columnVisibility = visibility;
    });
    widget.onSettingsChanged?.call();
  }

  String get _displaySettingsTitle {
    switch (_displaySettingsScope) {
      case PageShapeDisplaySettingsScope.book:
        return 'הגדרות תצוגה לספר זה';
      case PageShapeDisplaySettingsScope.workspace:
        return 'הגדרות תצוגה לשולחן עבודה זה';
      case PageShapeDisplaySettingsScope.global:
        return 'הגדרות תצוגה גלובליות';
    }
  }

  String get _displaySettingsSubtitle {
    switch (_displaySettingsScope) {
      case PageShapeDisplaySettingsScope.book:
        return 'הדגשה והצגת טורים יחולו רק על "${widget.bookTitle}"';
      case PageShapeDisplaySettingsScope.workspace:
        return 'הדגשה והצגת טורים יחולו רק בשולחן העבודה הנוכחי';
      case PageShapeDisplaySettingsScope.global:
        return 'הדגשה והצגת טורים יחולו על כל הספרים';
    }
  }

  IconData get _displaySettingsIcon {
    switch (_displaySettingsScope) {
      case PageShapeDisplaySettingsScope.book:
        return FluentIcons.book_24_regular;
      case PageShapeDisplaySettingsScope.workspace:
        return FluentIcons.window_24_regular;
      case PageShapeDisplaySettingsScope.global:
        return FluentIcons.globe_24_regular;
    }
  }

  Widget _buildDisplaySettingsIcon(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    if (_displaySettingsScope == PageShapeDisplaySettingsScope.book) {
      return RtlIcon(
        FluentIcons.book_24_regular,
        size: 20,
        color: color,
      );
    }
    return Icon(
      _displaySettingsIcon,
      size: 20,
      color: color,
    );
  }

  String get _commentatorSaveScopeSubtitle {
    if (_commentatorSaveScope == CommentatorSaveScope.category &&
        _selectedCategory != null) {
      return 'המפרשים יחולו על כל ספרי "$_selectedCategory"';
    }
    return 'המפרשים יחולו רק על "${widget.bookTitle}"';
  }

  Future<void> _resetCommentators() async {
    final confirm = await showWarningDialog(
      context: context,
      title: 'איפוס הגדרות מפרשים',
      content: 'האם לאפס את הגדרות המפרשים לברירות המחדל?',
      subtitle:
          'פעולה זו תמחק את ההגדרות השמורות ותטען את המפרשים '
          'המתאימים לפי סוג הספר.',
      confirmText: 'אפס',
    );

    if (confirm != true) return;

    await PageShapeSettingsManager.resetBookCommentatorConfig(widget.bookTitle);
    widget.onReset?.call();
  }

  @override
  Widget build(BuildContext context) {
    // הגלילה, הכותרת והריפוד מסופקים ע"י ContextOverlayPanel העוטף.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // בחירת תחום השמירה של הגדרות התצוגה בלבד.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppSurfaces.panelSection(context),
            borderRadius: AppTokens.borderRadiusAll,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildDisplaySettingsIcon(context),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _displaySettingsTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppSegmentedControl<PageShapeDisplaySettingsScope>(
                options: const [
                  SegmentOption(
                    value: PageShapeDisplaySettingsScope.book,
                    label: 'ספר זה',
                  ),
                  SegmentOption(
                    value: PageShapeDisplaySettingsScope.workspace,
                    label: 'שולחן עבודה זה',
                  ),
                  SegmentOption(
                    value: PageShapeDisplaySettingsScope.global,
                    label: 'גלובלי',
                  ),
                ],
                currentValue: _displaySettingsScope,
                onChanged: _onDisplayScopeChanged,
                expandToFillWidth: true,
                showSelectedIcon: false,
                height: 40,
              ),
              const SizedBox(height: 8),
              Text(
                _displaySettingsSubtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),

        // בחירת היכן לשמור את הגדרות המפרשים
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppSurfaces.panelSectionAccent(context),
            borderRadius: AppTokens.borderRadiusAll,
            border: Border.all(
              color: AppSurfaces.panelSectionAccentBorder(context),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    FluentIcons.save_24_regular,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'שמירת בחירת מפרשים',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_availableCategories.isNotEmpty) ...[
                AppSegmentedControl<CommentatorSaveScope>(
                  options: const [
                    SegmentOption(
                      value: CommentatorSaveScope.book,
                      label: 'ספר זה',
                    ),
                    SegmentOption(
                      value: CommentatorSaveScope.category,
                      label: 'קטגוריה',
                    ),
                  ],
                  currentValue: _commentatorSaveScope,
                  onChanged: (value) {
                    setState(() {
                      _commentatorSaveScope = value;
                    });
                    _saveSettings();
                  },
                  expandToFillWidth: true,
                  showSelectedIcon: false,
                  height: 40,
                ),
                const SizedBox(height: 8),
              ],
              Text(
                _commentatorSaveScopeSubtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              // בחירת קטגוריה
              if (_commentatorSaveScope == CommentatorSaveScope.category &&
                  _availableCategories.isNotEmpty) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedCategory,
                  decoration: InputDecoration(
                    labelText: 'בחר קטגוריה',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                  ),
                  items: _availableCategories.map((category) {
                    return DropdownMenuItem<String>(
                      value: category,
                      child: Text(
                        category,
                        style: const TextStyle(fontSize: 13),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedCategory = value;
                    });
                    _saveSettings();
                  },
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),
        const Text(
          'בחר מפרשים להצגה:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('הדגש פרשנים קשורים'),
          subtitle: const Text('הדגשת קטעים בפרשנים הקשורים לשורה שנבחרה'),
          value: _highlightRelatedCommentators,
          onChanged: (value) {
            setState(() {
              _highlightRelatedCommentators = value;
            });
            _saveSettings();
          },
        ),
        const Divider(),
        const SizedBox(height: 8),
        // הסבר על כפתורי העין
        Row(
          children: [
            Icon(
              FluentIcons.eye_24_regular,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'לחץ על סמל העין כדי להציג או להסתיר טור',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildCommentatorDropdown(
          label: 'מפרש ימני',
          value: _leftCommentator,
          onChanged: (value) => _onCommentatorChanged(
            value,
            (v) => _leftCommentator = v,
            visibilityKey: 'left',
          ),
          visibilityKey: 'left',
        ),
        const SizedBox(height: 12),
        _buildCommentatorDropdown(
          label: 'מפרש שמאלי',
          value: _rightUsesMultipleSelection
              ? pageShapeMultipleCommentatorsModeValue
              : _rightSingleCommentator,
          onChanged: _onRightCommentatorModeChanged,
          visibilityKey: 'right',
          allowMultipleCommentatorsSelection: true,
        ),
        if (_rightUsesMultipleSelection) ...[
          const SizedBox(height: 8),
          _buildRightPaneInfo(),
        ],
        const SizedBox(height: 12),
        _buildCommentatorDropdown(
          label: 'מפרש תחתון',
          value: _bottomCommentator,
          onChanged: (value) => _onCommentatorChanged(
            value,
            (v) => _bottomCommentator = v,
            visibilityKey: 'bottom',
          ),
          visibilityKey: 'bottom',
        ),
        const SizedBox(height: 12),
        _buildCommentatorDropdown(
          label: 'מפרש תחתון נוסף',
          value: _bottomRightCommentator,
          onChanged: (value) => _onCommentatorChanged(
            value,
            (v) => _bottomRightCommentator = v,
            visibilityKey: 'bottomRight',
          ),
          visibilityKey: 'bottomRight',
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 12),
        // גודל גופן המפרשים
        const Text(
          'גודל גופן מפרשים:',
          style: TextStyle(fontSize: 15),
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(FluentIcons.subtract_24_regular),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: _commentaryFontSize > 10
                  ? () => _onFontSizeChanged(_commentaryFontSize - 1)
                  : null,
            ),
            SizedBox(
              width: 36,
              child: Text(
                '${_commentaryFontSize.round()}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            IconButton(
              icon: const Icon(FluentIcons.add_24_regular),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: _commentaryFontSize < 30
                  ? () => _onFontSizeChanged(_commentaryFontSize + 1)
                  : null,
            ),
            Expanded(
              child: Slider(
                value: _commentaryFontSize,
                min: 10,
                max: 30,
                divisions: 20,
                // בזמן גרירה מעדכנים רק את התצוגה; שמירה ועדכון
                // חי - רק בשחרור הסליידר, כדי לא להציף בטעינות.
                onChanged: (value) => setState(() {
                  _commentaryFontSize = value;
                }),
                onChangeEnd: _onFontSizeChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'גופן מפרשים תחתונים:',
          style: TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _bottomFontFamily,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          items: AppFonts.buildDropdownItems(
            selectedValue: _bottomFontFamily,
            itemTextStyle: const TextStyle(fontSize: 13),
          ),
          onChanged: (value) {
            if (value != null) {
              _onFontChanged(value);
            }
          },
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ActionButton.warning(
            onPressed: _resetCommentators,
            icon: FluentIcons.arrow_reset_24_regular,
            text: 'איפוס מפרשים',
          ),
        ),
      ],
    );
  }

  Widget _buildCommentatorDropdown({
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
    String? visibilityKey,
    bool allowRemainingCommentatorsSelection = false,
    bool allowMultipleCommentatorsSelection = false,
  }) {
    final isVisible = visibilityKey != null
        ? (_columnVisibility[visibilityKey] ?? true)
        : true;

    final menuData = _buildCommentatorMenuData(
      allowRemaining: allowRemainingCommentatorsSelection,
      allowMultiple: allowMultipleCommentatorsSelection,
    );

    return Row(
      children: [
        // כפתור הצגה/הסתרה
        if (visibilityKey != null)
          IconButton(
            icon: Icon(
              isVisible
                  ? FluentIcons.eye_24_regular
                  : FluentIcons.eye_off_24_regular,
              size: 20,
              color: isVisible
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            tooltip: isVisible ? 'הסתר טור' : 'הצג טור',
            onPressed: () => _toggleColumnVisibility(visibilityKey, !isVisible),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        SizedBox(
          width: visibilityKey != null ? 108 : 140,
          child: Text(
            label,
            style: const TextStyle(fontSize: 15),
          ),
        ),
        Expanded(
          child: AppDropdownField<String>(
            value: value ?? _noneCommentatorValue,
            entries: menuData.entries,
            enableSearch: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'חיפוש מפרש...',
            ),
            filterLabels: menuData.filterLabels,
            filterPredicates: menuData.filterPredicates,
            labelBuilder: (v) => v == _noneCommentatorValue
                ? 'ללא מפרש'
                : formatPageShapeCommentatorSelection(v),
            onSelected: (selected) => onChanged(
              selected == _noneCommentatorValue ? null : selected,
            ),
          ),
        ),
      ],
    );
  }

  /// בונה את פריטי התפריט וצ'יפי הסינון לפי הדורות.
  /// עד שהדורות נטענים מוחזרת רשימה ריקה כדי שהשדה יישאר מנוטרל.
  ({
    List<AppMenuEntry<String>> entries,
    List<String> filterLabels,
    List<bool Function(AppMenuEntry<String>)?> filterPredicates,
  })
  _buildCommentatorMenuData({
    required bool allowRemaining,
    required bool allowMultiple,
  }) {
    if (_isLoadingGroups) {
      return (
        entries: const [],
        filterLabels: const [],
        filterPredicates: const [],
      );
    }

    final entries = <AppMenuEntry<String>>[];
    if (allowMultiple) {
      entries.add(
        const AppMenuEntry(
          value: pageShapeMultipleCommentatorsModeValue,
          label: pageShapeMultipleCommentatorsModeLabel,
        ),
      );
    }
    if (allowRemaining) {
      entries.add(
        const AppMenuEntry(
          value: pageShapeRemainingCommentatorsValue,
          label: pageShapeRemainingCommentatorsLabel,
        ),
      );
    }
    entries.add(
      const AppMenuEntry(
        value: _noneCommentatorValue,
        label: 'ללא מפרש',
      ),
    );

    final eraOf = <String, String>{};
    final nonEmptyGroups = _groups
        .where((group) => group.commentators.isNotEmpty)
        .toList();
    for (final group in nonEmptyGroups) {
      for (final commentator in group.commentators) {
        eraOf[commentator] = group.title;
        entries.add(AppMenuEntry(value: commentator, label: commentator));
      }
    }

    // הפריטים המיוחדים (ללא/שאר/מרובים) אינם משויכים לדור — יופיעו רק תחת "הכל".
    final filterLabels = <String>['הכל', ...nonEmptyGroups.map((g) => g.title)];
    final filterPredicates = <bool Function(AppMenuEntry<String>)?>[
      null,
      for (final group in nonEmptyGroups)
        (entry) => eraOf[entry.value] == group.title,
    ];

    return (
      entries: entries,
      filterLabels: filterLabels,
      filterPredicates: filterPredicates,
    );
  }

  Widget _buildRightPaneInfo() {
    final selectionLabel = _rightCommentators.isEmpty
        ? 'לא נבחרו מפרשים'
        : formatPageShapeCommentatorSelection(
            encodePageShapeCommentatorsSelection(
              _rightCommentators,
              forceMultipleMode: true,
            ),
          );

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            selectionLabel,
            style: TextStyle(
              fontSize: 13,
              color: _rightCommentators.isEmpty
                  ? Theme.of(context).hintColor
                  : Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'הבחירה המפורטת נעשית מתוך החלונית עצמה.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
