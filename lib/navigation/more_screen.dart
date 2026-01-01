import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tools/measurement_converter/measurement_converter_screen.dart';
import 'package:otzaria/tools/gematria/gematria_search_screen.dart';
import 'package:otzaria/tools/aramaic_dictionary/aramaic_dictionary_screen.dart';
import 'package:shamor_zachor/shamor_zachor.dart';
import 'calendar_widget.dart';
import 'calendar_cubit.dart';
import 'package:otzaria/personal_notes/view/personal_notes_screen.dart';
import 'package:otzaria/settings/settings_repository.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> with TickerProviderStateMixin {
  late final TabController _tabController;
  late final CalendarCubit _calendarCubit;
  late final SettingsRepository _settingsRepository;
  final GlobalKey<GematriaSearchScreenState> _gematriaKey =
      GlobalKey<GematriaSearchScreenState>();
  late final List<Widget> _pages;

  final List<_TabInfo> _tabs = [
    const _TabInfo(
      label: 'לוח שנה',
      icon: Icons.calendar_month_outlined,
    ),
    const _TabInfo(
      label: 'זכור ושמור',
      icon: null,
      imageIcon: 'assets/icon/זכור ושמור.png',
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
      label: 'מילון ארמי',
      icon: FluentIcons.book_24_regular,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _settingsRepository = SettingsRepository();
    _calendarCubit = CalendarCubit(settingsRepository: _settingsRepository);
    
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
         setState(() {});
      }
    });

    // יצירת הדפים פעם אחת ב-initState
    _pages = [
      BlocProvider.value(
        value: _calendarCubit,
        child: const CalendarWidget(),
      ),
      ShamorZachorWidget(
        onTitleChanged: (_) {},
      ),
      const MeasurementConverterScreen(),
      const PersonalNotesManagerScreen(),
      GematriaSearchScreen(key: _gematriaKey),
      const AramaicDictionaryScreen(),
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
    _calendarCubit.close();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.center,
          tabs: _tabs.map((tab) {
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
          }).toList(),
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
