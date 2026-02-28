import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tools/measurement_converter/measurement_converter_screen.dart';
import 'package:otzaria/tools/gematria/gematria_search_screen.dart';
import 'package:otzaria/tools/dictionary/dictionary_screen.dart';
import 'package:otzaria/tools/shamor_zachor/shamor_zachor.dart';
import 'calendar_widget.dart';
import 'calendar_cubit.dart';
import 'package:otzaria/personal_notes/view/personal_notes_screen.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final TabController _tabController;
  final GlobalKey<GematriaSearchScreenState> _gematriaKey =
      GlobalKey<GematriaSearchScreenState>();
  late final List<Widget> _pages;
  late final List<Widget> _tabWidgets;

  final List<_TabInfo> _tabs = [
    const _TabInfo(
      label: 'לוח שנה',
      icon: Icons.calendar_month_outlined,
    ),
    const _TabInfo(
      label: 'שמור וזכור',
      icon: null,
      imageIcon: 'assets/icon/שמור וזכור שחור ריק.png',
    ),
    const _TabInfo(
      label: 'מדות ושיעורים',
      icon: Icons.straighten,
    ),
    const _TabInfo(
      label: 'הערות אישיות',
      icon: FluentIcons.note_24_regular,
    ),
    const _TabInfo(
      label: 'גימטריה',
      icon: FluentIcons.calculator_24_regular,
    ),
    const _TabInfo(
      label: 'מילון',
      icon: FluentIcons.book_24_regular,
    ),
  ];

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: _tabs.length, vsync: this);

    _tabWidgets = _tabs.map((tab) {
      if (tab.imageIcon != null) {
        return SizedBox(
          width: 100,
          child: Tab(
            text: tab.label,
            icon: ImageIcon(AssetImage(tab.imageIcon!), size: 20),
          ),
        );
      }
      return SizedBox(
        width: 100,
        child: Tab(
          text: tab.label,
          icon: Icon(tab.icon, size: 20),
        ),
      );
    }).toList();

    // יצירת הדפים פעם אחת ב-initState
    _pages = [
      BlocBuilder<CalendarCubit, CalendarState>(
        builder: (context, _) => const CalendarWidget(),
      ),
      ShamorZachorWidget(
        onTitleChanged: (_) {},
      ),
      const MeasurementConverterScreen(),
      const PersonalNotesManagerScreen(),
      GematriaSearchScreen(key: _gematriaKey),
      const DictionaryScreen(),
    ];
  }

  /// Reset to calendar page - public method for external access
  void resetToCalendar() {
    if (_tabController.index != 0) {
      _tabController.animateTo(0);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.center,
          tabs: _tabWidgets,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: Theme.of(context).dividerColor,
            height: 1.0,
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _pages,
      ),
    );
  }
}

class _TabInfo {
  final String label;
  final IconData? icon;
  final String? imageIcon;

  const _TabInfo({
    required this.label,
    this.icon,
    this.imageIcon,
  });
}
