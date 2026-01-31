import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/advanced_search_controls.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';

/// פאנל עריכת חיפוש - מופיע מתחת לשורת "מוצגות תוצאות של..."
/// מאפשר עריכת החיפוש הנוכחי ללא יצירת כרטיסייה חדשה
class SearchEditPanel extends StatelessWidget {
  final SearchingTab tab;
  final VoidCallback onClose;

  const SearchEditPanel({
    super.key,
    required this.tab,
    required this.onClose,
  });

  void _performSearch(BuildContext context) {
    final query = tab.queryController.text.trim();

    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('נא להזין טקסט לחיפוש'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    tab.searchBloc.add(
      UpdateSearchQuery(
        query,
        customSpacing: tab.spacingValues,
        alternativeWords: tab.alternativeWords,
        searchOptions: tab.searchOptions,
      ),
    );

    onClose();
  }

  Widget _buildSearchModeToggle(SearchState state) {
    final modes = [
      {'label': 'מתקדם', 'mode': SearchMode.advanced},
      {'label': 'מדוייק', 'mode': SearchMode.exact},
      {'label': 'מקורב', 'mode': SearchMode.fuzzy},
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: modes.map((modeData) {
        final isSelected = state.configuration.searchMode == modeData['mode'];
        return Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: ChoiceChip(
            label: Text(modeData['label'] as String),
            selected: isSelected,
            onSelected: (selected) {
              if (selected) {
                tab.searchBloc
                    .add(SetSearchMode(modeData['mode'] as SearchMode));
              }
            },
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchBloc, SearchState>(
      builder: (context, state) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // שורה עליונה: מצב חיפוש + מרווח כללי
              Row(
                children: [
                  Text(
                    'מצב חיפוש:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 16),
                  _buildSearchModeToggle(state),
                  const SizedBox(width: 32),
                  if (tab.spacingValues.isEmpty && !state.fuzzy) ...[
                    Text(
                      'מרווח כללי בין מילים:',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 80,
                      child: RtlTextField(
                        decoration: const InputDecoration(
                          hintText: '0-30',
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          isDense: true,
                        ),
                        controller: TextEditingController(
                          text: state.distance.toString(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^([0-9]|[12][0-9]|30)$'),
                          ),
                        ],
                        textAlign: TextAlign.center,
                        onChanged: (value) {
                          final distance = int.tryParse(value);
                          if (distance != null &&
                              distance >= 0 &&
                              distance <= 30) {
                            tab.searchBloc.add(UpdateDistance(distance));
                          }
                        },
                      ),
                    ),
                  ],
                  const Spacer(),
                ],
              ),

              const SizedBox(height: 16),

              // שורה שנייה: שדה חיפוש + כפתורים
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: RtlTextField(
                      controller: tab.queryController,
                      focusNode: tab.searchFieldFocusNode,
                      decoration: InputDecoration(
                        hintText: 'הזן טקסט לחיפוש...',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(FluentIcons.dismiss_24_regular),
                          onPressed: () {
                            tab.queryController.clear();
                          },
                        ),
                      ),
                      textAlign: TextAlign.right,
                      onSubmitted: (_) => _performSearch(context),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: () => _performSearch(context),
                    icon: const Icon(FluentIcons.search_24_regular),
                    label: const Text('חפש'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(FluentIcons.dismiss_24_regular),
                    onPressed: onClose,
                    tooltip: 'סגור',
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),

              if (state.configuration.searchMode == SearchMode.advanced)
                AdvancedSearchControls(
                  tab: tab,
                  compactMode: false,
                  onEmptySubmit: () => _performSearch(context),
                )
              else
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Text(
                      'אפשרויות מתקדמות זמינות רק במצב "חיפוש מתקדם"',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
