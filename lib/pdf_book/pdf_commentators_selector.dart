import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/filter_list/src/filter_list_dialog.dart';
import 'package:otzaria/widgets/filter_list/src/theme/filter_list_theme.dart';

/// Widget לבחירת מפרשים עבור PDF - מבוסס על CommentatorsListView
class PdfCommentatorsSelector extends StatefulWidget {
  final PdfBookTab tab;
  final VoidCallback onChanged;

  const PdfCommentatorsSelector({
    super.key,
    required this.tab,
    required this.onChanged,
  });

  @override
  State<PdfCommentatorsSelector> createState() =>
      _PdfCommentatorsSelectorState();
}

class _PdfCommentatorsSelectorState extends State<PdfCommentatorsSelector> {
  TextEditingController searchController = TextEditingController();
  List<String> selectedTopics = [];
  List<String> commentatorsList = [];
  List<String> _torahShebichtav = [];
  List<String> _chazal = [];
  List<String> _rishonim = [];
  List<String> _acharonim = [];
  List<String> _modern = [];
  List<String> _ungrouped = [];
  List<CommentatorGroup> _groups = [];
  
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

  @override
  void initState() {
    super.initState();
    _loadCommentatorGroups();
  }

  void _loadCommentatorGroups() {
    // חילוץ רשימת המפרשים הייחודיים מה-links
    final commentatorsSet = <String>{};
    for (final link in widget.tab.links) {
      if (link.connectionType == "commentary" ||
          link.connectionType == "targum") {
        final commentatorName = utils.getTitleFromPath(link.path2);
        commentatorsSet.add(commentatorName);
      }
    }

    // יצירת קבוצות מפרשים פשוטה - כל המפרשים בקבוצה אחת
    _groups = [
      const CommentatorGroup(title: 'תורה שבכתב', commentators: []),
      const CommentatorGroup(title: 'חז"ל', commentators: []),
      const CommentatorGroup(title: 'ראשונים', commentators: []),
      const CommentatorGroup(title: 'אחרונים', commentators: []),
      const CommentatorGroup(title: 'מחברי זמננו', commentators: []),
      CommentatorGroup(
          title: 'שאר מפרשים',
          commentators: commentatorsSet.toList()..sort()),
    ];
    _update();
  }

  Future<List<String>> filterGroup(List<String> group) async {
    final filteredByQuery =
        group.where((title) => title.contains(searchController.text));

    if (selectedTopics.isEmpty) {
      return filteredByQuery.toList();
    }

    final List<String> filtered = [];
    for (final title in filteredByQuery) {
      for (final topic in selectedTopics) {
        if (await utils.hasTopic(title, topic)) {
          filtered.add(title);
          break;
        }
      }
    }
    return filtered;
  }

  Future<void> _update() async {
    // סינון הקבוצות הידועות
    final torahShebichtav = await filterGroup(
        CommentatorGroup.groupByTitle(_groups, 'תורה שבכתב').commentators);
    final chazal = await filterGroup(
        CommentatorGroup.groupByTitle(_groups, 'חז"ל').commentators);
    final rishonim = await filterGroup(
        CommentatorGroup.groupByTitle(_groups, 'ראשונים').commentators);
    final acharonim = await filterGroup(
        CommentatorGroup.groupByTitle(_groups, 'אחרונים').commentators);
    final modern = await filterGroup(
        CommentatorGroup.groupByTitle(_groups, 'מחברי זמננו').commentators);
    final ungrouped = await filterGroup(
        CommentatorGroup.groupByTitle(_groups, 'שאר מפרשים').commentators);

    _torahShebichtav = torahShebichtav;
    _chazal = chazal;
    _rishonim = rishonim;
    _acharonim = acharonim;
    _modern = modern;
    _ungrouped = ungrouped;

    // בניית הרשימה עם כותרות לפני כל קבוצה קיימת
    final List<String> merged = [];

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
    if (mounted) {
      setState(() => commentatorsList = merged);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (commentatorsList.isEmpty) {
      return const Center(
        child: Text("אין מפרשים"),
      );
    }

    return Column(
      children: [
        FilterListWidget<String>(
          hideSearchField: true,
          controlButtons: const [],
          onApplyButtonClick: (list) {
            selectedTopics = list ?? [];
            _update();
          },
          validateSelectedItem: (list, item) =>
              list != null && list.contains(item),
          onItemSearch: (item, query) => item == query,
          listData: [
            'תורה שבכתב',
            'חז"ל',
            'ראשונים',
            'אחרונים',
            'מחברי זמננו',
          ],
          selectedListData: selectedTopics,
          choiceChipLabel: (p0) => p0,
          hideSelectedTextCount: true,
          themeData: FilterListThemeData(
            context,
            wrapAlignment: WrapAlignment.center,
          ),
          choiceChipBuilder: (context, item, isSelected) => Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 3,
              vertical: 2,
            ),
            child: Chip(
              label: Text(item),
              backgroundColor: isSelected!
                  ? Theme.of(context).colorScheme.secondary
                  : null,
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
              // שדה החיפוש
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: "סינון מפרשים...",
                    prefixIcon: const Icon(FluentIcons.search_24_regular),
                    suffixIcon: searchController.text.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              searchController.clear();
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

              // כפתור הכל
              if (commentatorsList.isNotEmpty)
                CheckboxListTile(
                  title: const Text('הצג את כל המפרשים'),
                  value: commentatorsList
                      .where((e) =>
                          !e.startsWith('__TITLE_') &&
                          !e.startsWith('__BUTTON_'))
                      .every(widget.tab.activeCommentators.contains),
                  onChanged: (checked) {
                    final items = commentatorsList
                        .where((e) =>
                            !e.startsWith('__TITLE_') &&
                            !e.startsWith('__BUTTON_'))
                        .toList();
                    setState(() {
                      if (checked ?? false) {
                        widget.tab.activeCommentators.clear();
                        widget.tab.activeCommentators.addAll(items);
                      } else {
                        widget.tab.activeCommentators
                            .removeWhere(items.contains);
                      }
                    });
                    widget.onChanged();
                  },
                ),

              // רשימת המפרשים
              Expanded(
                child: ListView.builder(
                  itemCount: commentatorsList.length,
                  itemBuilder: (context, index) {
                    final item = commentatorsList[index];

                    // כפתורי קבוצות
                    if (item == _torahShebichtavButton) {
                      return _buildGroupButton(
                        'הצג את כל התורה שבכתב',
                        _torahShebichtav,
                      );
                    }
                    if (item == _chazalButton) {
                      return _buildGroupButton(
                        'הצג את כל חז"ל',
                        _chazal,
                      );
                    }
                    if (item == _rishonimButton) {
                      return _buildGroupButton(
                        'הצג את כל הראשונים',
                        _rishonim,
                      );
                    }
                    if (item == _acharonimButton) {
                      return _buildGroupButton(
                        'הצג את כל האחרונים',
                        _acharonim,
                      );
                    }
                    if (item == _modernButton) {
                      return _buildGroupButton(
                        'הצג את כל מחברי זמננו',
                        _modern,
                      );
                    }
                    if (item == _ungroupedButton) {
                      return _buildGroupButton(
                        'הצג את כל שאר המפרשים',
                        _ungrouped,
                      );
                    }

                    // כותרות
                    if (item.startsWith('__TITLE_')) {
                      String titleText = '';
                      switch (item) {
                        case _torahShebichtavTitle:
                          titleText = 'תורה שבכתב';
                          break;
                        case _chazalTitle:
                          titleText = 'חז"ל';
                          break;
                        case _rishonimTitle:
                          titleText = 'ראשונים';
                          break;
                        case _acharonimTitle:
                          titleText = 'אחרונים';
                          break;
                        case _modernTitle:
                          titleText = 'מחברי זמננו';
                          break;
                        case _ungroupedTitle:
                          titleText = 'שאר מפרשים';
                          break;
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 10.0, horizontal: 16.0),
                        child: Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8.0),
                              child: Text(
                                titleText,
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

                    // מפרש רגיל
                    return CheckboxListTile(
                      title: Text(item),
                      value: widget.tab.activeCommentators.contains(item),
                      onChanged: (checked) {
                        setState(() {
                          if (checked ?? false) {
                            if (!widget.tab.activeCommentators.contains(item)) {
                              widget.tab.activeCommentators.add(item);
                            }
                          } else {
                            widget.tab.activeCommentators.remove(item);
                          }
                        });
                        widget.onChanged();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildGroupButton(String title, List<String> group) {
    final allActive = group.every(widget.tab.activeCommentators.contains);
    return CheckboxListTile(
      title: Text(title),
      value: allActive,
      onChanged: (checked) {
        setState(() {
          if (checked ?? false) {
            for (final t in group) {
              if (!widget.tab.activeCommentators.contains(t)) {
                widget.tab.activeCommentators.add(t);
              }
            }
          } else {
            widget.tab.activeCommentators.removeWhere(group.contains);
          }
        });
        widget.onChanged();
      },
    );
  }
}
