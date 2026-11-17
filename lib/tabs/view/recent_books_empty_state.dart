import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/utils/bookmark_from_tab.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/history/view/history_screen.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/utils/ui/book_format_icon.dart';
import 'package:otzaria/utils/ui/reading_left_pane_policy.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/dialog_teardown.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';
import 'package:otzaria/widgets/layout/app_card.dart';
import 'package:otzaria/widgets/text/app_section_label.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// הספרים האחרונים לפי זהות הספר ולא לפי מספר המקומות ששמורים בהיסטוריה.
List<Bookmark> recentReadingBooks(List<Bookmark> history, {int limit = 4}) {
  final result = <Bookmark>[];
  final seen = <String>{};
  if (limit <= 0) return result;
  for (final item in history) {
    if (item.isSearch || (item.book is! TextBook && item.book is! PdfBook)) {
      continue;
    }
    if (!seen.add(bookIdentity(item.book))) continue;
    result.add(item);
    if (result.length == limit) break;
  }
  return result;
}

/// הצעות מצומצמות במסך עיון ריק, מתוך ההיסטוריה השמורה (לא רק טאבים שנסגרו).
class RecentBooksEmptyState extends StatelessWidget {
  const RecentBooksEmptyState({super.key, this.onFindRefRequested});

  final VoidCallback? onFindRefRequested;

  void _openBook(BuildContext context, Bookmark bookmark) {
    final tab = tabFromBookmark(
      bookmark,
      screenWidth: readingLayoutWidthOf(context),
    );
    context.read<TabsBloc>().add(
      OpenOrFocusTab(
        tab,
        targetTitle: bookmark.ref,
        matchHistorySlot: bookmark.targetKind == BookmarkTargetKind.book,
      ),
    );
    context.read<NavigationBloc>().add(const NavigateToScreen(Screen.reading));
  }

  @override
  Widget build(BuildContext context) {
    final maxBooks = WindowClass.isShortOf(context)
        ? 2
        : switch (WindowClass.of(context)) {
            WindowClass.compact => 2,
            WindowClass.medium => 3,
            WindowClass.expanded || WindowClass.large => 4,
          };

    return BlocBuilder<HistoryBloc, HistoryState>(
      builder: (context, state) {
        final recent = state is HistoryLoaded
            ? recentReadingBooks(state.history, limit: maxBooks)
            : <Bookmark>[];

        return OtzariaEmptyState(
          icon: OtzariaIcons.otzaria_icon_2_page_24_regular,
          title: 'לא נבחרו ספרים',
          message: 'פתחו ספר מהספרייה או מהאיתור כדי להתחיל בקריאה',
          body: recent.isEmpty
              ? null
              : ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: LayoutConstraints.mainContentMinWidth,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AppSectionLabel('נפתחו לאחרונה'),
                      const SizedBox(height: AppTokens.spaceSM),
                      for (final bookmark in recent) ...[
                        AppCard(
                          onTap: () => _openBook(context, bookmark),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTokens.spaceSMD,
                            vertical: AppTokens.spaceSM,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                bookFormatIcon(bookmark.book),
                                size: AppTokens.iconMD,
                              ),
                              const SizedBox(width: AppTokens.spaceSM),
                              Expanded(
                                child: Text(
                                  bookmark.book.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppTokens.spaceXS),
                      ],
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: ActionButton.inline(
                          text: 'היסטוריה מלאה',
                          onPressed: () => showDialogUntilTornDown<void>(
                            context: context,
                            builder: (_) => const HistoryDialog(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          actions: [
            ActionButton.recommended(
              text: 'דפדף בספרייה',
              icon: FluentIcons.library_24_regular,
              onPressed: () => context.read<NavigationBloc>().add(
                const NavigateToScreen(Screen.library),
              ),
            ),
            ActionButton.neutral(
              text: 'איתור ספר',
              icon: FluentIcons.search_24_regular,
              onPressed: onFindRefRequested,
            ),
          ],
        );
      },
    );
  }
}
