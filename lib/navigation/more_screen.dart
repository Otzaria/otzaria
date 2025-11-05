import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tools/measurement_converter/measurement_converter_screen.dart';
import 'package:otzaria/tools/gematria/gematria_search_screen.dart';
import 'package:otzaria/settings/settings_repository.dart';
import 'package:otzaria/settings/calendar_settings_dialog.dart';
import 'package:otzaria/settings/gematria_settings_dialog.dart';
import 'package:shamor_zachor/shamor_zachor.dart';
import 'calendar_widget.dart';
import 'calendar_cubit.dart';
import 'package:otzaria/personal_notes/view/personal_notes_screen.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  late final CalendarCubit _calendarCubit;
  late final SettingsRepository _settingsRepository;
  final GlobalKey<GematriaSearchScreenState> _gematriaKey =
      GlobalKey<GematriaSearchScreenState>();
  late final PageController _pageController;

  // Title for the ShamorZachor section (dynamic from the package)
  String _shamorZachorTitle = 'שמור וזכור';

  /// Update the ShamorZachor title
  void _updateShamorZachorTitle(String title) {
    setState(() {
      _shamorZachorTitle = title;
    });
  }

  @override
  void initState() {
    super.initState();
    _settingsRepository = SettingsRepository();
    _calendarCubit = CalendarCubit(settingsRepository: _settingsRepository);
    _pageController = PageController(initialPage: 0);
  }

  /// Reset to calendar page - public method for external access
  void resetToCalendar() {
    if (_selectedIndex != 0) {
      setState(() {
        _selectedIndex = 0;
      });
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    }
  }



  @override
  void dispose() {
    _calendarCubit.close();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
        title: Text(
          _getTitle(_selectedIndex),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: _getActions(context, _selectedIndex),
      ),
      body: OrientationBuilder(
        builder: (context, orientation) {
          return Row(
            children: [
              NavigationRail(
                selectedIndex: _selectedIndex,
                onDestinationSelected: (int index) {
                  setState(() {
                    _selectedIndex = index;
                  });
                  if (_pageController.hasClients) {
                    _pageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  }
                },
                labelType: NavigationRailLabelType.all,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.calendar_month_outlined),
                    label: Text('לוח שנה'),
                  ),
                  NavigationRailDestination(
                    icon: ImageIcon(AssetImage('assets/icon/שמור וזכור.png')),
                    label: Text('שמור וזכור'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(FluentIcons.ruler_24_regular),
                    label: Text('מדות ושיעורים'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(FluentIcons.note_24_regular),
                    label: Text('הערות אישיות'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(FluentIcons.calculator_24_regular),
                    label: Text('גימטריות'),
                  ),
                ],
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(
                child: PageView(
                  scrollDirection: orientation == Orientation.landscape
                      ? Axis.vertical
                      : Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _selectedIndex = index;
                    });
                  },
                  children: [
                    BlocProvider.value(
                      value: _calendarCubit,
                      child: const CalendarWidget(),
                    ),
                    ShamorZachorWidget(
                      onTitleChanged: _updateShamorZachorTitle,
                    ),
                    const MeasurementConverterScreen(),
                    const PersonalNotesManagerScreen(),
                    GematriaSearchScreen(key: _gematriaKey),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _getTitle(int index) {
    switch (index) {
      case 0:
        return 'לוח שנה';
      case 1:
        return _shamorZachorTitle;
      case 2:
        return 'מדות ושיעורים';
      case 3:
        return 'הערות אישיות';
      case 4:
        return 'גימטריה';
      default:
        return 'כלים';
    }
  }

  List<Widget>? _getActions(BuildContext context, int index) {
    Widget buildSettingsButton(VoidCallback onPressed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: IconButton(
          icon: const Icon(FluentIcons.settings_24_regular),
          tooltip: 'הגדרות',
          onPressed: onPressed,
          style: IconButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    switch (index) {
      case 0:
        return [buildSettingsButton(() => showCalendarSettingsDialog(context))];
      case 4:
        return [buildSettingsButton(() => showGematriaSettingsDialog(context))];
      default:
        return null;
    }
  }


}
