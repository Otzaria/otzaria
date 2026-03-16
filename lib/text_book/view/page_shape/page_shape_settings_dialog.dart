import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_commentary_selection.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/rtl_text_field.dart';

/// סוג שמירת הגדרות מפרשים
enum CommentatorSaveScope {
  book, // לספר הנוכחי בלבד
  category, // לכל הספרים בקטגוריה
}

/// דיאלוג הגדרות צורת הדף - בחירת מפרשים לכל מיקום
class PageShapeSettingsDialog extends StatefulWidget {
  final List<String> availableCommentators;
  final String bookTitle;
  final String? heCategories; // קטגוריות הספר
  final String? currentLeft;
  final String? currentRight;
  final String? currentBottom;
  final String? currentBottomRight;

  const PageShapeSettingsDialog({
    super.key,
    required this.availableCommentators,
    required this.bookTitle,
    this.heCategories,
    this.currentLeft,
    this.currentRight,
    this.currentBottom,
    this.currentBottomRight,
  });

  @override
  State<PageShapeSettingsDialog> createState() =>
      _PageShapeSettingsDialogState();
}

class _PageShapeSettingsDialogState extends State<PageShapeSettingsDialog> {
  String? _leftCommentator;
  String? _rightCommentator;
  String? _bottomCommentator;
  String? _bottomRightCommentator;
  String _bottomFontFamily = AppFonts.defaultFont;
  double _commentaryFontSize =
      PageShapeSettingsManager.defaultCommentaryFontSize;
  List<CommentatorGroup> _groups = [];
  bool _isLoadingGroups = true;
  bool _hasChanges = false;
  bool _highlightRelatedCommentators = false;
  Map<String, bool> _columnVisibility = {
    'left': true,
    'right': true,
    'bottom': true,
  };

  // הגדרה חדשה: האם לשמור לספר הנוכחי בלבד (להגדרות תצוגה)
  bool _saveForCurrentBookOnly = false;

  // הגדרה חדשה: היכן לשמור את בחירת המפרשים
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
    // בדיקה אם יש הגדרות פר-ספר
    _saveForCurrentBookOnly =
        PageShapeSettingsManager.hasBookSpecificSettings(widget.bookTitle);

    // טעינת קטגוריות זמינות
    _availableCategories =
        PageShapeSettingsManager.parseCategories(widget.heCategories);

    // אם אין קטגוריות, נסה לחלץ מהכותרת
    if (_availableCategories.isEmpty && widget.bookTitle.contains(',')) {
      // למשל: "משנה תורה, הלכות שבת" → ["משנה תורה"]
      final firstPart = widget.bookTitle.split(',').first.trim();
      if (firstPart.isNotEmpty) {
        _availableCategories = [firstPart];
      }
    }

    // בדיקה מאיפה נטענו הגדרות המפרשים
    final activeCategory =
        PageShapeSettingsManager.getActiveCategory(widget.heCategories);
    if (activeCategory != null) {
      _commentatorSaveScope = CommentatorSaveScope.category;
      _selectedCategory = activeCategory;
    } else {
      _commentatorSaveScope = CommentatorSaveScope.book;
      // בחירת קטגוריית ברירת מחדל
      _selectedCategory =
          _availableCategories.isNotEmpty ? _availableCategories.first : null;
    }

    setState(() {
      _leftCommentator = widget.currentLeft;
      _rightCommentator = widget.currentRight;
      _bottomCommentator = widget.currentBottom;
      _bottomRightCommentator = widget.currentBottomRight;
      _bottomFontFamily = Settings.getValue<String>('page_shape_bottom_font') ??
          AppFonts.defaultFont;
      _commentaryFontSize = PageShapeSettingsManager.getCommentaryFontSize();
      _highlightRelatedCommentators =
          PageShapeSettingsManager.getHighlightSetting(widget.bookTitle);
      _columnVisibility =
          PageShapeSettingsManager.getColumnVisibility(widget.bookTitle);
    });
  }

  Future<void> _loadCommentatorGroups() async {
    final eras = await utils.splitByEra(widget.availableCommentators);

    final known = <String>{
      ...?eras['תורה שבכתב'],
      ...?eras['חז"ל'],
      ...?eras['ראשונים'],
      ...?eras['אחרונים'],
      ...?eras['מחברי זמננו'],
    };

    final others = (eras['מפרשים נוספים'] ?? [])
        .toSet()
        .union(widget.availableCommentators
            .where((c) => !known.contains(c))
            .toList()
            .toSet())
        .toList();

    if (mounted) {
      setState(() {
        _groups = [
          CommentatorGroup(
            title: 'תורה שבכתב',
            commentators: eras['תורה שבכתב'] ?? const [],
          ),
          CommentatorGroup(
            title: 'חז"ל',
            commentators: eras['חז"ל'] ?? const [],
          ),
          CommentatorGroup(
            title: 'ראשונים',
            commentators: eras['ראשונים'] ?? const [],
          ),
          CommentatorGroup(
            title: 'אחרונים',
            commentators: eras['אחרונים'] ?? const [],
          ),
          CommentatorGroup(
            title: 'מחברי זמננו',
            commentators: eras['מחברי זמננו'] ?? const [],
          ),
          CommentatorGroup(
            title: 'שאר מפרשים',
            commentators: others,
          ),
        ];
        _isLoadingGroups = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    debugPrint(
        'PageShapeDialog: Saving settings for book: ${widget.bookTitle}');

    // שמירת הגדרות מפרשים - לספר או לקטגוריה לפי הבחירה
    final config = {
      'left': _leftCommentator,
      'right': _rightCommentator,
      'bottom': _bottomCommentator,
      'bottomRight': _bottomRightCommentator,
    };

    debugPrint('PageShapeDialog: Config to save: $config');
    debugPrint('PageShapeDialog: Save scope: $_commentatorSaveScope');
    debugPrint('PageShapeDialog: Selected category: $_selectedCategory');

    if (_commentatorSaveScope == CommentatorSaveScope.category &&
        _selectedCategory != null) {
      // שמירה לקטגוריה
      debugPrint('PageShapeDialog: Saving to category: $_selectedCategory');
      await PageShapeSettingsManager.saveConfiguration(
        widget.bookTitle,
        config,
        saveToCategory: _selectedCategory,
      );
      // מחיקת הגדרות מפרשים ספציפיות לספר אם יש
      await PageShapeSettingsManager.resetBookCommentatorConfig(
          widget.bookTitle);
    } else {
      // שמירה לספר ספציפי
      debugPrint('PageShapeDialog: Saving to book: ${widget.bookTitle}');
      await PageShapeSettingsManager.saveConfiguration(
        widget.bookTitle,
        config,
      );
    }

    // שמירת הגופן של המפרשים התחתונים (תמיד גלובלי)
    await Settings.setValue<String>(
        'page_shape_bottom_font', _bottomFontFamily);

    // שמירת הגדרת הדגשה - גלובלי או פר-ספר לפי הבחירה
    await PageShapeSettingsManager.saveHighlightSetting(
      widget.bookTitle,
      _highlightRelatedCommentators,
      saveAsGlobal: !_saveForCurrentBookOnly,
    );

    // שמירת הגדרות visibility - גלובלי או פר-ספר לפי הבחירה
    await PageShapeSettingsManager.saveColumnVisibility(
      widget.bookTitle,
      _columnVisibility,
      saveAsGlobal: !_saveForCurrentBookOnly,
    );

    debugPrint('PageShapeDialog: Settings saved successfully');
  }

  void _onCommentatorChanged(String? value, void Function(String?) setter,
      {String? visibilityKey}) {
    setState(() {
      setter(value);
      _hasChanges = true;
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
      _hasChanges = true;
    });
    _saveSettings();
  }

  void _onFontSizeChanged(double value) {
    setState(() {
      _commentaryFontSize = value;
      _hasChanges = true;
    });
    PageShapeSettingsManager.saveCommentaryFontSize(value);
  }

  void _toggleColumnVisibility(String column, bool visible) {
    setState(() {
      _columnVisibility[column] = visible;
      _hasChanges = true;
    });
    _saveSettings();
  }

  /// איפוס הגדרות תצוגה פר-ספר וחזרה לגלובלי (לא משפיע על בחירת מפרשים)
  Future<void> _resetDisplaySettingsToGlobal() async {
    await PageShapeSettingsManager.resetBookDisplaySettings(widget.bookTitle);
    // טעינה מחדש של הגדרות התצוגה הגלובליות (לא מפרשים!)
    final highlight =
        PageShapeSettingsManager.getHighlightSetting(widget.bookTitle);
    final visibility =
        PageShapeSettingsManager.getColumnVisibility(widget.bookTitle);
    if (!mounted) return;
    setState(() {
      _saveForCurrentBookOnly = false;
      _hasChanges = true;
      _highlightRelatedCommentators = highlight;
      _columnVisibility = visibility;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('הגדרות צורת הדף'),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // בחירה בין גלובלי לפר-ספר (להגדרות תצוגה בלבד)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _saveForCurrentBookOnly
                              ? FluentIcons.book_24_regular
                              : FluentIcons.globe_24_regular,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _saveForCurrentBookOnly
                                ? 'הגדרות תצוגה לספר הנוכחי בלבד'
                                : 'הגדרות תצוגה גלובליות',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      title: Text(
                        _saveForCurrentBookOnly
                            ? 'שמירה לספר הנוכחי בלבד'
                            : 'שמירה גלובלית (לכל הספרים)',
                      ),
                      subtitle: Text(
                        _saveForCurrentBookOnly
                            ? 'הדגשה והצגת טורים יחולו רק על "${widget.bookTitle}"'
                            : 'הדגשה והצגת טורים יחולו על כל הספרים',
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: _saveForCurrentBookOnly,
                      onChanged: (value) async {
                        if (!value && _saveForCurrentBookOnly) {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('חזרה להגדרות גלובליות'),
                              content: const Text(
                                'האם לאפס את הגדרות התצוגה הספציפיות לספר זה ולחזור להגדרות הגלובליות?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('ביטול'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('אפס'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await _resetDisplaySettingsToGlobal();
                          }
                        } else {
                          setState(() {
                            _saveForCurrentBookOnly = value;
                            _hasChanges = true;
                          });
                          await _saveSettings();
                        }
                      },
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ],
                ),
              ),

              // בחירת היכן לשמור את הגדרות המפרשים
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.3),
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
                        Text(
                          'שמירת בחירת מפרשים',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // אפשרות 1: לספר הנוכחי
                    RadioGroup<CommentatorSaveScope>(
                      groupValue: _commentatorSaveScope,
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _commentatorSaveScope = value;
                            _hasChanges = true;
                          });
                          _saveSettings();
                        }
                      },
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Radio<CommentatorSaveScope>(
                                value: CommentatorSaveScope.book,
                              ),
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _commentatorSaveScope =
                                          CommentatorSaveScope.book;
                                      _hasChanges = true;
                                    });
                                    _saveSettings();
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 8.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text('לספר הנוכחי בלבד'),
                                        Text(
                                          'המפרשים יחולו רק על "${widget.bookTitle}"',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          // אפשרות 2: לקטגוריה - רק אם יש קטגוריות זמינות
                          if (_availableCategories.isNotEmpty)
                            Row(
                              children: [
                                Radio<CommentatorSaveScope>(
                                  value: CommentatorSaveScope.category,
                                ),
                                Expanded(
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        _commentatorSaveScope =
                                            CommentatorSaveScope.category;
                                        _hasChanges = true;
                                      });
                                      _saveSettings();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 8.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text('לכל הספרים בקטגוריה'),
                                          if (_selectedCategory != null)
                                            Text(
                                              'המפרשים יחולו על כל ספרי "$_selectedCategory"',
                                              style:
                                                  const TextStyle(fontSize: 11),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    // בחירת קטגוריה
                    if (_commentatorSaveScope ==
                            CommentatorSaveScope.category &&
                        _availableCategories.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedCategory,
                        decoration: InputDecoration(
                          labelText: 'בחר קטגוריה',
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                        ),
                        items: _availableCategories.map((category) {
                          return DropdownMenuItem<String>(
                            value: category,
                            child: Text(category,
                                style: const TextStyle(fontSize: 13)),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedCategory = value;
                            _hasChanges = true;
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
                subtitle:
                    const Text('הדגשת קטעים בפרשנים הקשורים לשורה שנבחרה'),
                value: _highlightRelatedCommentators,
                onChanged: (value) {
                  setState(() {
                    _highlightRelatedCommentators = value;
                    _hasChanges = true;
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
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'לחץ על סמל העין כדי להציג או להסתיר טור',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
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
                    value, (v) => _leftCommentator = v,
                    visibilityKey: 'left'),
                visibilityKey: 'left',
              ),
              const SizedBox(height: 12),
              _buildCommentatorDropdown(
                label: 'מפרש שמאלי',
                value: _rightCommentator,
                onChanged: (value) => _onCommentatorChanged(
                    value, (v) => _rightCommentator = v,
                    visibilityKey: 'right'),
                visibilityKey: 'right',
                allowRemainingCommentatorsSelection: true,
              ),
              const SizedBox(height: 12),
              _buildCommentatorDropdown(
                label: 'מפרש תחתון',
                value: _bottomCommentator,
                onChanged: (value) => _onCommentatorChanged(
                    value, (v) => _bottomCommentator = v,
                    visibilityKey: 'bottom'),
                visibilityKey: 'bottom',
              ),
              const SizedBox(height: 12),
              _buildCommentatorDropdown(
                label: 'מפרש תחתון נוסף',
                value: _bottomRightCommentator,
                onChanged: (value) => _onCommentatorChanged(
                    value, (v) => _bottomRightCommentator = v),
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              // גודל גופן המפרשים
              Row(
                children: [
                  const SizedBox(
                    width: 140,
                    child: Text(
                      'גודל גופן מפרשים:',
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(FluentIcons.subtract_24_regular),
                          onPressed: _commentaryFontSize > 10
                              ? () =>
                                  _onFontSizeChanged(_commentaryFontSize - 1)
                              : null,
                        ),
                        SizedBox(
                          width: 50,
                          child: Text(
                            '${_commentaryFontSize.round()}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(FluentIcons.add_24_regular),
                          onPressed: _commentaryFontSize < 30
                              ? () =>
                                  _onFontSizeChanged(_commentaryFontSize + 1)
                              : null,
                        ),
                        Expanded(
                          child: Slider(
                            value: _commentaryFontSize,
                            min: 10,
                            max: 30,
                            divisions: 20,
                            onChanged: _onFontSizeChanged,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(
                    width: 140,
                    child: Text(
                      'גופן מפרשים תחתונים:',
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _bottomFontFamily,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      items: AppFonts.availableFonts.map((font) {
                        return DropdownMenuItem<String>(
                          value: font.value,
                          child: Text(
                            font.label,
                            style: TextStyle(
                              fontFamily:
                                  AppFonts.fontPaths.containsKey(font.value)
                                      ? font.value
                                      : null,
                              fontSize: 13,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          _onFontChanged(value);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        // כפתור איפוס הגדרות מפרשים
        TextButton.icon(
          onPressed: () async {
            final navigator = Navigator.of(context);
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('איפוס הגדרות מפרשים'),
                content: const Text(
                  'האם לאפס את הגדרות המפרשים לברירות המחדל?\n\n'
                  'פעולה זו תמחק את ההגדרות השמורות ותטען את המפרשים המתאימים לפי סוג הספר.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('ביטול'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('אפס'),
                  ),
                ],
              ),
            );

            if (confirm == true) {
              // מחיקת הגדרות מפרשים פר-ספר
              await PageShapeSettingsManager.resetBookCommentatorConfig(
                  widget.bookTitle);

              // טעינה מחדש של ברירות המחדל
              if (!mounted) return;
              navigator.pop(true); // סגירת הדיאלוג עם סימון שהיו שינויים
            }
          },
          icon: const Icon(FluentIcons.arrow_reset_24_regular, size: 18),
          label: const Text('איפוס מפרשים'),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
        ),
        const SizedBox(width: 12),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_hasChanges),
          child: const Text('סגור'),
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
  }) {
    final isVisible = visibilityKey != null
        ? (_columnVisibility[visibilityKey] ?? true)
        : true;

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
                  : Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.4),
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
          child: InkWell(
            onTap: () => _showCommentatorPicker(
              value,
              onChanged,
              allowRemainingCommentatorsSelection:
                  allowRemainingCommentatorsSelection,
            ),
            child: InputDecorator(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                suffixIcon: Icon(FluentIcons.chevron_down_24_regular, size: 20),
              ),
              child: Text(
                formatPageShapeCommentatorSelection(value),
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 13,
                  color: value == null
                      ? Theme.of(context).hintColor
                      : Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showCommentatorPicker(
    String? currentValue,
    ValueChanged<String?> onChanged,
    {bool allowRemainingCommentatorsSelection = false}
  ) async {
    if (_isLoadingGroups) {
      return;
    }

    final result = await showDialog<String?>(
      context: context,
      builder: (context) => _CommentatorPickerDialog(
        groups: _groups,
        currentValue: currentValue,
        availableCommentators: widget.availableCommentators,
        allowRemainingCommentatorsSelection:
            allowRemainingCommentatorsSelection,
      ),
    );

    if (result != null) {
      onChanged(result == '__NONE__' ? null : result);
    }
  }
}

/// דיאלוג בחירת מפרש עם חיפוש וקיבוץ
class _CommentatorPickerDialog extends StatefulWidget {
  final List<CommentatorGroup> groups;
  final String? currentValue;
  final List<String> availableCommentators;
  final bool allowRemainingCommentatorsSelection;

  const _CommentatorPickerDialog({
    required this.groups,
    required this.currentValue,
    required this.availableCommentators,
    this.allowRemainingCommentatorsSelection = false,
  });

  @override
  State<_CommentatorPickerDialog> createState() =>
      _CommentatorPickerDialogState();
}

class _CommentatorPickerDialogState extends State<_CommentatorPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<String> _filteredCommentators = [];
  List<CommentatorGroup> _filteredGroups = [];

  @override
  void initState() {
    super.initState();
    _updateFilteredList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _updateFilteredList() {
    final query = _searchController.text.trim();

    if (query.isEmpty) {
      setState(() {
        _filteredGroups = widget.groups
            .where((group) => group.commentators.isNotEmpty)
            .toList();
        _filteredCommentators = [];
      });
    } else {
      final filtered =
          widget.availableCommentators.where((c) => c.contains(query)).toList();
      setState(() {
        _filteredCommentators = filtered;
        _filteredGroups = [];
      });
    }
  }

  bool _shouldShowRemainingOption() {
    if (!widget.allowRemainingCommentatorsSelection) {
      return false;
    }

    final query = _searchController.text.trim();
    if (query.isEmpty) {
      return true;
    }

    return pageShapeRemainingCommentatorsLabel.contains(query) ||
        'מפרשים נוספים'.contains(query);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 500,
        height: 600,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'בחר מפרש',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: RtlTextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: "חיפוש מפרש...",
                  prefixIcon: const Icon(FluentIcons.search_24_regular),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _searchController.clear();
                            _updateFilteredList();
                          },
                          icon: const Icon(FluentIcons.dismiss_24_regular),
                        )
                      : null,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                onChanged: (_) => _updateFilteredList(),
              ),
            ),
            Expanded(
              child: _searchController.text.isEmpty
                  ? _buildGroupedList()
                  : _buildFilteredList(),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('ביטול'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop('__NONE__'),
                    child: const Text('ללא מפרש'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedList() {
    return ListView(
      children: [
        if (_shouldShowRemainingOption()) _buildRemainingCommentatorsTile(),
        for (final group in _filteredGroups)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                child: Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        group.title,
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
              ),
              ...group.commentators
                  .map((commentator) => _buildCommentatorTile(commentator)),
            ],
          ),
      ],
    );
  }

  Widget _buildFilteredList() {
    if (_filteredCommentators.isEmpty && !_shouldShowRemainingOption()) {
      return const Center(
        child: Text(
          'לא נמצאו מפרשים',
          textDirection: TextDirection.rtl,
        ),
      );
    }

    return ListView(
      children: [
        if (_shouldShowRemainingOption()) _buildRemainingCommentatorsTile(),
        ..._filteredCommentators
            .map((commentator) => _buildCommentatorTile(commentator)),
      ],
    );
  }

  Widget _buildRemainingCommentatorsTile() {
    final isSelected =
        widget.currentValue == pageShapeRemainingCommentatorsValue;

    return ListTile(
      title: const Text(
        pageShapeRemainingCommentatorsLabel,
        textDirection: TextDirection.rtl,
      ),
      subtitle: const Text(
        'כל המפרשים שלא שובצו בחלוניות האחרות',
        textDirection: TextDirection.rtl,
      ),
      selected: isSelected,
      trailing:
          isSelected ? const Icon(FluentIcons.checkmark_24_regular) : null,
      onTap: () =>
          Navigator.of(context).pop(pageShapeRemainingCommentatorsValue),
    );
  }

  Widget _buildCommentatorTile(String commentator) {
    final isSelected = commentator == widget.currentValue;

    return ListTile(
      title: Text(
        commentator,
        textDirection: TextDirection.rtl,
      ),
      selected: isSelected,
      trailing:
          isSelected ? const Icon(FluentIcons.checkmark_24_regular) : null,
      onTap: () => Navigator.of(context).pop(commentator),
    );
  }
}
