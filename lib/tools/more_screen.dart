// lib/tools/more_screen.dart

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tools/measurement_converter/measurement_converter_screen.dart';
import 'package:otzaria/tools/gematria/gematria_search_screen.dart';
import 'package:otzaria/tools/aramaic_dictionary/aramaic_dictionary_screen.dart';
import 'package:otzaria/tools/acronyms_dictionary/acronyms_dictionary_screen.dart';
import 'package:otzaria/tools/shamor_zachor/shamor_zachor.dart';
import 'package:otzaria/tools/calendar/ulits/calendar_widget.dart';
import 'package:otzaria/tools/calendar/ulits/calendar_cubit.dart';
import 'package:otzaria/personal_notes/view/personal_notes_screen.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  MoreScreenState createState() => MoreScreenState();
}

/// מצב מסך "עוד".
///
/// אחראי על מעבר בין לשוניות הכלים ועל החזרת פוקוס יזומה ללוח השנה
/// כאשר חוזרים אליו ממסך אחר או מלשונית אחרת.
class MoreScreenState extends State<MoreScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static const int _calendarFocusRetryCount = 6;
  late final TabController _tabController;
  final GlobalKey<CalendarWidgetState> _calendarKey =
      GlobalKey<CalendarWidgetState>();
  final GlobalKey<GematriaSearchScreenState> _gematriaKey =
      GlobalKey<GematriaSearchScreenState>();
  late final List<Widget> _pages;
  late final List<Widget> _tabWidgets;

  void _requestCalendarFocus({int remainingAttempts = _calendarFocusRetryCount}) {
    if (!mounted) {
      return;
    }

    final calendarState = _calendarKey.currentState;
    if (calendarState != null) {
      calendarState.requestKeyboardFocus();
      return;
    }

    if (remainingAttempts <= 0) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      Future<void>.delayed(const Duration(milliseconds: 50), () {
        if (mounted) {
          _requestCalendarFocus(remainingAttempts: remainingAttempts - 1);
        }
      });
    });
  }

  /// מבקש פוקוס ללשונית הפעילה אם היא לוח השנה.
  ///
  /// המתודה מנסה שוב לזמן קצר אם לוח השנה עדיין לא חובר לעץ בזמן
  /// הקריאה, למשל בזמן אנימציית מעבר בין מסכים.
  void requestActiveTabFocus() {
    if (_tabController.index == 0) {
      _requestCalendarFocus();
    }
  }

  void _handleTabChange() {
    if (_tabController.index == 0) {
      _requestCalendarFocus();
    }
  }

  final List<_TabInfo> _tabs = [
    const _TabInfo(
      label: 'לוח שנה',
      icon: FluentIcons.calendar_24_regular,
    ),
    const _TabInfo(
      label: 'שמור וזכור',
      icon: null,
      imageIcon: 'assets/icon/שמור וזכור שחור ריק.png',
    ),
    const _TabInfo(
      label: 'מדות ושיעורים',
      icon: FluentIcons.ruler_24_regular,
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
      label: 'מילון ארמי-עברי',
      icon: FluentIcons.translate_24_regular,
    ),
    const _TabInfo(
      label: 'ראשי תיבות',
      icon: FluentIcons.text_quote_24_regular,
    ),
  ];

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_handleTabChange);

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

    _pages = [
      BlocBuilder<CalendarCubit, CalendarState>(
        builder: (context, _) => CalendarWidget(key: _calendarKey),
      ),
      ShamorZachorWidget(
        onTitleChanged: (_) {},
      ),
      const MeasurementConverterScreen(),
      const PersonalNotesManagerScreen(),
      GematriaSearchScreen(key: _gematriaKey),
      const AramaicDictionaryScreen(),
      const AcronymsDictionaryScreen(),
    ];
  }

  /// מחזיר את מסך "עוד" ללשונית לוח השנה.
  ///
  /// אם לשונית לוח השנה כבר פעילה, מתבצעת בקשת פוקוס מחודשת כדי
  /// לאפשר ניווט מיידי עם מקשי החיצים.
  void resetToCalendar() {
    if (_tabController.index != 0) {
      _tabController.animateTo(0);
      return;
    }

    _requestCalendarFocus();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isMoreScreenActive =
        context.select((NavigationBloc bloc) => bloc.state.currentScreen) ==
            Screen.more;

    if (isMoreScreenActive && _tabController.index == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          requestActiveTabFocus();
        }
      });
    }

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
