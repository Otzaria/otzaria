// lib/favourites/favourites_screen.dart
// שינויים:
//  • AnimatedSwitcher לאנימציית מעבר בין אייקון regular ל-filled בטאבים
//  • שימוש באייקונים עבים (filled) למצב נבחר
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/history/history_screen.dart';
import 'package:otzaria/bookmarks/bookmark_screen.dart';
import 'package:otzaria/theme/theme_exports.dart';

class FavouritesScreen extends StatefulWidget {
  const FavouritesScreen({super.key});

  @override
  State<FavouritesScreen> createState() => _FavouritesScreenState();
}

class _FavouritesScreenState extends State<FavouritesScreen>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildAnimatedIcon(int index, IconData regular, IconData filled) {
    final isSelected = _tabController.index == index;
    return AnimatedSwitcher(
      duration: AppTokens.animNormal,
      switchInCurve: Curves.easeInOutCubicEmphasized,
      switchOutCurve: Curves.easeInOutCubicEmphasized,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: Icon(
        isSelected ? filled : regular,
        key: ValueKey<bool>(isSelected),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: TabBar(
        controller: _tabController,
        tabs: [
          Tab(
            text: 'סימניות',
            icon: _buildAnimatedIcon(
              0,
              FluentIcons.bookmark_24_regular,
              FluentIcons.bookmark_24_filled,
            ),
          ),
          Tab(
            text: 'היסטוריה',
            icon: _buildAnimatedIcon(
              1,
              FluentIcons.history_24_regular,
              FluentIcons.history_24_regular,
            ),
          ),
        ],
        splashBorderRadius: BorderRadius.circular(AppTokens.radiusMD),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          BookmarkView(),
          HistoryView(),
        ],
      ),
    );
  }
}
