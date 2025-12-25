import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/constants/fonts.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/rtl_text_field.dart';

/// דיאלוג הגדרות צורת הדף - בחירת מפרשים לכל מיקום
class PageShapeSettingsDialog extends StatefulWidget {
  final List<String> availableCommentators;
  final String bookTitle;
  final String? currentLeft;
  final String? currentRight;
  final String? currentBottom;
  final String? currentBottomRight;

  const PageShapeSettingsDialog({
    super.key,
    required this.availableCommentators,
    required this.bookTitle,
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
  String _bottomFontFamily =
      AppFonts.defaultFont; // גופן ברירת מחדל למפרשים תחתונים
  List<CommentatorGroup> _groups = [];
  bool _isLoadingGroups = true;
  bool _hasChanges = false; // האם היו שינויים שצריך לשמור
  bool _highlightRelatedCommentators = false;
  Map<String, bool> _columnVisibility = {
    'left': true,
    'right': true,
    'bottom': true,
  };

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
    _loadCommentatorGroups();
  }

  void _loadCurrentSettings() {
    // טעינת הערכים הנוכחיים שהועברו מהמסך
    setState(() {
      _leftCommentator = widget.currentLeft;
      _rightCommentator = widget.currentRight;
      _bottomCommentator = widget.currentBottom;
      _bottomRightCommentator = widget.currentBottomRight;
      _bottomFontFamily = Settings.getValue<String>('page_shape_bottom_font') ??
          AppFonts.defaultFont;
      _highlightRelatedCommentators =
          PageShapeSettingsManager.getHighlightSetting(widget.bookTitle);
      _columnVisibility =
          PageShapeSettingsManager.getColumnVisibility(widget.bookTitle);
    });
  }

  Future<void> _loadCommentatorGroups() async {
    // חלוקת המפרשים לפי דורות
    final eras = await utils.splitByEra(widget.availableCommentators);

    // יצירת קבוצות מפרשים לפי דורות
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
    await PageShapeSettingsManager.saveConfiguration(
      widget.bookTitle,
      {
        'left': _leftCommentator,
        'right': _rightCommentator,
        'bottom': _bottomCommentator,
        'bottomRight': _bottomRightCommentator,
      },
    );
    // שמירת הגופן של המפרשים התחתונים (הגדרה גלובלית)
    await Settings.setValue<String>(
        'page_shape_bottom_font', _bottomFontFamily);
    await PageShapeSettingsManager.saveHighlightSetting(
      widget.bookTitle,
      _highlightRelatedCommentators,
    );
  }

  void _onCommentatorChanged(String? value, void Function(String?) setter) {
    setState(() {
      setter(value);
      _hasChanges = true;
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

  void _toggleColumnVisibility(String column, bool visible) {
    setState(() {
      _columnVisibility[column] = visible;
      _hasChanges = true;
    });
    PageShapeSettingsManager.saveColumnVisibility(
        widget.bookTitle, _columnVisibility);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('הגדרות צורת הדף'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              _buildCommentatorDropdown(
                label: 'מפרש ימני',
                value: _leftCommentator,
                onChanged: (value) =>
                    _onCommentatorChanged(value, (v) => _leftCommentator = v),
                visibilityKey: 'left',
              ),
              const SizedBox(height: 12),
              _buildCommentatorDropdown(
                label: 'מפרש שמאלי',
                value: _rightCommentator,
                onChanged: (value) =>
                    _onCommentatorChanged(value, (v) => _rightCommentator = v),
                visibilityKey: 'right',
              ),
              const SizedBox(height: 12),
              _buildCommentatorDropdown(
                label: 'מפרש תחתון',
                value: _bottomCommentator,
                onChanged: (value) =>
                    _onCommentatorChanged(value, (v) => _bottomCommentator = v),
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
                              fontFamily: font.value,
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
              isVisible ? Icons.visibility : Icons.visibility_off,
              size: 20,
              color: isVisible
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
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
            style: TextStyle(
              fontSize: 15,
              color: isVisible
                  ? null
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ),
        Expanded(
          child: Opacity(
            opacity: isVisible ? 1.0 : 0.5,
            child: InkWell(
              onTap: isVisible ? () => _showCommentatorPicker(value, onChanged) : null,
              child: InputDecorator(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  suffixIcon: Icon(Icons.arrow_drop_down, size: 20),
                ),
                child: Text(
                  value ?? 'ללא מפרש',
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
        ),
      ],
    );
  }

  Future<void> _showCommentatorPicker(
    String? currentValue,
    ValueChanged<String?> onChanged,
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
      // אין חיפוש - מציג את כל הקבוצות
      setState(() {
        _filteredGroups = widget.groups
            .where((group) => group.commentators.isNotEmpty)
            .toList();
        _filteredCommentators = [];
      });
    } else {
      // יש חיפוש - מסנן את המפרשים
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
            // כותרת
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'בחר מפרש',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(height: 1),

            // שדה חיפוש
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

            // רשימת המפרשים
            Expanded(
              child: _searchController.text.isEmpty
                  ? _buildGroupedList()
                  : _buildFilteredList(),
            ),

            // כפתורים
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
            // כותרת קבוצה
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
            // מפרשי הקבוצה
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
        child: Text('לא נמצאו מפרשים'),
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
      title: Text(commentator),
      selected: isSelected,
      trailing: isSelected ? const Icon(Icons.check) : null,
      onTap: () => Navigator.of(context).pop(commentator),
    );
  }
}
