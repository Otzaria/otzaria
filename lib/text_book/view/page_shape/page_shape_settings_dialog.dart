import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_commentary_config.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/commentators_selection_panel.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';

enum CommentatorSaveScope {
  book,
  category,
}

Future<String?> showPageShapeSingleCommentatorPickerDialog({
  required BuildContext context,
  required List<CommentatorGroup> groups,
  required String? currentValue,
  required List<String> availableCommentators,
}) {
  return showDialog<String?>(
    context: context,
    builder: (context) => _CommentatorPickerDialog(
      groups: groups,
      currentValue: currentValue,
      availableCommentators: availableCommentators,
    ),
  );
}

Future<List<String>?> showPageShapeMultipleCommentatorsPickerDialog({
  required BuildContext context,
  required List<CommentatorGroup> groups,
  required List<String> initialSelection,
  required String bookTitle,
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (context) => _MultipleCommentatorsPickerDialog(
      groups: groups,
      initialSelection: initialSelection,
      bookTitle: bookTitle,
    ),
  );
}

class PageShapeSettingsDialog extends StatefulWidget {
  final List<String> availableCommentators;
  final String bookTitle;
  final String? heCategories;
  final PageShapeConfiguration currentConfiguration;

  const PageShapeSettingsDialog({
    super.key,
    required this.availableCommentators,
    required this.bookTitle,
    required this.currentConfiguration,
    this.heCategories,
  });

  @override
  State<PageShapeSettingsDialog> createState() =>
      _PageShapeSettingsDialogState();
}

class _PageShapeSettingsDialogState extends State<PageShapeSettingsDialog> {
  late PageShapeConfiguration _configuration;
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
  bool _saveForCurrentBookOnly = false;
  CommentatorSaveScope _commentatorSaveScope = CommentatorSaveScope.book;
  String? _selectedCategory;
  List<String> _availableCategories = [];

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
    _loadCommentatorGroups();
  }

  void _loadCurrentSettings() {
    _configuration = widget.currentConfiguration;
    _saveForCurrentBookOnly =
        PageShapeSettingsManager.hasBookSpecificSettings(widget.bookTitle);

    _availableCategories =
        PageShapeSettingsManager.parseCategories(widget.heCategories);
    if (_availableCategories.isEmpty && widget.bookTitle.contains(',')) {
      final firstPart = widget.bookTitle.split(',').first.trim();
      if (firstPart.isNotEmpty) {
        _availableCategories = [firstPart];
      }
    }

    final activeCategory =
        PageShapeSettingsManager.getActiveCategory(widget.heCategories);
    if (activeCategory != null) {
      _commentatorSaveScope = CommentatorSaveScope.category;
      _selectedCategory = activeCategory;
    } else {
      _commentatorSaveScope = CommentatorSaveScope.book;
      _selectedCategory =
          _availableCategories.isNotEmpty ? _availableCategories.first : null;
    }

    _bottomFontFamily = Settings.getValue<String>('page_shape_bottom_font') ??
        AppFonts.defaultFont;
    _commentaryFontSize = PageShapeSettingsManager.getCommentaryFontSize();
    _highlightRelatedCommentators =
        PageShapeSettingsManager.getHighlightSetting(widget.bookTitle);
    _columnVisibility =
        PageShapeSettingsManager.getColumnVisibility(widget.bookTitle);
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
            .toSet())
        .toList();

    if (!mounted) return;
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

  Future<void> _saveSettings() async {
    if (_commentatorSaveScope == CommentatorSaveScope.category &&
        _selectedCategory != null) {
      await PageShapeSettingsManager.saveConfiguration(
        widget.bookTitle,
        _configuration,
        saveToCategory: _selectedCategory,
      );
      await PageShapeSettingsManager.resetBookCommentatorConfig(
          widget.bookTitle);
    } else {
      await PageShapeSettingsManager.saveConfiguration(
        widget.bookTitle,
        _configuration,
      );
    }

    await Settings.setValue<String>(
        'page_shape_bottom_font', _bottomFontFamily);
    await PageShapeSettingsManager.saveHighlightSetting(
      widget.bookTitle,
      _highlightRelatedCommentators,
      saveAsGlobal: !_saveForCurrentBookOnly,
    );
    await PageShapeSettingsManager.saveColumnVisibility(
      widget.bookTitle,
      _columnVisibility,
      saveAsGlobal: !_saveForCurrentBookOnly,
    );
  }

  PageShapeSlotConfiguration _slotFor(String key) {
    return _configuration.slotFor(key);
  }

  String _slotLabel(String key) {
    switch (key) {
      case 'left':
        return 'מפרש ימני';
      case 'right':
        return 'מפרש שמאלי';
      case 'bottom':
        return 'מפרש תחתון';
      case 'bottomRight':
        return 'מפרש תחתון נוסף';
      default:
        return key;
    }
  }

  String _slotSummary(PageShapeSlotConfiguration slot) {
    if (slot.commentators.isEmpty) {
      return 'ללא מפרש';
    }
    if (slot.mode == PageShapeCommentaryMode.single ||
        slot.commentators.length == 1) {
      return slot.primaryCommentator!;
    }
    final visible = slot.commentators.take(3).join(', ');
    final remaining = slot.commentators.length - 3;
    if (remaining > 0) {
      return '$visible ועוד $remaining';
    }
    return visible;
  }

  Future<void> _updateSlot(
    String key,
    PageShapeSlotConfiguration slot, {
    String? visibilityKey,
  }) async {
    setState(() {
      _configuration = _configuration.copyWith(
        left: key == 'left' ? slot : null,
        right: key == 'right' ? slot : null,
        bottom: key == 'bottom' ? slot : null,
        bottomRight: key == 'bottomRight' ? slot : null,
      );
      _hasChanges = true;
      if (visibilityKey != null &&
          slot.commentators.isNotEmpty &&
          _columnVisibility[visibilityKey] == false) {
        _columnVisibility[visibilityKey] = true;
      }
    });
    await _saveSettings();
  }

  Future<void> _toggleSlotMode(
    String key,
    PageShapeCommentaryMode mode, {
    String? visibilityKey,
  }) async {
    final current = _slotFor(key);
    final commentators = mode == PageShapeCommentaryMode.multiple
        ? List<String>.from(widget.availableCommentators)
        : current.commentators.isEmpty
            ? <String>[]
            : [current.commentators.first];
    await _updateSlot(
      key,
      PageShapeSlotConfiguration(mode: mode, commentators: commentators),
      visibilityKey: visibilityKey,
    );
  }

  Future<void> _pickSingleCommentator(
    String key, {
    String? visibilityKey,
  }) async {
    if (_isLoadingGroups) {
      return;
    }

    final current = _slotFor(key).primaryCommentator;
    final result = await showPageShapeSingleCommentatorPickerDialog(
      context: context,
      groups: _groups,
      currentValue: current,
      availableCommentators: widget.availableCommentators,
    );

    if (result == null) {
      return;
    }

    await _updateSlot(
      key,
      PageShapeSlotConfiguration(
        mode: PageShapeCommentaryMode.single,
        commentators: result == '__NONE__' ? const [] : [result],
      ),
      visibilityKey: visibilityKey,
    );
  }

  Future<void> _pickMultipleCommentators(
    String key, {
    String? visibilityKey,
  }) async {
    if (_isLoadingGroups) {
      return;
    }

    final result = await showPageShapeMultipleCommentatorsPickerDialog(
      context: context,
      groups: _groups,
      initialSelection: _slotFor(key).commentators,
      bookTitle: widget.bookTitle,
    );

    if (result == null) {
      return;
    }

    await _updateSlot(
      key,
      PageShapeSlotConfiguration(
        mode: PageShapeCommentaryMode.multiple,
        commentators: result,
      ),
      visibilityKey: visibilityKey,
    );
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

  Future<void> _resetDisplaySettingsToGlobal() async {
    await PageShapeSettingsManager.resetBookDisplaySettings(widget.bookTitle);
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

  Widget _buildSlotEditor(String key, {String? visibilityKey}) {
    final slot = _slotFor(key);
    final isVisible = visibilityKey != null
        ? (_columnVisibility[visibilityKey] ?? true)
        : true;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (visibilityKey != null)
                IconButton(
                  icon: Icon(
                    isVisible
                        ? FluentIcons.eye_24_regular
                        : FluentIcons.eye_off_24_regular,
                    size: 20,
                  ),
                  tooltip: isVisible ? 'הסתר טור' : 'הצג טור',
                  onPressed: () =>
                      _toggleColumnVisibility(visibilityKey, !isVisible),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              Expanded(
                child: Text(
                  _slotLabel(key),
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<PageShapeCommentaryMode>(
                  initialValue: slot.mode,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: PageShapeCommentaryMode.single,
                      child: Text('מפרש יחיד'),
                    ),
                    DropdownMenuItem(
                      value: PageShapeCommentaryMode.multiple,
                      child: Text('מפרשים מרובים'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _toggleSlotMode(key, value, visibilityKey: visibilityKey);
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () {
                  if (slot.mode == PageShapeCommentaryMode.single) {
                    _pickSingleCommentator(key, visibilityKey: visibilityKey);
                  } else {
                    _pickMultipleCommentators(key,
                        visibilityKey: visibilityKey);
                  }
                },
                icon: Icon(
                  slot.mode == PageShapeCommentaryMode.single
                      ? FluentIcons.book_24_regular
                      : FluentIcons.checkbox_checked_24_regular,
                  size: 18,
                ),
                label: Text(
                  slot.mode == PageShapeCommentaryMode.single
                      ? 'בחר מפרש'
                      : 'בחר מפרשים',
                  textDirection: TextDirection.rtl,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _slotSummary(slot),
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'הגדרות צורת הדף',
        textDirection: TextDirection.rtl,
      ),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                            textDirection: TextDirection.rtl,
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
                        textDirection: TextDirection.rtl,
                      ),
                      subtitle: Text(
                        _saveForCurrentBookOnly
                            ? 'הדגשה והצגת טורים יחולו רק על "${widget.bookTitle}"'
                            : 'הדגשה והצגת טורים יחולו על כל הספרים',
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: _saveForCurrentBookOnly,
                      onChanged: (value) async {
                        if (!value && _saveForCurrentBookOnly) {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text(
                                'חזרה להגדרות גלובליות',
                                textDirection: TextDirection.rtl,
                              ),
                              content: const Text(
                                'האם לאפס את הגדרות התצוגה הספציפיות לספר זה ולחזור להגדרות הגלובליות?',
                                textDirection: TextDirection.rtl,
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
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
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
                      child: Row(
                        children: [
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
                              child: Row(
                                children: [
                                  const Radio<CommentatorSaveScope>(
                                    value: CommentatorSaveScope.book,
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'לספר הנוכחי בלבד',
                                          textDirection: TextDirection.rtl,
                                        ),
                                        Text(
                                          'המפרשים יחולו רק על "${widget.bookTitle}"',
                                          textDirection: TextDirection.rtl,
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_availableCategories.isNotEmpty) ...[
                            const SizedBox(width: 12),
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
                                child: Row(
                                  children: [
                                    const Radio<CommentatorSaveScope>(
                                      value: CommentatorSaveScope.category,
                                    ),
                                    const Expanded(
                                      child: Text(
                                        'לכל הספרים בקטגוריה',
                                        textDirection: TextDirection.rtl,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
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
                            child: Text(
                              category,
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(fontSize: 13),
                            ),
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
                textDirection: TextDirection.rtl,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SwitchListTile(
                title: const Text(
                  'הדגש פרשנים קשורים',
                  textDirection: TextDirection.rtl,
                ),
                subtitle: const Text(
                  'הדגשת קטעים בפרשנים הקשורים לשורה שנבחרה',
                  textDirection: TextDirection.rtl,
                ),
                value: _highlightRelatedCommentators,
                onChanged: (value) {
                  setState(() {
                    _highlightRelatedCommentators = value;
                    _hasChanges = true;
                  });
                  _saveSettings();
                },
              ),
              const SizedBox(height: 8),
              _buildSlotEditor('left', visibilityKey: 'left'),
              const SizedBox(height: 12),
              _buildSlotEditor('right', visibilityKey: 'right'),
              const SizedBox(height: 12),
              _buildSlotEditor('bottom', visibilityKey: 'bottom'),
              const SizedBox(height: 12),
              _buildSlotEditor('bottomRight'),
              const SizedBox(height: 20),
              const Divider(),
              Row(
                children: [
                  const SizedBox(
                    width: 140,
                    child: Text(
                      'גודל גופן מפרשים:',
                      textDirection: TextDirection.rtl,
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
                      textDirection: TextDirection.rtl,
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
                            textDirection: TextDirection.rtl,
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
        TextButton.icon(
          onPressed: () async {
            final navigator = Navigator.of(context);
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text(
                  'איפוס הגדרות מפרשים',
                  textDirection: TextDirection.rtl,
                ),
                content: const Text(
                  'האם לאפס את הגדרות המפרשים לברירות המחדל?\n\nפעולה זו תמחק את ההגדרות השמורות ותטען את המפרשים המתאימים לפי סוג הספר.',
                  textDirection: TextDirection.rtl,
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
              await PageShapeSettingsManager.resetBookCommentatorConfig(
                  widget.bookTitle);
              if (!mounted) return;
              navigator.pop(true);
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
}

class _CommentatorPickerDialog extends StatefulWidget {
  final List<CommentatorGroup> groups;
  final String? currentValue;
  final List<String> availableCommentators;

  const _CommentatorPickerDialog({
    required this.groups,
    required this.currentValue,
    required this.availableCommentators,
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
                textDirection: TextDirection.rtl,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: RtlTextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'חיפוש מפרש...',
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
    return ListView.builder(
      itemCount: _filteredGroups.length,
      itemBuilder: (context, groupIndex) {
        final group = _filteredGroups[groupIndex];
        return Column(
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
        );
      },
    );
  }

  Widget _buildFilteredList() {
    if (_filteredCommentators.isEmpty) {
      return const Center(
        child: Text(
          'לא נמצאו מפרשים',
          textDirection: TextDirection.rtl,
        ),
      );
    }

    return ListView.builder(
      itemCount: _filteredCommentators.length,
      itemBuilder: (context, index) {
        return _buildCommentatorTile(_filteredCommentators[index]);
      },
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

class _MultipleCommentatorsPickerDialog extends StatefulWidget {
  final List<CommentatorGroup> groups;
  final List<String> initialSelection;
  final String bookTitle;

  const _MultipleCommentatorsPickerDialog({
    required this.groups,
    required this.initialSelection,
    required this.bookTitle,
  });

  @override
  State<_MultipleCommentatorsPickerDialog> createState() =>
      _MultipleCommentatorsPickerDialogState();
}

class _MultipleCommentatorsPickerDialogState
    extends State<_MultipleCommentatorsPickerDialog> {
  late List<String> _selectedCommentators;

  @override
  void initState() {
    super.initState();
    _selectedCommentators = List<String>.from(widget.initialSelection);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 560,
        height: 700,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'בחר מפרשים מרובים',
                textDirection: TextDirection.rtl,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: CommentatorsSelectionPanel(
                  groups: widget.groups,
                  selectedCommentators: _selectedCommentators,
                  onSelectionChanged: (commentators) {
                    setState(() {
                      _selectedCommentators = commentators;
                    });
                  },
                  bookTitle: widget.bookTitle,
                ),
              ),
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
                    onPressed: () {
                      setState(() {
                        _selectedCommentators = [];
                      });
                    },
                    child: const Text('נקה'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_selectedCommentators),
                    child: const Text('אישור'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
