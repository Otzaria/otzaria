import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tools/measurement_converter/measurement_converter_screen.dart';
import 'package:otzaria/tools/gematria/gematria_search_screen.dart';
import 'package:otzaria/tools/aramaic_dictionary/aramaic_dictionary_screen.dart';
import 'package:otzaria/settings/calendar_settings_dialog.dart';
import 'package:otzaria/settings/gematria_settings_dialog.dart';
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
  int _selectedIndex = 0;
  late final CalendarCubit _calendarCubit;
  late final SettingsRepository _settingsRepository;
  final GlobalKey<GematriaSearchScreenState> _gematriaKey =
      GlobalKey<GematriaSearchScreenState>();
  late final List<Widget> _pages;

  // Title for the ShamorZachor section (dynamic from the package)
  String _shamorZachorTitle = 'זכור ושמור';

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

    // יצירת הדפים פעם אחת ב-initState
    _pages = [
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
      const AramaicDictionaryScreen(),
    ];
  }

  /// Reset to calendar page - public method for external access
  void resetToCalendar() {
    if (_selectedIndex != 0) {
      setState(() {
        _selectedIndex = 0;
      });
    }
  }

  Widget _buildCenteredLabel(String text) {
    return SizedBox(
      width: 74,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

  @override
  void dispose() {
    _calendarCubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 700;

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
      body: isSmallScreen
          ? IndexedStack(
              index: _selectedIndex,
              children: _pages,
            )
          : Row(
              children: [
                SizedBox(
                  width: 74,
                  child: NavigationRail(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (int index) {
                      setState(() {
                        _selectedIndex = index;
                      });
                    },
                    labelType: NavigationRailLabelType.all,
                    minWidth: 74,
                    destinations: [
                      NavigationRailDestination(
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: _buildCenteredLabel('לוח שנה'),
                      ),
                      NavigationRailDestination(
                        icon: const ImageIcon(
                            AssetImage('assets/icon/זכור ושמור.png')),
                        label: _buildCenteredLabel('זכור ושמור'),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.straighten),
                        label: _buildCenteredLabel('מדות ושיעורים'),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(FluentIcons.note_24_regular),
                        label: _buildCenteredLabel('הערות אישיות'),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(FluentIcons.calculator_24_regular),
                        label: _buildCenteredLabel('גימטריות'),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(FluentIcons.book_24_regular),
                        label: _buildCenteredLabel('מילון ארמי'),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: _pages,
                  ),
                ),
              ],
            ),
      bottomNavigationBar: isSmallScreen
          ? BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: (int index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              type: BottomNavigationBarType.fixed,
              selectedFontSize: 11,
              unselectedFontSize: 10,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.calendar_month_outlined, size: 20),
                  label: 'לוח שנה',
                ),
                BottomNavigationBarItem(
                  icon: ImageIcon(AssetImage('assets/icon/זכור ושמור.png'),
                      size: 20),
                  label: 'זכור ושמור',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.straighten, size: 20),
                  label: 'מדות',
                ),
                BottomNavigationBarItem(
                  icon: Icon(FluentIcons.note_24_regular, size: 20),
                  label: 'הערות',
                ),
                BottomNavigationBarItem(
                  icon: Icon(FluentIcons.calculator_24_regular, size: 20),
                  label: 'גימטריה',
                ),
                BottomNavigationBarItem(
                  icon: Icon(FluentIcons.book_24_regular, size: 20),
                  label: 'מילון',
                ),
              ],
            )
          : null,
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
      case 5:
        return 'מילון ארמי-עברי';
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
        return [
          buildSettingsButton(() => showCalendarSettingsDialog(
                context,
                calendarCubit: context.read<CalendarCubit>(),
              ))
        ];
      case 4:
        return [buildSettingsButton(() => showGematriaSettingsDialog(context))];
      default:
        return null;
    }
  }
}
