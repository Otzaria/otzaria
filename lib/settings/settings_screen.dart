import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/core/scaffold_messenger.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_event.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/settings/reading_settings_dialog.dart';
import 'package:otzaria/settings/library_settings_dialog.dart';
import 'package:otzaria/settings/calendar_settings_dialog.dart';
import 'package:otzaria/settings/gematria_settings_dialog.dart';
import 'package:otzaria/settings/backup_service.dart';
import 'package:otzaria/settings/settings_repository.dart';
import 'package:otzaria/widgets/shortcut_dropdown_tile.dart';
import 'package:otzaria/widgets/confirmation_dialog.dart';
import 'package:otzaria/settings/custom_folders/custom_folders_tile.dart';
import 'package:otzaria/widgets/dialogs.dart';
import 'package:otzaria/utils/fullscreen_helper.dart';
import 'package:otzaria/utils/shortcut_validator.dart';
import 'dart:async';

class MySettingsScreen extends StatefulWidget {
  const MySettingsScreen({
    super.key,
  });

  @override
  State<MySettingsScreen> createState() => _MySettingsScreenState();
}

class _MySettingsScreenState extends State<MySettingsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // מפתח לשמירת מיקום הגלילה בהגדרת מצב חיבור לרשת
  final GlobalKey _networkModeTileKey = GlobalKey();

  Widget _buildSettingsCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 160,
      height: 140,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 36,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildColumns(int maxColumns, List<Widget> children) {
    const double rowSpacing = 16.0;
    const double columnSpacing = 16.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int columns = (width / 300).floor();
        columns = math.min(math.max(columns, 1), maxColumns);

        if (columns <= 1) {
          return Column(children: children);
        }

        List<Widget> rows = [];
        for (int i = 0; i < children.length; i += columns) {
          List<Widget> rowChildren = [];

          for (int j = 0; j < columns; j++) {
            if (i + j < children.length) {
              rowChildren.add(Expanded(child: children[i + j]));

              if (j < columns - 1 && i + j + 1 < children.length) {
                rowChildren.add(const VerticalDivider(
                  width: columnSpacing,
                  thickness: 1,
                ));
              }
            }
          }

          // עוטפים את ה-Row ב-IntrinsicHeight כדי להבטיח גובה אחיד לקו המפריד
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch, // גורם לילדים להימתח
                children: rowChildren,
              ),
            ),
          );
        }

        return Wrap(
          runSpacing: rowSpacing,
          children: rows,
        );
      },
    );
  }

  /// בונה את הווידג'ט של מצב חיבור לרשת - מציג שתי אפשרויות (אונליין/אופליין)
  /// במקום מתג הפעלה/כיבוי, כך ששתי האפשרויות נראות כ"פעילות"
  Widget _buildNetworkModeTile(BuildContext context, SettingsState state) {
    final isOffline = state.isOfflineMode;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final cardColor = Theme.of(context).cardColor;

    return KeyedSubtree(
      key: _networkModeTileKey,
      child: _SettingsTile(
        leading: const Icon(FluentIcons.globe_24_regular),
        title: 'מצב חיבור לרשת',
        subtitle: isOffline
            ? 'התוכנה מנותקת לגמרי מהרשת, כל התכונות המקוונות מושבתות'
            : 'התוכנה יכולה להתחבר לרשת',
        trailing: SegmentedButton<bool>(
          segments: [
            ButtonSegment<bool>(
              value: false,
              label: const Text(
                'מקוון',
                style: TextStyle(fontSize: 14, letterSpacing: 0),
              ),
              icon: const Icon(FluentIcons.wifi_1_24_regular),
            ),
            ButtonSegment<bool>(
              value: true,
              label: const Text(
                'מנותק',
                style: TextStyle(fontSize: 14, letterSpacing: 0),
              ),
              icon: const Icon(FluentIcons.wifi_off_24_regular),
            ),
          ],
          selected: {isOffline},
          onSelectionChanged: (Set<bool> newSelection) {
            context
                .read<SettingsBloc>()
                .add(UpdateOfflineMode(newSelection.first));

            // גלילה לאלמנט הזה אחרי שהמסך מתעדכן
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (_networkModeTileKey.currentContext != null) {
                Scrollable.ensureVisible(
                  _networkModeTileKey.currentContext!,
                  duration: const Duration(milliseconds: 200),
                  alignment: 0.0,
                );
              }
            });
          },
          style: ButtonStyle(
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            backgroundColor: WidgetStateProperty.resolveWith<Color?>(
              (Set<WidgetState> states) {
                if (states.contains(WidgetState.selected)) {
                  return primaryColor.withValues(alpha: 0.2);
                }
                return cardColor;
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    const Map<String, String> shortcuctsList = {
      'ctrl+a': 'CTRL + A',
      'ctrl+b': "CTRL + B",
      'ctrl+c': "CTRL + C",
      'ctrl+d': "CTRL + D",
      'ctrl+e': "CTRL + E",
      'ctrl+f': "CTRL + F",
      'ctrl+g': "CTRL + G",
      'ctrl+h': "CTRL + H",
      'ctrl+i': "CTRL + I",
      'ctrl+j': "CTRL + J",
      'ctrl+k': "CTRL + K",
      'ctrl+l': "CTRL + L",
      'ctrl+m': "CTRL + M",
      'ctrl+n': "CTRL + N",
      'ctrl+o': "CTRL + O",
      'ctrl+p': "CTRL + P",
      'ctrl+q': "CTRL + Q",
      'ctrl+r': "CTRL + R",
      'ctrl+s': "CTRL + S",
      'ctrl+t': "CTRL + T",
      'ctrl+u': "CTRL + U",
      'ctrl+v': "CTRL + V",
      'ctrl+w': "CTRL + W",
      'ctrl+x': "CTRL + X",
      'ctrl+y': "CTRL + Y",
      'ctrl+z': "CTRL + Z",
      'ctrl+0': "CTRL + 0",
      'ctrl+1': "CTRL + 1",
      'ctrl+2': "CTRL + 2",
      'ctrl+3': "CTRL + 3",
      'ctrl+4': "CTRL + 4",
      'ctrl+5': "CTRL + 5",
      'ctrl+6': "CTRL + 6",
      'ctrl+7': "CTRL + 7",
      'ctrl+8': "CTRL + 8",
      'ctrl+9': "CTRL + 9",
      'ctrl+comma': "CTRL + ,",
      'ctrl+shift+b': "CTRL + SHIFT + B",
      'ctrl+shift+w': "CTRL + SHIFT + W",
    };

    return Scaffold(
      body: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, state) {
          return Theme(
            data: Theme.of(context).copyWith(
              appBarTheme: AppBarTheme(
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.15),
                centerTitle: true,
                titleTextStyle: TextStyle(
                  color: Theme.of(context).colorScheme.secondary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            child: Center(
              child: SettingsScreen(
                title: 'הגדרות',
                children: [
                  SettingsGroup(
                    titleAlignment: Alignment.centerRight,
                    title: 'הגדרות עיצוב',
                    titleTextStyle: const TextStyle(fontSize: 25),
                    children: <Widget>[
                      _buildColumns(3, [
                        if (!(Platform.isAndroid || Platform.isIOS))
                          BlocBuilder<SettingsBloc, SettingsState>(
                            builder: (context, settingsState) {
                              return SimpleSettingsTile(
                                title: 'מסך מלא',
                                subtitle: 'החלף מצב מסך מלא',
                                leading: Icon(settingsState.isFullscreen
                                    ? FluentIcons
                                        .full_screen_minimize_24_regular
                                    : FluentIcons
                                        .full_screen_maximize_24_regular),
                                onTap: () async {
                                  final newFullscreenState =
                                      !settingsState.isFullscreen;
                                  await FullscreenHelper.toggleFullscreen(
                                      context, newFullscreenState);
                                },
                              );
                            },
                          ),
                        SwitchSettingsTile(
                          settingKey: 'key-dark-mode',
                          title: 'מצב כהה',
                          enabledLabel: 'מופעל',
                          disabledLabel: 'לא מופעל',
                          leading:
                              const Icon(FluentIcons.weather_moon_24_regular),
                          onChange: (value) {
                            context
                                .read<SettingsBloc>()
                                .add(UpdateDarkMode(value));
                          },
                          activeColor: Theme.of(context).cardColor,
                        ),
                        ColorPickerSettingsTile(
                          key: ValueKey(
                              'color-picker-${state.isDarkMode ? 'dark' : 'light'}'),
                          title: 'צבע בסיס',
                          leading: const Icon(FluentIcons.color_24_regular),
                          settingKey: state.isDarkMode
                              ? 'key-dark-swatch-color'
                              : 'key-swatch-color',
                          onChange: (color) {
                            if (state.isDarkMode) {
                              context
                                  .read<SettingsBloc>()
                                  .add(UpdateDarkSeedColor(color));
                            } else {
                              context
                                  .read<SettingsBloc>()
                                  .add(UpdateSeedColor(color));
                            }
                          },
                        ),
                      ]),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Platform.isAndroid
                      ? const SizedBox.shrink()
                      : SettingsGroup(
                          titleAlignment: Alignment.centerRight,
                          title: "קיצורי מקשים",
                          titleTextStyle: const TextStyle(fontSize: 25),
                          children: [
                            SimpleSettingsTile(
                              title: 'איפוס קיצורי מקשים',
                              subtitle: 'החזר את כל קיצורי המקשים לברירת מחדל',
                              leading: const Icon(
                                  FluentIcons.arrow_reset_24_regular),
                              onTap: () async {
                                final confirmed = await showConfirmationDialog(
                                  context: context,
                                  title: 'איפוס קיצורי מקשים?',
                                  content:
                                      'כל קיצורי המקשים המותאמים אישית יאופסו לברירת המחדל. האם להמשיך?',
                                  isDangerous: true,
                                  barrierDismissible: false,
                                );

                                if (confirmed == true && context.mounted) {
                                  context
                                      .read<SettingsBloc>()
                                      .add(ResetShortcuts());

                                  UiSnack.show('קיצורי המקשים אופסו בהצלחה');
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8.0, right: 8.0),
                              child: Text(
                                'ניווט כללי',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            _buildColumns(3, [
                              ShortcutDropDownTile(
                                selected: 'ctrl+l',
                                settingKey: 'key-shortcut-open-library-browser',
                                title: 'ספרייה',
                                allShortcuts: shortcuctsList,
                                leading:
                                    const Icon(FluentIcons.library_24_regular),
                              ),
                              ShortcutDropDownTile(
                                selected: 'ctrl+o',
                                settingKey: 'key-shortcut-open-find-ref',
                                title: 'איתור',
                                allShortcuts: shortcuctsList,
                                leading: const Icon(
                                    FluentIcons.book_search_24_regular),
                              ),
                              ShortcutDropDownTile(
                                selected: 'ctrl+r',
                                settingKey: 'key-shortcut-open-reading-screen',
                                title: 'עיון',
                                leading: const Icon(
                                    FluentIcons.book_open_24_regular),
                                allShortcuts: shortcuctsList,
                              ),
                              ShortcutDropDownTile(
                                selected: 'ctrl+q',
                                settingKey: 'key-shortcut-open-new-search',
                                title: 'חלון חיפוש חדש',
                                leading:
                                    const Icon(FluentIcons.search_24_regular),
                                allShortcuts: shortcuctsList,
                              ),
                              ShortcutDropDownTile(
                                settingKey: 'key-shortcut-open-settings',
                                title: 'הגדרות',
                                allShortcuts: shortcuctsList,
                                selected: 'ctrl+comma',
                                leading:
                                    const Icon(FluentIcons.settings_24_regular),
                              ),
                              ShortcutDropDownTile(
                                settingKey: 'key-shortcut-open-more',
                                title: 'כלים',
                                allShortcuts: shortcuctsList,
                                selected: 'ctrl+m',
                                leading:
                                    const Icon(FluentIcons.apps_24_regular),
                              ),
                              ShortcutDropDownTile(
                                settingKey: 'key-shortcut-open-bookmarks',
                                title: 'סימניות',
                                allShortcuts: shortcuctsList,
                                selected: 'ctrl+shift+b',
                                leading:
                                    const Icon(FluentIcons.bookmark_24_regular),
                              ),
                              ShortcutDropDownTile(
                                settingKey: 'key-shortcut-open-history',
                                title: 'היסטוריה',
                                allShortcuts: shortcuctsList,
                                selected: 'ctrl+h',
                                leading:
                                    const Icon(FluentIcons.history_24_regular),
                              ),
                              ShortcutDropDownTile(
                                settingKey: 'key-shortcut-switch-workspace',
                                title: 'החלף שולחן עבודה',
                                allShortcuts: shortcuctsList,
                                selected: 'ctrl+k',
                                leading:
                                    const Icon(FluentIcons.grid_24_regular),
                              ),
                            ]),
                            const SizedBox(height: 16),
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8.0, right: 8.0),
                              child: Text(
                                'תצוגת ספר',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            _buildColumns(3, [
                              ShortcutDropDownTile(
                                settingKey: 'key-shortcut-search-in-book',
                                title: 'חיפוש בספר',
                                allShortcuts: shortcuctsList,
                                selected: 'ctrl+f',
                                leading:
                                    const Icon(FluentIcons.search_24_regular),
                              ),
                              ShortcutDropDownTile(
                                settingKey: 'key-shortcut-edit-section',
                                title: 'עריכת קטע',
                                allShortcuts: shortcuctsList,
                                selected: 'ctrl+e',
                                leading: const Icon(
                                    FluentIcons.document_edit_24_regular),
                              ),
                              ShortcutDropDownTile(
                                settingKey: 'key-shortcut-print',
                                title: 'הדפסה',
                                allShortcuts: shortcuctsList,
                                selected: 'ctrl+p',
                                leading:
                                    const Icon(FluentIcons.print_24_regular),
                              ),
                              ShortcutDropDownTile(
                                settingKey: 'key-shortcut-add-bookmark',
                                title: 'הוספת סימניה',
                                allShortcuts: shortcuctsList,
                                selected: 'ctrl+b',
                                leading:
                                    const Icon(FluentIcons.bookmark_24_regular),
                              ),
                              ShortcutDropDownTile(
                                settingKey: 'key-shortcut-add-note',
                                title: 'הוספת הערה',
                                allShortcuts: shortcuctsList,
                                selected: 'ctrl+n',
                                leading:
                                    const Icon(FluentIcons.note_24_regular),
                              ),
                              ShortcutDropDownTile(
                                settingKey: 'key-shortcut-toggle-pdf-view',
                                title: 'החלף מצב תצוגה',
                                allShortcuts: shortcuctsList,
                                selected: ShortcutValidator.defaultShortcuts[
                                    'key-shortcut-toggle-pdf-view']!,
                                leading: const Icon(
                                    FluentIcons.document_pdf_24_regular),
                              ),
                              ShortcutDropDownTile(
                                selected: 'ctrl+w',
                                settingKey: 'key-shortcut-close-tab',
                                title: 'סגור ספר נוכחי',
                                allShortcuts: shortcuctsList,
                                leading: const Icon(
                                    FluentIcons.dismiss_circle_24_regular),
                              ),
                              ShortcutDropDownTile(
                                selected: 'ctrl+shift+w',
                                settingKey: 'key-shortcut-close-all-tabs',
                                title: 'סגור כל הספרים',
                                allShortcuts: shortcuctsList,
                                leading:
                                    const Icon(FluentIcons.dismiss_24_regular),
                              ),
                            ]),
                          ],
                        ),
                  const SizedBox(height: 24),
                  SettingsGroup(
                    title: 'הגדרות ממשק',
                    titleAlignment: Alignment.centerRight,
                    titleTextStyle: const TextStyle(fontSize: 25),
                    children: [
                      SwitchSettingsTile(
                        settingKey: 'key-replace-holy-names',
                        title: 'הסתרת שמות הקודש',
                        enabledLabel: 'השמות הקדושים יוחלפו מפאת קדושתם',
                        disabledLabel: 'השמות הקדושים יוצגו ככתיבתם',
                        leading: const Icon(FluentIcons.eye_off_24_regular),
                        defaultValue: state.replaceHolyNames,
                        onChange: (value) {
                          context
                              .read<SettingsBloc>()
                              .add(UpdateReplaceHolyNames(value));
                        },
                        activeColor: Theme.of(context).cardColor,
                      ),
                      // קוביות הגדרות
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Wrap(
                          spacing: 12.0,
                          runSpacing: 12.0,
                          alignment: WrapAlignment.end,
                          children: [
                            _buildSettingsCard(
                              context: context,
                              title: 'הגדרות מסך ספרייה',
                              icon: FluentIcons.library_24_regular,
                              onTap: () => showLibrarySettingsDialog(context),
                            ),
                            _buildSettingsCard(
                              context: context,
                              title: 'הגדרות תצוגת הספרים',
                              icon: FluentIcons.book_24_regular,
                              onTap: () => showReadingSettingsDialog(context),
                            ),
                            _buildSettingsCard(
                              context: context,
                              title: 'הגדרות לוח שנה',
                              icon: Icons.calendar_month_outlined,
                              onTap: () => showCalendarSettingsDialog(context),
                            ),
                            // הגדרות זכור ושמור - מוסתר כרגע
                            // ignore: dead_code
                            if (false)
                              // ignore: dead_code
                              _buildSettingsCard(
                                context: context,
                                title: 'הגדרות זכור ושמור',
                                icon: FluentIcons.book_24_regular,
                                onTap: () {
                                  // יוסף בעתיד
                                },
                              ),
                            _buildSettingsCard(
                              context: context,
                              title: 'הגדרות גימטריות',
                              icon: FluentIcons.calculator_24_regular,
                              onTap: () => showGematriaSettingsDialog(context),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _BackupSettingsSection(),
                  const SizedBox(height: 24),
                  SettingsGroup(
                    title: 'כללי',
                    titleAlignment: Alignment.centerRight,
                    titleTextStyle: const TextStyle(fontSize: 25),
                    children: [
                      // הצגת ההגדרה רק אם מצב אופליין לא מופעל
                      if (!state.isOfflineMode)
                        SwitchSettingsTile(
                          title: 'סינכרון הספרייה באופן אוטומטי',
                          leading: Icon(FluentIcons.arrow_sync_24_regular),
                          settingKey: SettingsRepository.keyAutoSync,
                          defaultValue: true,
                          enabledLabel:
                              'מאגר הספרים המובנה יתעדכן אוטומטית מאתר אוצריא',
                          disabledLabel: 'מאגר הספרים לא יתעדכן אוטומטית.',
                          activeColor: Theme.of(context).cardColor,
                        ),
                      const SizedBox(height: 16),
                      _buildColumns(2, [
                        SwitchSettingsTile(
                          settingKey: 'key-use-fast-search',
                          title: 'חיפוש מהיר באמצעות אינדקס',
                          enabledLabel: 'חיפוש מהיר יותר, נדרש ליצור אינדקס',
                          disabledLabel: 'חיפוש איטי יותר, לא נדרש אינדקס',
                          leading: const Icon(FluentIcons.search_24_regular),
                          defaultValue: state.useFastSearch,
                          onChange: (value) {
                            context
                                .read<SettingsBloc>()
                                .add(UpdateUseFastSearch(value));
                          },
                          activeColor: Theme.of(context).cardColor,
                        ),
                        SwitchSettingsTile(
                          title: 'עדכון אינדקס אוטומטי',
                          leading: const Icon(
                              FluentIcons.arrow_clockwise_24_regular),
                          settingKey: 'key-auto-index-update',
                          defaultValue: state.autoUpdateIndex,
                          enabledLabel: 'אינדקס החיפוש יתעדכן אוטומטית',
                          disabledLabel: 'אינדקס החיפוש לא יתעדכן אוטומטית',
                          onChange: (value) async {
                            context
                                .read<SettingsBloc>()
                                .add(UpdateAutoUpdateIndex(value));
                          },
                          activeColor: Theme.of(context).cardColor,
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _buildColumns(2, [
                        BlocBuilder<IndexingBloc, IndexingState>(
                          builder: (context, indexingState) {
                            return SimpleSettingsTile(
                              title: "אינדקס חיפוש",
                              subtitle: indexingState is IndexingInProgress
                                  ? "התקדמות האינדקס: ${indexingState.booksProcessed}/${indexingState.totalBooks}"
                                  : indexingState is IndexingComplete
                                      ? "האינדקס מעודכן"
                                      : "האינדקס לא מעודכן",
                              leading: const Icon(FluentIcons.table_24_regular),
                              onTap: () async {
                                if (indexingState is IndexingInProgress) {
                                  final result = await showConfirmationDialog(
                                    context: context,
                                    title: 'עצירת עדכון',
                                    content:
                                        'האם לעצור את תהליך עדכון האינדקס?',
                                  );
                                  if (!context.mounted) return;
                                  if (result == true) {
                                    context
                                        .read<IndexingBloc>()
                                        .add(CancelIndexing());
                                    setState(() {});
                                  }
                                } else {
                                  // התחלת עדכון האינדקס ללא מחיקה
                                  final library =
                                      context.read<LibraryBloc>().state.library;
                                  if (library != null) {
                                    context
                                        .read<IndexingBloc>()
                                        .add(StartIndexing(library));
                                  }
                                }
                              },
                            );
                          },
                        ),
                        SimpleSettingsTile(
                          title: "איפוס אינדקס",
                          subtitle: "מחק את אינדקס החיפוש",
                          leading: const Icon(FluentIcons.delete_24_regular),
                          onTap: () async {
                            final result = await showConfirmationDialog(
                              context: context,
                              title: 'איפוס אינדקס',
                              content:
                                  'האם למחוק את אינדקס החיפוש? תצטרך לבנות אותו מחדש כדי להשתמש בחיפוש.',
                            );
                            if (!context.mounted) return;
                            if (result == true) {
                              // רק מחיקת האינדקס, ללא התחלה מחדש
                              context.read<IndexingBloc>().add(ClearIndex());
                            }
                          },
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _buildColumns(2, [
                        SimpleSettingsTile(
                          title: 'מיקום הספרייה',
                          subtitle: Settings.getValue<String>(
                                  SettingsRepository.keyLibraryPath) ??
                              'לא קיים',
                          leading: const Icon(FluentIcons.folder_24_regular),
                          onTap: () async {
                            String? path =
                                await FilePicker.platform.getDirectoryPath();
                            if (path != null) {
                              if (!context.mounted) return;
                              // עדכון מיקום הספרייה
                              context
                                  .read<LibraryBloc>()
                                  .add(UpdateLibraryPath(path));
                              // רענון מצב הניווט כדי לבדוק אם הספרייה ריקה
                              context
                                  .read<NavigationBloc>()
                                  .add(const CheckLibrary());
                            }
                          },
                        ),
                        Tooltip(
                          message: 'במידה וקיימים ברשותך ספרים ממאגר זה',
                          child: SimpleSettingsTile(
                            title: 'מיקום ספרי היברובוקס',
                            subtitle: Settings.getValue<String>(
                                    SettingsRepository.keyHebrewBooksPath) ??
                                'לא קיים',
                            leading: const Icon(FluentIcons.folder_24_regular),
                            onTap: () async {
                              String? path =
                                  await FilePicker.platform.getDirectoryPath();
                              if (path != null) {
                                if (!context.mounted) return;
                                // עדכון מיקום ספרי היברובוקס
                                context
                                    .read<LibraryBloc>()
                                    .add(UpdateHebrewBooksPath(path));
                                // רענון מצב הניווט
                                context
                                    .read<NavigationBloc>()
                                    .add(const CheckLibrary());
                              }
                            },
                          ),
                        ),
                      ]),
                      if (!(Platform.isAndroid || Platform.isIOS))
                        const CustomFoldersTile(),
                      if (!(Platform.isAndroid || Platform.isIOS))
                        // הצגת ההגדרה רק אם מצב אופליין לא מופעל
                        if (!state.isOfflineMode)
                          SwitchSettingsTile(
                            settingKey: 'key-dev-channel',
                            title: 'עדכון לגרסאות מפתחים',
                            enabledLabel:
                                'קבלת עדכונים על גרסאות בדיקה, ייתכנו באגים וחוסר יציבות',
                            disabledLabel: 'קבלת עדכונים על גרסאות יציבות בלבד',
                            leading: const Icon(FluentIcons.bug_24_regular),
                            activeColor: Theme.of(context).cardColor,
                          ),
                      // הגדרת מצב אופליין - תמיד מוצגת
                      _buildNetworkModeTile(context, state),
                      SimpleSettingsTile(
                        title: 'איפוס הגדרות',
                        subtitle:
                            'פעולה זו תמחק את כל ההגדרות ותחזיר את התוכנה למצב ההתחלתי',
                        leading: const Icon(FluentIcons.arrow_reset_24_regular),
                        onTap: () async {
                          // דיאלוג לאישור המשתמש
                          final confirmed = await showConfirmationDialog(
                            context: context,
                            title: 'איפוס הגדרות?',
                            content:
                                'כל ההגדרות האישיות שלך ימחקו. פעולה זו אינה הפיכה. האם להמשיך?',
                            isDangerous: true,
                          );

                          if (confirmed == true && context.mounted) {
                            Settings.clearCache();

                            // הודעה למשתמש שנדרשת הפעלה מחדש
                            await showDialog<void>(
                                context: context,
                                barrierDismissible: false,
                                builder: (context) => AlertDialog(
                                        title: const Text('ההגדרות אופסו'),
                                        content: const Text(
                                            'יש לסגור ולהפעיל מחדש את התוכנה כדי שהשינויים יכנסו לתוקף.'),
                                        actions: [
                                          TextButton(
                                              onPressed: () => exit(0),
                                              child:
                                                  const Text('סגור את התוכנה'))
                                        ]));
                          }
                        },
                      ),
                    ],
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Slider סימטרי עם תצוגה חיה לרוחב השוליים
class MarginSliderPreview extends StatefulWidget {
  final double initial;
  final double min;
  final double max;
  final int step;
  final ValueChanged<double> onChanged;

  const MarginSliderPreview({
    super.key,
    required this.initial,
    this.min = 0,
    this.max = 500,
    this.step = 2,
    required this.onChanged,
  });

  @override
  State<MarginSliderPreview> createState() => _MarginSliderPreviewState();
}

class _MarginSliderPreviewState extends State<MarginSliderPreview> {
  late double _margin;
  bool _showPreview = false;
  Timer? _disappearTimer;

  // משתנים לעיצוב כדי שיהיה קל לשנות
  final double thumbSize = 20.0; // גודל הידית
  final double trackHeight = 4.0; // גובה הפס
  final double widgetHeight = 50.0; // גובה כל הווידג'ט

  @override
  void initState() {
    super.initState();
    _margin = widget.initial.clamp(widget.min, widget.max / 2);
  }

  @override
  void dispose() {
    _disappearTimer?.cancel();
    super.dispose();
  }

  void _handleDragStart() {
    _disappearTimer?.cancel();
    setState(() => _showPreview = true);
  }

  void _handleDragEnd() {
    _disappearTimer?.cancel();
    _disappearTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showPreview = false);
    });
  }

  // פונקציה לבניית הידית כדי למנוע כפילות קוד
  Widget _buildThumb({required bool isLeft}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            double newMargin = isLeft
                ? _margin + details.delta.dx
                : _margin - details.delta.dx;

            // מגבילים את המרחב לפי רוחב הווידג'ט והגדרות המשתמש
            final maxWidth =
                (context.findRenderObject() as RenderBox).size.width;
            _margin = newMargin
                .clamp(widget.min, maxWidth / 2)
                .clamp(widget.min, widget.max);
          });
          widget.onChanged(_margin);
        },
        onPanStart: (_) => _handleDragStart(),
        onPanEnd: (_) => _handleDragEnd(),
        child: Container(
          width: thumbSize * 2, // אזור לחיצה גדול יותר מהנראות
          height: thumbSize * 2,
          color: Colors.transparent, // אזור הלחיצה שקוף
          alignment: Alignment.center,
          child: Container(
            // --- שינוי 1: עיצוב הידית מחדש ---
            width: thumbSize,
            height: thumbSize,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary, // צבע ראשי
              shape: BoxShape.circle,
              boxShadow: kElevationToShadow[1], // הצללה סטנדרטית של פלאטר
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fullWidth = constraints.maxWidth;
        final previewTextWidth =
            (fullWidth - 2 * _margin).clamp(0.0, fullWidth);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: widgetHeight,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTapDown: (details) {
                    final renderBox = context.findRenderObject() as RenderBox;
                    final localPosition =
                        renderBox.globalToLocal(details.globalPosition);
                    final tapX = localPosition.dx;

                    double newMargin;

                    double distanceFromCenter = (tapX - fullWidth / 2).abs();
                    newMargin = (fullWidth / 2) - distanceFromCenter;

                    newMargin = newMargin
                        .clamp(widget.min, widget.max)
                        .clamp(widget.min, fullWidth / 2);

                    setState(() {
                      _margin = newMargin;
                    });

                    widget.onChanged(_margin);
                    _handleDragStart();
                    _handleDragEnd();
                  },
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: thumbSize * 2,
                        color: Colors.transparent,
                      ),

                      // קו הרקע
                      Container(
                        height: trackHeight,
                        decoration: BoxDecoration(
                          color: Theme.of(context).dividerColor.withAlpha(128),
                          borderRadius: BorderRadius.circular(trackHeight / 2),
                        ),
                      ),

                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: _margin),
                        child: Container(
                          height: trackHeight,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius:
                                BorderRadius.circular(trackHeight / 2),
                          ),
                        ),
                      ),

                      if (_showPreview)
                        Positioned(
                          left: _margin - 10,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _margin.toStringAsFixed(0),
                              style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.onPrimary,
                                  fontSize: 12),
                            ),
                          ),
                        ),

                      if (_showPreview)
                        Positioned(
                          right: _margin - 10,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _margin.toStringAsFixed(0),
                              style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.onPrimary,
                                  fontSize: 12),
                            ),
                          ),
                        ),

                      // הכפתור השמאלי
                      Positioned(
                        left: _margin - (thumbSize),
                        child: _buildThumb(isLeft: true),
                      ),

                      // הכפתור הימני
                      Positioned(
                        right: _margin - (thumbSize),
                        child: _buildThumb(isLeft: false),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _showPreview ? 1.0 : 0.0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: _showPreview ? 60 : 0,
                curve: Curves.easeInOut,
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor.withAlpha(128),
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                padding: EdgeInsets.symmetric(horizontal: _margin),
                child: SizedBox(
                  width: previewTextWidth,
                  child: Text(
                    'מאימתי קורין את שמע בערבין משעה שהכהנים נכנסים לאכול בתרומתן עד סוף האשמורה הראשונה דברי רבי אליעזר וחכמים אומרים עד חצות רבן גמליאל אומר עד שיעלה עמוד השחר מעשה ובאו בניו מבית המשתה אמרו לו לא קרינו את שמע אמר להם אם לא עלה עמוד השחר חייבין אתם לקרות ולא זו בלבד אמרו אלא כל מה שאמרו חכמים עד חצות מצותן עד שיעלה עמוד השחר',
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    textDirection: TextDirection.rtl,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// ווידג'ט מותאם אישית שמחקה את הסגנון של flutter_settings_screens
class _SettingsTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const _SettingsTile({
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Column(
        children: [
          ListTile(
            leading: leading,
            title: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                letterSpacing: -0.1,
              ),
            ),
            subtitle: subtitle != null
                ? Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 13,
                          letterSpacing: -0.1,
                        ),
                  )
                : null,
            trailing: trailing,
          ),
          const Divider(height: 0),
        ],
      ),
    );
  }
}

/// מצבי גיבוי אפשריים
enum _BackupMode { all, custom }

/// ווידג'ט הגדרות גיבוי
class _BackupSettingsSection extends StatefulWidget {
  @override
  State<_BackupSettingsSection> createState() => _BackupSettingsSectionState();
}

class _BackupSettingsSectionState extends State<_BackupSettingsSection> {
  // מפתחות הגדרות גיבוי
  static const _keyBackupSettings = 'key-backup-settings';
  static const _keyBackupBookmarks = 'key-backup-bookmarks';
  static const _keyBackupHistory = 'key-backup-history';
  static const _keyBackupNotes = 'key-backup-notes';
  static const _keyBackupWorkspaces = 'key-backup-workspaces';
  static const _keyBackupShamorZachor = 'key-backup-shamor-zachor';
  static const _keyAutoBackupFrequency = 'key-auto-backup-frequency';

  _BackupMode _selectedBackupMode = _BackupMode.all;

  // פונקציית עזר לבדיקה האם לכלול סוג נתונים בגיבוי
  bool _shouldInclude(String key) {
    return _selectedBackupMode == _BackupMode.all ||
        (Settings.getValue<bool>(key) ?? true);
  }

  // פונקציה ליצירת גיבוי
  Future<void> _createBackup() async {
    final includeSettings = _shouldInclude(_keyBackupSettings);
    final includeBookmarks = _shouldInclude(_keyBackupBookmarks);
    final includeHistory = _shouldInclude(_keyBackupHistory);
    final includeNotes = _shouldInclude(_keyBackupNotes);
    final includeWorkspaces = _shouldInclude(_keyBackupWorkspaces);
    final includeShamorZachor = _shouldInclude(_keyBackupShamorZachor);

    try {
      final backupPath = await BackupService.createBackup(
        includeSettings: includeSettings,
        includeBookmarks: includeBookmarks,
        includeHistory: includeHistory,
        includeNotes: includeNotes,
        includeWorkspaces: includeWorkspaces,
        includeShamorZachor: includeShamorZachor,
      );

      final file = File(backupPath);
      final fileExists = await file.exists();
      final fileSize = fileExists ? await file.length() : 0;

      if (!mounted) return;

      if (fileExists) {
        UiSnack.showWithAction(
          message:
              'הגיבוי נשמר בהצלחה!\nנתיב: $backupPath\nגודל: ${(fileSize / 1024).toStringAsFixed(1)} KB',
          duration: const Duration(seconds: 5),
          actionLabel: 'פתח תיקייה',
          onAction: () async {
            final dir = Directory(file.parent.path);
            if (Platform.isWindows) {
              await Process.run('explorer', [dir.path]);
            } else if (Platform.isMacOS) {
              await Process.run('open', [dir.path]);
            } else if (Platform.isLinux) {
              await Process.run('xdg-open', [dir.path]);
            }
          },
        );
      } else {
        UiSnack.showWithDuration(
          'שגיאה: הקובץ לא נוצר בנתיב:\n$backupPath',
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 5),
        );
      }
    } catch (e, stackTrace) {
      if (!mounted) return;
      UiSnack.showWithDuration(
        'שגיאה ביצירת הגיבוי:\n$e\n\nStack trace:\n${stackTrace.toString().substring(0, math.min(stackTrace.toString().length, 200))}',
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 10),
      );
    }
  }

  // פונקציה לשחזור מגיבוי
  Future<void> _restoreBackup() async {
    String? filePath = await FilePicker.platform
        .pickFiles(
          type: FileType.custom,
          allowedExtensions: ['json'],
          dialogTitle: 'בחר קובץ גיבוי',
        )
        .then((result) => result?.files.single.path);

    if (filePath == null) return;

    if (!mounted) return;
    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'שחזור מגיבוי?',
      content: 'פעולה זו תחליף את הנתונים הקיימים בנתונים מהגיבוי. האם להמשיך?',
      isDangerous: true,
    );

    if (confirmed != true) return;

    try {
      await BackupService.restoreFromBackup(filePath);

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('השחזור הושלם'),
          content:
              const Text('הנתונים שוחזרו בהצלחה. יש להפעיל מחדש את התוכנה.'),
          actions: [
            TextButton(
              onPressed: () {
                if (Platform.isAndroid || Platform.isIOS) {
                  SystemNavigator.pop();
                } else if (Platform.isLinux ||
                    Platform.isMacOS ||
                    Platform.isWindows) {
                  windowManager.close();
                }
              },
              child: const Text('סגור את התוכנה'),
            ),
          ],
        ),
      );
    } catch (e, stackTrace) {
      if (!mounted) return;
      UiSnack.showWithDuration(
        'שגיאה בשחזור הגיבוי: $e\n\nStack trace: ${stackTrace.toString().substring(0, math.min(stackTrace.toString().length, 200))}',
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 10),
      );
    }
  }

  // בניית רשימת האפשרויות לבחירה מה לגבות
  Widget _buildBackupOptions() {
    return Column(
      children: [
        SwitchSettingsTile(
          settingKey: _keyBackupSettings,
          title: 'הגדרות',
          subtitle: 'כולל את כלל הגדרות התוכנה',
          leading: const Icon(FluentIcons.settings_24_regular),
          defaultValue: true,
          activeColor: Theme.of(context).cardColor,
        ),
        SwitchSettingsTile(
          settingKey: _keyBackupBookmarks,
          title: 'סימניות',
          subtitle: 'כל הסימניות שנשמרו',
          leading: const Icon(FluentIcons.bookmark_24_regular),
          defaultValue: true,
          activeColor: Theme.of(context).cardColor,
        ),
        SwitchSettingsTile(
          settingKey: _keyBackupHistory,
          title: 'היסטוריה',
          subtitle: 'היסטוריית הלימוד',
          leading: const Icon(FluentIcons.history_24_regular),
          defaultValue: true,
          activeColor: Theme.of(context).cardColor,
        ),
        SwitchSettingsTile(
          settingKey: _keyBackupNotes,
          title: 'הערות אישיות',
          subtitle: 'כל ההערות האישיות שלך',
          leading: const Icon(FluentIcons.note_24_regular),
          defaultValue: true,
          activeColor: Theme.of(context).cardColor,
        ),
        SwitchSettingsTile(
          settingKey: _keyBackupWorkspaces,
          title: 'שולחנות עבודה',
          subtitle: 'כל שולחנות העבודה',
          leading: const Icon(FluentIcons.grid_24_regular),
          defaultValue: true,
          activeColor: Theme.of(context).cardColor,
        ),
        SwitchSettingsTile(
          settingKey: _keyBackupShamorZachor,
          title: 'זכור ושמור',
          subtitle: 'ספרים ומעקב לימוד',
          leading: const Icon(FluentIcons.book_24_regular),
          defaultValue: true,
          activeColor: Theme.of(context).cardColor,
        ),
      ],
    );
  }

  // הפעולות המשותפות (גיבוי אוטומטי, צור גיבוי, שחזר)
  Widget _buildCommonActions() {
    final autoBackupFrequency =
        Settings.getValue<String>(_keyAutoBackupFrequency) ?? 'none';
    final primaryColor = Theme.of(context).colorScheme.primary;
    final cardColor = Theme.of(context).cardColor;

    return Column(
      children: [
        Column(
          children: [
            ListTile(
              leading: const Icon(FluentIcons.calendar_clock_24_regular),
              title: Text(
                'גיבוי אוטומטי',
                style: const TextStyle(
                  fontSize: 16,
                  letterSpacing: 0,
                ),
              ),
              trailing: SegmentedButton<String>(
                style: ButtonStyle(
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith<Color?>(
                    (Set<WidgetState> states) {
                      if (states.contains(WidgetState.selected)) {
                        return primaryColor.withValues(alpha: 0.2);
                      }
                      return cardColor;
                    },
                  ),
                ),
                segments: const [
                  ButtonSegment<String>(
                    value: 'none',
                    label: Text('ללא'),
                  ),
                  ButtonSegment<String>(
                    value: 'weekly',
                    label: Text('כל שבוע'),
                  ),
                  ButtonSegment<String>(
                    value: 'monthly',
                    label: Text('כל חודש'),
                  ),
                ],
                selected: {autoBackupFrequency},
                onSelectionChanged: (Set<String> newSelection) {
                  Settings.setValue<String>(
                      _keyAutoBackupFrequency, newSelection.first);
                  setState(() {});
                },
              ),
            ),
            const Divider(height: 0),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SimpleSettingsTile(
                title: 'צור גיבוי עכשיו',
                subtitle: 'שמור גיבוי של הנתונים שנבחרו',
                leading: const Icon(FluentIcons.arrow_upload_24_regular),
                onTap: _createBackup,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SimpleSettingsTile(
                title: 'שחזר מגיבוי',
                subtitle: 'בחר קובץ גיבוי לשחזור',
                leading: const Icon(FluentIcons.arrow_download_24_regular),
                onTap: _restoreBackup,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final cardColor = Theme.of(context).cardColor;

    return SettingsGroup(
      title: 'גיבוי',
      titleAlignment: Alignment.centerRight,
      titleTextStyle: const TextStyle(fontSize: 25),
      children: [
        _buildCommonActions(),
        const SizedBox(height: 16),
        Column(
          children: [
            ListTile(
              leading: const Icon(FluentIcons.options_24_regular),
              title: Text(
                'בחר מה לגבות',
                style: TextStyle(
                  fontSize: 16,
                  letterSpacing:
                      -0.1, // רווח בין אותיות - 0 = רגיל, שלילי = צפוף יותר
                ),
              ),
              trailing: SegmentedButton<_BackupMode>(
                style: ButtonStyle(
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith<Color?>(
                    (Set<WidgetState> states) {
                      if (states.contains(WidgetState.selected)) {
                        return primaryColor.withValues(alpha: 0.2);
                      }
                      return cardColor;
                    },
                  ),
                ),
                segments: const [
                  ButtonSegment<_BackupMode>(
                    value: _BackupMode.all,
                    label: Text('גבה הכל'),
                    icon: Icon(FluentIcons.checkmark_circle_24_regular),
                  ),
                  ButtonSegment<_BackupMode>(
                    value: _BackupMode.custom,
                    label: Text('מותאם אישית'),
                    icon: Icon(FluentIcons.options_24_regular),
                  ),
                ],
                selected: {_selectedBackupMode},
                onSelectionChanged: (Set<_BackupMode> newSelection) {
                  setState(() {
                    _selectedBackupMode = newSelection.first;
                  });
                },
              ),
            ),
            const Divider(height: 0),
          ],
        ),
        if (_selectedBackupMode == _BackupMode.custom) ...[
          Padding(
            padding: const EdgeInsets.only(left: 48, right: 48),
            child: _buildBackupOptions(),
          ),
        ],
      ],
    );
  }
}
