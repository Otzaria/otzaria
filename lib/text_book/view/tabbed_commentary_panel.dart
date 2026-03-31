import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/view/selected_line_links_view.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_sidebar.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/text_book/view/commentators_list_screen.dart';
import 'package:otzaria/text_book/widgets/text_book_state_builder.dart';

/// Widget שמציג כרטיסיות עם מפרשים וקישורים בחלונית הצד
class TabbedCommentaryPanel extends StatefulWidget {
  final Function(OpenedTab) openBookCallback;
  final double fontSize;
  final bool showSearch;
  final VoidCallback? onClosePane;
  final int? initialTabIndex;
  final Function(int)? onTabChanged;
  final bool showSplitView;

  const TabbedCommentaryPanel({
    super.key,
    required this.openBookCallback,
    required this.fontSize,
    required this.showSearch,
    this.onClosePane,
    this.initialTabIndex,
    this.onTabChanged,
    this.showSplitView = true,
  });

  @override
  State<TabbedCommentaryPanel> createState() => _TabbedCommentaryPanelState();
}

class _TabbedCommentaryPanelState extends State<TabbedCommentaryPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  void switchToLinksTab() {
    if (_tabController.index != 1) {
      _tabController.animateTo(1);
    }
  }

  @override
  void initState() {
    super.initState();
    final validInitialIndex = (widget.initialTabIndex ?? 0).clamp(0, 2);
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: validInitialIndex,
    );

    _tabController.addListener(() {
      if (!_tabController.indexIsChanging &&
          _tabController.index >= 0 &&
          _tabController.index < 3) {
        widget.onTabChanged?.call(_tabController.index);
      }
    });
  }

  @override
  void didUpdateWidget(TabbedCommentaryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTabIndex != null &&
        widget.initialTabIndex != oldWidget.initialTabIndex) {
      final validIndex = widget.initialTabIndex!.clamp(0, 2);
      if (_tabController.index != validIndex) {
        _tabController.animateTo(validIndex);
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildAnimatedTab(
    int index,
    IconData regular,
    IconData filled,
    String label,
  ) {
    final isSelected = _tabController.index == index;
    return Tab(
      height: 48,
      iconMargin: const EdgeInsets.only(bottom: 2),
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeInOutCubicEmphasized,
        switchOutCurve: Curves.easeInOutCubicEmphasized,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: animation, child: child),
        ),
        child: Icon(
          isSelected ? filled : regular,
          key: ValueKey<bool>(isSelected),
          size: 18,
        ),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextBookStateBuilder(
      builder: (context, state) {
        return Container(
          color: cs.surfaceContainerLow,
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    Expanded(
                      child: AnimatedBuilder(
                        animation: _tabController,
                        builder: (context, _) => TabBar(
                          controller: _tabController,
                          tabs: [
                            _buildAnimatedTab(
                              0,
                              widget.showSplitView
                                  ? FluentIcons.book_24_regular
                                  : FluentIcons.settings_24_regular,
                              widget.showSplitView
                                  ? FluentIcons.book_24_filled
                                  : FluentIcons.settings_24_filled,
                              widget.showSplitView
                                  ? 'מפרשים'
                                  : 'סינון מפרשים',
                            ),
                            _buildAnimatedTab(
                              1,
                              FluentIcons.link_24_regular,
                              FluentIcons.link_24_filled,
                              'קישורים',
                            ),
                            _buildAnimatedTab(
                              2,
                              FluentIcons.note_24_regular,
                              FluentIcons.note_24_filled,
                              'הערות',
                            ),
                          ],
                          unselectedLabelColor:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                          dividerColor: Colors.transparent,
                          dividerHeight: 0,
                          overlayColor:
                              WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.hovered)) {
                              return Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.08);
                            }
                            if (states.contains(WidgetState.pressed)) {
                              return Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.12);
                            }
                            return null;
                          }),
                          splashBorderRadius:
                              BorderRadius.circular(AppTokens.radiusMD),
                        ),
                      ),
                    ),
                    IconButton(
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      icon: const Icon(FluentIcons.dismiss_24_regular),
                      onPressed: widget.onClosePane,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildFirstTabContent(context, state),
                    SelectedLineLinksView(
                      openBookCallback: widget.openBookCallback,
                      fontSize: widget.fontSize,
                      showVisibleLinksIfNoSelection: widget.initialTabIndex == 1,
                    ),
                    PersonalNotesSidebar(
                      bookId: state.book.title,
                      onNavigateToLine: (line) =>
                          _handleNoteNavigation(context, state, line),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFirstTabContent(
    BuildContext context,
    TextBookLoaded state,
  ) {
    if (widget.showSplitView) {
      return CommentaryListBase(
        key: const ValueKey('commentary_list_tabbed'),
        openBookCallback: widget.openBookCallback,
        fontSize: widget.fontSize,
        showSearch: widget.showSearch,
        selectedCommentatorsOverride: state.activeCommentators,
        onSelectedCommentatorsOverrideChanged: (commentators) {
          context.read<TextBookBloc>().add(UpdateCommentators(commentators));
        },
      );
    }

    return const CommentatorsListView(
      key: ValueKey('commentators_settings_tabbed'),
    );
  }

  Future<void> _handleNoteNavigation(
    BuildContext context,
    TextBookLoaded state,
    int lineNumber,
  ) async {
    if (lineNumber < 1 || state.content.isEmpty) {
      return;
    }

    final targetIndex = (lineNumber - 1).clamp(0, state.content.length - 1);

    await state.scrollController.scrollTo(
      index: targetIndex,
      alignment: 0.05,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );

    if (!mounted) {
      return;
    }
    if (!context.mounted) {
      return;
    }

    final bloc = context.read<TextBookBloc>();
    bloc.add(UpdateSelectedIndex(targetIndex));
    bloc.add(HighlightLine(targetIndex));
  }
}
