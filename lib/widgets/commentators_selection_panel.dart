import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/utils/text_manipulation.dart';
import 'package:otzaria/widgets/filter_chips_widget.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';

class CommentatorsSelectionPanel extends StatefulWidget {
  final List<CommentatorGroup> groups;
  final List<String> selectedCommentators;
  final ValueChanged<List<String>> onSelectionChanged;
  final VoidCallback? onSelectionApplied;
  final String bookTitle;
  final Widget? emptyState;

  const CommentatorsSelectionPanel({
    super.key,
    required this.groups,
    required this.selectedCommentators,
    required this.onSelectionChanged,
    required this.bookTitle,
    this.onSelectionApplied,
    this.emptyState,
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
        oldWidget.bookTitle != widget.bookTitle) {
      _update();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<String>> _filterGroup(List<String> group) async {
    final filteredByQuery =
        group.where((title) => title.contains(_searchController.text));

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
    widget.onSelectionChanged(commentators);
    widget.onSelectionApplied?.call();
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
    final items = _commentatorsList
        .where((e) => !e.startsWith('__TITLE_') && !e.startsWith('__BUTTON_'))
        .toList();

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

  @override
  Widget build(BuildContext context) {
    if (widget.groups.every((group) => group.commentators.isEmpty)) {
      return widget.emptyState ??
          const Center(
            child: Text(
              'אין מפרשים',
              textDirection: TextDirection.rtl,
            ),
          );
    }

    return Column(
      children: [
        FilterChipsSelector<String>(
          items: [
            'תורה שבכתב',
            'חז"ל',
            'ראשונים',
            'אחרונים',
            'מחברי זמננו',
            'על ${widget.bookTitle}',
          ],
          selectedItems: _selectedTopics,
          labelBuilder: (item) => item,
          wrapAlignment: WrapAlignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          onSelectionChanged: (list) {
            _selectedTopics = list;
            _update();
          },
          chipBuilder: (context, item, isSelected) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            child: Chip(
              label: Text(
                item,
                textDirection: TextDirection.rtl,
              ),
              backgroundColor:
                  isSelected ? Theme.of(context).colorScheme.secondary : null,
              labelStyle: TextStyle(
                color: isSelected
                    ? Theme.of(context).colorScheme.onSecondary
                    : null,
                fontSize: 11,
              ),
              labelPadding: const EdgeInsets.all(0),
            ),
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: RtlTextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'סינון מפרשים...',
                    prefixIcon: const Icon(FluentIcons.search_24_regular),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _searchController.clear();
                              _update();
                            },
                            icon: const Icon(FluentIcons.dismiss_24_regular),
                          )
                        : null,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  onChanged: (_) => _update(),
                ),
              ),
              if (_commentatorsList.isNotEmpty)
                CheckboxListTile(
                  title: const Text(
                    'הצג את כל המפרשים',
                    textDirection: TextDirection.rtl,
                  ),
                  value: _commentatorsList
                      .where((e) =>
                          !e.startsWith('__TITLE_') &&
                          !e.startsWith('__BUTTON_'))
                      .every(widget.selectedCommentators.contains),
                  onChanged: (checked) => _toggleAllVisible(checked ?? false),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: _commentatorsList.length,
                  itemBuilder: (context, index) {
                    final item = _commentatorsList[index];

                    if (item == _torahShebichtavButton) {
                      return CheckboxListTile(
                        title: const Text(
                          'הצג את כל התורה שבכתב',
                          textDirection: TextDirection.rtl,
                        ),
                        value: _torahShebichtav
                            .every(widget.selectedCommentators.contains),
                        onChanged: (checked) =>
                            _toggleGroup(_torahShebichtav, checked ?? false),
                      );
                    }
                    if (item == _chazalButton) {
                      return CheckboxListTile(
                        title: const Text(
                          'הצג את כל חז"ל',
                          textDirection: TextDirection.rtl,
                        ),
                        value:
                            _chazal.every(widget.selectedCommentators.contains),
                        onChanged: (checked) =>
                            _toggleGroup(_chazal, checked ?? false),
                      );
                    }
                    if (item == _rishonimButton) {
                      return CheckboxListTile(
                        title: const Text(
                          'הצג את כל הראשונים',
                          textDirection: TextDirection.rtl,
                        ),
                        value: _rishonim
                            .every(widget.selectedCommentators.contains),
                        onChanged: (checked) =>
                            _toggleGroup(_rishonim, checked ?? false),
                      );
                    }
                    if (item == _acharonimButton) {
                      return CheckboxListTile(
                        title: const Text(
                          'הצג את כל האחרונים',
                          textDirection: TextDirection.rtl,
                        ),
                        value: _acharonim
                            .every(widget.selectedCommentators.contains),
                        onChanged: (checked) =>
                            _toggleGroup(_acharonim, checked ?? false),
                      );
                    }
                    if (item == _modernButton) {
                      return CheckboxListTile(
                        title: const Text(
                          'הצג את כל מחברי זמננו',
                          textDirection: TextDirection.rtl,
                        ),
                        value:
                            _modern.every(widget.selectedCommentators.contains),
                        onChanged: (checked) =>
                            _toggleGroup(_modern, checked ?? false),
                      );
                    }
                    if (item == _ungroupedButton) {
                      return CheckboxListTile(
                        title: const Text(
                          'הצג את כל שאר המפרשים',
                          textDirection: TextDirection.rtl,
                        ),
                        value: _ungrouped
                            .every(widget.selectedCommentators.contains),
                        onChanged: (checked) =>
                            _toggleGroup(_ungrouped, checked ?? false),
                      );
                    }

                    if (item.startsWith('__TITLE_')) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10.0,
                          horizontal: 16.0,
                        ),
                        child: Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8.0),
                              child: Text(
                                _titleTextForToken(item),
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
                      );
                    }

                    return CheckboxListTile(
                      title: Text(
                        item,
                        textDirection: TextDirection.rtl,
                      ),
                      value: widget.selectedCommentators.contains(item),
                      onChanged: (checked) =>
                          _toggleSingleCommentator(item, checked ?? false),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
