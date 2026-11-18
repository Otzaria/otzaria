import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_commentary_selection.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_commentary_font_slider.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/book_common/utils/commentator_group_builder.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/controls/app_icon_button.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';

/// סוג שמירת הגדרות מפרשים
enum CommentatorSaveScope {
  book, // לספר הנוכחי בלבד
  workspace, // לספר הנוכחי בשולחן העבודה הנוכחי בלבד
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

  /// המקור של הספר — מפרשי מסד מצורף מסווגים לפי הדורות של המסד שלו.
  final BookSource bookSource;
  final String? currentLeft;
  final String? currentRight;
  final String? currentBottom;
  final String? currentBottomRight;
  final String? currentWorkspaceId;
  final int configurationGeneration;
  final bool? applyTextMaxWidth;

  /// מפרשי-על שאפשר להציג בטור יחיד: מפרש-על ← המפרש שעליו הוא מפרש.
  final Map<String, String> superCommentatorParents;

  /// נקרא אחרי כל שמירת שינוי, כדי שהמסך יתעדכן מיידית (עדכון חי).
  final VoidCallback? onSettingsChanged;

  /// נקרא אחרי איפוס בחירת המפרשים, כדי שהמסך יטען מחדש את ברירות המחדל.
  final VoidCallback? onReset;

  const PageShapeSettingsPanel({
    super.key,
    required this.availableCommentators,
    required this.bookTitle,
    this.heCategories,
    this.bookSource = BookSource.official,
    this.currentLeft,
    this.currentRight,
    this.currentBottom,
    this.currentBottomRight,
    this.currentWorkspaceId,
    this.configurationGeneration = 0,
    this.applyTextMaxWidth,
    this.superCommentatorParents = const {},
    this.onSettingsChanged,
    this.onReset,
  });

  @override
  State<PageShapeSettingsPanel> createState() => _PageShapeSettingsPanelState();
}

class _PageShapeSettingsPanelState extends State<PageShapeSettingsPanel> {
  String? _leftCommentator;
  String? _rightCommentatorSelection;
  String? _rightSingleCommentator;
  String? _bottomCommentator;
  String? _bottomRightCommentator;
  String _bottomFontFamily = AppFonts.defaultFont;
  bool _applyTextMaxWidth = PageShapeSettingsManager.getApplyTextMaxWidth();
  List<CommentatorGroup> _groups = [];
  bool _isLoadingGroups = true;
  int _groupsLoadGeneration = 0;
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

  @override
  void didUpdateWidget(covariant PageShapeSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.configurationGeneration != widget.configurationGeneration) {
      _loadCurrentSettings();
    }
    if (oldWidget.applyTextMaxWidth != widget.applyTextMaxWidth) {
      _applyTextMaxWidth =
          widget.applyTextMaxWidth ??
          PageShapeSettingsManager.getApplyTextMaxWidth();
    }
    if (oldWidget.currentLeft != widget.currentLeft) {
      _leftCommentator = widget.currentLeft;
    }
    if (oldWidget.currentRight != widget.currentRight) {
      _rightCommentatorSelection = widget.currentRight;
    }
    if (oldWidget.currentBottom != widget.currentBottom) {
      _bottomCommentator = widget.currentBottom;
    }
    if (oldWidget.currentBottomRight != widget.currentBottomRight) {
      _bottomRightCommentator = widget.currentBottomRight;
    }

    final availableChanged =
        !listEquals(
          oldWidget.availableCommentators,
          widget.availableCommentators,
        ) ||
        oldWidget.bookSource != widget.bookSource;
    if (oldWidget.currentRight != widget.currentRight || availableChanged) {
      _rightSingleCommentator = resolvePageShapeSingleCommentatorSelection(
        selection: _rightCommentatorSelection,
        availableCommentators: widget.availableCommentators,
        commentedBookTitle: widget.bookTitle,
      );
    }
    if (availableChanged) {
      _isLoadingGroups = true;
      _groups = [];
      _loadCommentatorGroups();
    }
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
    _selectedCategory =
        activeCategory ??
        (_availableCategories.isNotEmpty ? _availableCategories.first : null);
    if (PageShapeSettingsManager.hasWorkspaceCommentatorConfig(
      widget.currentWorkspaceId,
      widget.bookTitle,
    )) {
      _commentatorSaveScope = CommentatorSaveScope.workspace;
    } else if (activeCategory != null) {
      _commentatorSaveScope = CommentatorSaveScope.category;
    } else {
      _commentatorSaveScope = CommentatorSaveScope.book;
    }

    setState(() {
      _leftCommentator = widget.currentLeft;
      _rightCommentatorSelection = widget.currentRight;
      _rightSingleCommentator = resolvePageShapeSingleCommentatorSelection(
        selection: widget.currentRight,
        availableCommentators: widget.availableCommentators,
        commentedBookTitle: widget.bookTitle,
      );
      _bottomCommentator = widget.currentBottom;
      _bottomRightCommentator = widget.currentBottomRight;
      _bottomFontFamily =
          Settings.getValue<String>(
            SettingsRepository.keyPageShapeBottomFont,
          ) ??
          AppFonts.defaultFont;
      _applyTextMaxWidth =
          widget.applyTextMaxWidth ??
          PageShapeSettingsManager.getApplyTextMaxWidth();
      _highlightRelatedCommentators =
          PageShapeSettingsManager.getHighlightSetting(
            widget.bookTitle,
            workspaceId: widget.currentWorkspaceId,
          );
      _columnVisibility = PageShapeSettingsManager.getColumnVisibility(
        widget.bookTitle,
        heCategories: widget.heCategories,
        workspaceId: widget.currentWorkspaceId,
      );
    });
  }

  Future<void> _loadCommentatorGroups() async {
    final generation = ++_groupsLoadGeneration;
    final available = widget.availableCommentators;
    final groups = await groupCommentatorsByEra(
      available,
      source: widget.bookSource,
    );

    if (mounted && generation == _groupsLoadGeneration) {
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
      'right': _rightCommentatorSelection,
      'bottom': _bottomCommentator,
      'bottomRight': _bottomRightCommentator,
    };

    if (_commentatorSaveScope == CommentatorSaveScope.workspace &&
        _hasWorkspace) {
      // שמירה לספר בשולחן העבודה הנוכחי - בלי לגעת בהגדרת הספר, כדי
      // ששולחנות עבודה אחרים ימשיכו לראות את הבחירה שלהם.
      await PageShapeSettingsManager.saveConfiguration(
        widget.bookTitle,
        config,
        saveToWorkspaceId: widget.currentWorkspaceId,
        columnVisibility: _columnVisibility,
      );
    } else if (_commentatorSaveScope == CommentatorSaveScope.category &&
        _selectedCategory != null) {
      // שמירה לקטגוריה
      await PageShapeSettingsManager.saveConfiguration(
        widget.bookTitle,
        config,
        saveToCategory: _selectedCategory,
        columnVisibility: _columnVisibility,
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
        columnVisibility: _columnVisibility,
      );
    }

    // שמירת הגופן של המפרשים התחתונים בלבד (תמיד גלובלי)
    await Settings.setValue<String>(
      SettingsRepository.keyPageShapeBottomFont,
      _bottomFontFamily,
    );

    // שמירת הגדרת הדגשה - גלובלי או פר-ספר לפי הבחירה
    await PageShapeSettingsManager.saveHighlightSetting(
      widget.bookTitle,
      _highlightRelatedCommentators,
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
    if (value != null &&
        !widget.availableCommentators.contains(value) &&
        !widget.superCommentatorParents.containsKey(value)) {
      return;
    }
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

  void _onApplyTextMaxWidthChanged(bool value) {
    setState(() {
      _applyTextMaxWidth = value;
    });
    PageShapeSettingsManager.saveApplyTextMaxWidth(
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
    final highlight = PageShapeSettingsManager.getHighlightSetting(
      widget.bookTitle,
    );
    if (!mounted) return;
    setState(() {
      _displaySettingsScope = PageShapeDisplaySettingsScope.global;
      _highlightRelatedCommentators = highlight;
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
        return 'הדגשת פרשנים קשורים תחול רק על "${widget.bookTitle}"';
      case PageShapeDisplaySettingsScope.workspace:
        return 'הדגשת פרשנים קשורים תחול רק בשולחן העבודה הנוכחי';
      case PageShapeDisplaySettingsScope.global:
        return 'הדגשת פרשנים קשורים תחול על כל הספרים';
    }
  }

  IconData get _displaySettingsIcon {
    switch (_displaySettingsScope) {
      case PageShapeDisplaySettingsScope.book:
        return OtzariaIcons.book_24_regular;
      case PageShapeDisplaySettingsScope.workspace:
        return FluentIcons.window_24_regular;
      case PageShapeDisplaySettingsScope.global:
        return FluentIcons.globe_24_regular;
    }
  }

  List<SegmentOption<CommentatorSaveScope>> get _commentatorSaveScopeOptions {
    return [
      // תמיד לספר הנוכחי — בבורר התצוגה "שולחן עבודה" חל על כל ספרי השולחן.
      SegmentOption(
        value: CommentatorSaveScope.book,
        label: context.settingsText('ספר זה'),
      ),
      if (_hasWorkspace)
        SegmentOption(
          value: CommentatorSaveScope.workspace,
          label: context.settingsText('ספר זה בשולחן'),
        ),
      if (_availableCategories.isNotEmpty)
        const SegmentOption(
          value: CommentatorSaveScope.category,
          label: 'קטגוריה',
        ),
    ];
  }

  bool get _hasWorkspace =>
      widget.currentWorkspaceId != null &&
      widget.currentWorkspaceId!.isNotEmpty;

  String get _commentatorSaveScopeSubtitle {
    if (_commentatorSaveScope == CommentatorSaveScope.workspace) {
      return 'המפרשים והטורים המוסתרים יחולו על "${widget.bookTitle}" בשולחן העבודה הנוכחי בלבד';
    }
    if (_commentatorSaveScope == CommentatorSaveScope.category &&
        _selectedCategory != null) {
      return 'המפרשים והטורים המוסתרים יחולו על כל ספרי "$_selectedCategory"';
    }
    return 'המפרשים והטורים המוסתרים יחולו על "${widget.bookTitle}" בכל שולחנות העבודה';
  }

  Future<void> _onCommentatorScopeChanged(CommentatorSaveScope scope) async {
    if (scope == _commentatorSaveScope) return;

    // יציאה מתחום שולחן העבודה מחייבת מחיקת ההגדרה שלו, אחרת היא ממשיכה
    // לגבור על מה שנשמר עכשיו לספר או לקטגוריה.
    if (_commentatorSaveScope == CommentatorSaveScope.workspace) {
      await PageShapeSettingsManager.resetWorkspaceCommentatorConfig(
        widget.currentWorkspaceId,
        widget.bookTitle,
      );
    }

    if (!mounted) return;
    setState(() {
      _commentatorSaveScope = scope;
    });
    await _saveSettings();
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
    await PageShapeSettingsManager.resetWorkspaceCommentatorConfig(
      widget.currentWorkspaceId,
      widget.bookTitle,
    );
    if (mounted) {
      setState(() {
        _commentatorSaveScope = CommentatorSaveScope.book;
      });
    }
    widget.onReset?.call();
  }

  @override
  Widget build(BuildContext context) {
    // הגלילה, הכותרת והריפוד מסופקים ע"י ContextOverlayPanel העוטף. המבנה זהה
    // ל"הגדרות תצוגת הספרים": כרטיסי SettingsCard עם שורות הגדרה.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDisplayCard(context),
        _buildCommentatorsCard(context),
        _buildFontCard(context),
        const SizedBox(height: AppTokens.spaceLG),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ActionButton.warningSoft(
            onPressed: _resetCommentators,
            icon: FluentIcons.arrow_reset_24_regular,
            text: 'איפוס מפרשים',
          ),
        ),
      ],
    );
  }

  /// תחום ההגדרות של התצוגה, והדגשת פרשנים ורוחב הטקסט.
  Widget _buildDisplayCard(BuildContext context) {
    return SettingsCard(
      children: [
        SettingsSegmentedTile<PageShapeDisplaySettingsScope>(
          icon: _displaySettingsIcon,
          title: _displaySettingsTitle,
          subtitle: _displaySettingsSubtitle,
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
        ),
        SettingsSwitchTile(
          icon: OtzariaIcons.book_alef_rashi_24_regular,
          title: 'הדגש פרשנים קשורים',
          subtitle: 'הדגשת קטעים בפרשנים הקשורים לשורה שנבחרה',
          value: _highlightRelatedCommentators,
          onChanged: (value) {
            setState(() {
              _highlightRelatedCommentators = value;
            });
            _saveSettings();
          },
        ),
        SettingsSwitchTile(
          icon: FluentIcons.text_align_distributed_24_regular,
          title: 'החל את רוחב הטקסט',
          subtitle: 'הגבלת רוחב הטקסט שבהגדרות תחול גם על הדף כולו',
          value: _applyTextMaxWidth,
          onChanged: _onApplyTextMaxWidthChanged,
        ),
      ],
    );
  }

  /// היכן נשמרת בחירת המפרשים, ובחירת המפרש לכל טור.
  Widget _buildCommentatorsCard(BuildContext context) {
    final showScopeChoice = _commentatorSaveScopeOptions.length > 1;
    return SettingsCard(
      title: 'בחר מפרשים להצגה',
      subtitle: 'לחץ על סמל העין כדי להציג או להסתיר טור',
      children: [
        if (showScopeChoice)
          SettingsSegmentedTile<CommentatorSaveScope>(
            icon: FluentIcons.save_24_regular,
            title: 'שמירת בחירת מפרשים',
            subtitle: _commentatorSaveScopeSubtitle,
            options: _commentatorSaveScopeOptions,
            currentValue: _commentatorSaveScope,
            onChanged: _onCommentatorScopeChanged,
          )
        else
          SettingsActionTile.text(
            icon: FluentIcons.save_24_regular,
            title: 'שמירת בחירת מפרשים',
            subtitle: _commentatorSaveScopeSubtitle,
          ),
        if (_commentatorSaveScope == CommentatorSaveScope.category &&
            _availableCategories.isNotEmpty)
          SettingsDropdownTile<String>(
            icon: FluentIcons.folder_24_regular,
            title: 'בחר קטגוריה',
            value: _selectedCategory,
            entries: _availableCategories
                .map(
                  (category) =>
                      AppMenuEntry<String>(value: category, label: category),
                )
                .toList(),
            onSelected: (value) {
              if (value != null) {
                setState(() {
                  _selectedCategory = value;
                });
                _saveSettings();
              }
            },
          ),
        _buildCommentatorDropdown(
          label: 'מפרש ימני',
          includeSuperCommentators: true,
          value: _leftCommentator,
          onChanged: (value) => _onCommentatorChanged(
            value,
            (v) => _leftCommentator = v,
            visibilityKey: 'left',
          ),
          visibilityKey: 'left',
        ),
        _buildCommentatorDropdown(
          label: 'מפרש שמאלי',
          value: _rightSingleCommentator,
          onChanged: (value) {
            _onCommentatorChanged(
              value,
              (v) {
                _rightSingleCommentator = v;
                _rightCommentatorSelection = v;
              },
              visibilityKey: 'right',
            );
          },
          visibilityKey: 'right',
        ),
        _buildCommentatorDropdown(
          label: 'מפרש תחתון',
          includeSuperCommentators: true,
          value: _bottomCommentator,
          onChanged: (value) => _onCommentatorChanged(
            value,
            (v) => _bottomCommentator = v,
            visibilityKey: 'bottom',
          ),
          visibilityKey: 'bottom',
        ),
        _buildCommentatorDropdown(
          label: 'מפרש תחתון נוסף',
          includeSuperCommentators: true,
          value: _bottomRightCommentator,
          onChanged: (value) => _onCommentatorChanged(
            value,
            (v) => _bottomRightCommentator = v,
            visibilityKey: 'bottomRight',
          ),
          visibilityKey: 'bottomRight',
        ),
      ],
    );
  }

  /// גודל וגופן המפרשים, באותן שורות כמו "הגדרות גופן ועיצוב" בהגדרות התצוגה.
  Widget _buildFontCard(BuildContext context) {
    return SettingsCard(
      title: 'גופן ועיצוב מפרשים',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceMD,
            vertical: AppTokens.spaceSMD,
          ),
          child: PageShapeCommentaryFontSizeSlider(
            title: 'גודל גופן מפרשים',
            onSaved: widget.onSettingsChanged,
          ),
        ),
        SettingsActionTile.text(
          icon: OtzariaIcons.beit_behind_alef_24_filled,
          title: 'גופן מפרשים תחתונים',
          stacked: true,
          actions: [
            SizedBox(
              width: double.infinity,
              child: FontDropdownField(
                value: _bottomFontFamily,
                onChanged: _onFontChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCommentatorDropdown({
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
    required String visibilityKey,
    bool includeSuperCommentators = false,
  }) {
    final isVisible = _columnVisibility[visibilityKey] ?? true;
    final menuData = _buildCommentatorMenuData(
      includeSuperCommentators: includeSuperCommentators,
    );

    // שורה אחת קומפקטית: עין, תווית ושדה. כך ארבעת הטורים תופסים מעט מקום.
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceSM,
        vertical: AppTokens.spaceXS,
      ),
      child: Row(
        children: [
          // כפתור הצגה/הסתרה של הטור, בצד התווית.
          AppIconButton(
            size: AppIconButtonSize.medium,
            icon: Icon(
              isVisible
                  ? FluentIcons.eye_24_regular
                  : FluentIcons.eye_off_24_regular,
            ),
            isSelected: isVisible,
            tooltip: isVisible ? 'הסתר טור' : 'הצג טור',
            onPressed: () => _toggleColumnVisibility(visibilityKey, !isVisible),
          ),
          const SizedBox(width: AppTokens.spaceXS),
          Expanded(
            flex: 2,
            child: Text(
              context.settingsText(label),
              style: AppTextStyles.settingTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppTokens.spaceSM),
          Expanded(
            flex: 3,
            child: AppDropdownField<String>(
              value: value ?? _noneCommentatorValue,
              entries: menuData.entries,
              enableSearch: true,
              decoration: const InputDecoration(
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
      ),
    );
  }

  /// בונה את פריטי התפריט וצ'יפי הסינון לפי הדורות.
  /// עד שהדורות נטענים מוחזרת רשימה ריקה כדי שהשדה יישאר מנוטרל.
  ({
    List<AppMenuEntry<String>> entries,
    List<String> filterLabels,
    List<bool Function(AppMenuEntry<String>)?> filterPredicates,
  })
  _buildCommentatorMenuData({bool includeSuperCommentators = false}) {
    if (_isLoadingGroups) {
      return (
        entries: const [],
        filterLabels: const [],
        filterPredicates: const [],
      );
    }

    final entries = <AppMenuEntry<String>>[
      const AppMenuEntry(
        value: _noneCommentatorValue,
        label: 'ללא מפרש',
      ),
    ];

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

    // מפרשי-על אינם מפרשי הספר: קבוצה לכל מפרש שעליו הם מפרשים, אחרי הדורות.
    final superGroups = <String>[];
    if (includeSuperCommentators) {
      for (final MapEntry(key: title, value: parent)
          in widget.superCommentatorParents.entries) {
        if (eraOf.containsKey(title)) continue;
        final group = context.settingsText(
          'על {parent}',
          args: {'parent': parent},
        );
        if (!superGroups.contains(group)) superGroups.add(group);
        eraOf[title] = group;
        entries.add(
          AppMenuEntry(
            value: title,
            label: context.settingsText(
              '{title} ({group})',
              args: {'title': title, 'group': group},
            ),
          ),
        );
      }
    }

    // "ללא מפרש" אינו משויך לדור — יופיע רק תחת "הכל".
    final groupTitles = [...nonEmptyGroups.map((g) => g.title), ...superGroups];
    final filterLabels = <String>['הכל', ...groupTitles];
    final filterPredicates = <bool Function(AppMenuEntry<String>)?>[
      null,
      for (final group in groupTitles) (entry) => eraOf[entry.value] == group,
    ];

    return (
      entries: entries,
      filterLabels: filterLabels,
      filterPredicates: filterPredicates,
    );
  }
}
