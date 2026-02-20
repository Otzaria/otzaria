import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:math' as math;
import 'package:path/path.dart' as p;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_event.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/widgets/confirmation_dialog.dart';
import 'package:otzaria/widgets/shortcut_dropdown_tile.dart';
import 'package:otzaria/settings/protected_mode_settings.dart';
import 'package:otzaria/settings/protected_settings_wrapper.dart';
import 'package:otzaria/core/app_paths.dart';

/// טאב הגדרות מתקדמות
class AdvancedSettingsTab extends StatefulWidget {
  const AdvancedSettingsTab({super.key});

  @override
  State<AdvancedSettingsTab> createState() => _AdvancedSettingsTabState();
}

class _AdvancedSettingsTabState extends State<AdvancedSettingsTab> {
  final GlobalKey _networkModeTileKey = GlobalKey();

  static const Map<String, String> shortcutsList = {
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

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // קיצורי מקשים (רק בדסקטופ)
              if (!(Platform.isAndroid || Platform.isIOS)) ...[
                _buildShortcutsSection(context),
                const SizedBox(height: 16),
              ],

              // חיפוש ואינדקס
              _buildSearchSection(context, state),
              const SizedBox(height: 16),

              // סינכרון ורשת
              _buildNetworkSection(context, state),
              const SizedBox(height: 16),

              // איפוס
              _buildResetSection(context),
              const SizedBox(height: 16),

              // מצב מוגן
              const ProtectedModeSettings(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShortcutsSection(BuildContext context) {
    return _buildSectionCard(
      context: context,
      title: 'קיצורי מקשים',
      children: [
        ListTile(
          leading: const Icon(FluentIcons.arrow_reset_24_regular),
          title:
              const Text('איפוס קיצורי מקשים', style: TextStyle(fontSize: 16)),
          subtitle: const Text('החזר את כל קיצורי המקשים לברירת מחדל',
              style: TextStyle(fontSize: 13)),
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
              context.read<SettingsBloc>().add(ResetShortcuts());
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('קיצורי המקשים אופסו בהצלחה',
                      textDirection: TextDirection.rtl),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
        ),
        const Divider(height: 1),
        ExpansionTile(
          leading: const Icon(FluentIcons.navigation_24_regular),
          title: const Text('ניווט כללי', style: TextStyle(fontSize: 16)),
          initiallyExpanded: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: _buildColumns(3, [
                _buildShortcutTile('key-shortcut-open-library-browser',
                    'ספרייה', 'ctrl+l', FluentIcons.library_24_regular),
                _buildShortcutTile('key-shortcut-open-find-ref', 'איתור',
                    'ctrl+o', FluentIcons.book_search_24_regular),
                _buildShortcutTile('key-shortcut-open-reading-screen', 'עיון',
                    'ctrl+r', FluentIcons.book_open_24_regular),
                _buildShortcutTile('key-shortcut-open-new-search',
                    'חלון חיפוש חדש', 'ctrl+q', FluentIcons.search_24_regular),
                _buildShortcutTile('key-shortcut-open-settings', 'הגדרות',
                    'ctrl+comma', FluentIcons.settings_24_regular),
                _buildShortcutTile('key-shortcut-open-more', 'כלים', 'ctrl+m',
                    FluentIcons.apps_24_regular),
                _buildShortcutTile('key-shortcut-open-bookmarks', 'סימניות',
                    'ctrl+shift+b', FluentIcons.bookmark_24_regular),
                _buildShortcutTile('key-shortcut-open-history', 'היסטוריה',
                    'ctrl+h', FluentIcons.history_24_regular),
                _buildShortcutTile('key-shortcut-switch-workspace',
                    'החלף שולחן עבודה', 'ctrl+k', FluentIcons.grid_24_regular),
              ]),
            ),
          ],
        ),
        ExpansionTile(
          leading: const Icon(FluentIcons.book_24_regular),
          title: const Text('תצוגת ספר', style: TextStyle(fontSize: 16)),
          initiallyExpanded: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: _buildColumns(3, [
                _buildShortcutTile('key-shortcut-search-in-book', 'חיפוש בספר',
                    'ctrl+f', FluentIcons.search_24_regular),
                _buildShortcutTile('key-shortcut-edit-section', 'עריכת קטע',
                    'ctrl+e', FluentIcons.document_edit_24_regular),
                _buildShortcutTile('key-shortcut-print', 'הדפסה', 'ctrl+p',
                    FluentIcons.print_24_regular),
                _buildShortcutTile('key-shortcut-add-bookmark', 'הוסף סימניה',
                    'ctrl+b', FluentIcons.bookmark_24_regular),
                _buildShortcutTile('key-shortcut-add-note', 'הוספת הערה',
                    'ctrl+n', FluentIcons.note_24_regular),
                _buildShortcutTile('key-shortcut-close-tab', 'סגור ספר נוכחי',
                    'ctrl+w', FluentIcons.dismiss_circle_24_regular),
                _buildShortcutTile(
                    'key-shortcut-close-all-tabs',
                    'סגור כל הספרים',
                    'ctrl+shift+w',
                    FluentIcons.dismiss_24_regular),
              ]),
            ),
          ],
        ),
      ],
    );
  }

  /// בונה פריסת עמודות דינמית לפי רוחב המסך
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

          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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

  Widget _buildShortcutTile(
      String settingKey, String title, String defaultValue, IconData icon) {
    return ShortcutDropDownTile(
      settingKey: settingKey,
      title: title,
      selected: defaultValue,
      allShortcuts: shortcutsList,
      leading: Icon(icon),
    );
  }

  Widget _buildSearchSection(BuildContext context, SettingsState state) {
    return _buildSectionCard(
      context: context,
      title: 'חיפוש ואינדקס',
      children: [
        SwitchListTile(
          secondary: const Icon(FluentIcons.search_24_regular),
          title: const Text('חיפוש מהיר באמצעות אינדקס',
              style: TextStyle(fontSize: 16)),
          subtitle: Text(
              state.useFastSearch
                  ? 'חיפוש מהיר יותר, נדרש ליצור אינדקס'
                  : 'חיפוש איטי יותר, לא נדרש אינדקס',
              style: const TextStyle(fontSize: 13)),
          value: state.useFastSearch,
          onChanged: (value) {
            context.read<SettingsBloc>().add(UpdateUseFastSearch(value));
          },
        ),
        const Divider(height: 1),
        SwitchListTile(
          secondary: const Icon(FluentIcons.arrow_clockwise_24_regular),
          title: const Text('עדכון אינדקס אוטומטי',
              style: TextStyle(fontSize: 16)),
          subtitle: Text(
              state.autoUpdateIndex
                  ? 'אינדקס החיפוש יתעדכן אוטומטית'
                  : 'אינדקס החיפוש לא יתעדכן אוטומטית',
              style: const TextStyle(fontSize: 13)),
          value: state.autoUpdateIndex,
          onChanged: (value) {
            context.read<SettingsBloc>().add(UpdateAutoUpdateIndex(value));
          },
        ),
        const Divider(height: 1),
        BlocBuilder<IndexingBloc, IndexingState>(
          builder: (context, indexingState) {
            return ListTile(
              leading: const Icon(FluentIcons.table_24_regular),
              title: const Text('אינדקס חיפוש', style: TextStyle(fontSize: 16)),
              subtitle: Text(
                  indexingState is IndexingInProgress
                      ? 'התקדמות האינדקס: ${indexingState.booksProcessed}/${indexingState.totalBooks}'
                      : indexingState is IndexingComplete
                          ? 'האינדקס מעודכן'
                          : 'האינדקס לא מעודכן',
                  style: const TextStyle(fontSize: 13)),
              trailing: indexingState is IndexingInProgress
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(FluentIcons.chevron_left_24_regular),
              onTap: () async {
                if (indexingState is IndexingInProgress) {
                  final result = await showConfirmationDialog(
                    context: context,
                    title: 'עצירת עדכון',
                    content: 'האם לעצור את תהליך עדכון האינדקס?',
                  );
                  if (!context.mounted) return;
                  if (result == true) {
                    context.read<IndexingBloc>().add(CancelIndexing());
                  }
                } else {
                  final library = context.read<LibraryBloc>().state.library;
                  if (library != null) {
                    context.read<IndexingBloc>().add(StartIndexing(library));
                  }
                }
              },
            );
          },
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(FluentIcons.delete_24_regular),
          title: const Text('איפוס אינדקס', style: TextStyle(fontSize: 16)),
          subtitle: const Text('מחק את אינדקס החיפוש',
              style: TextStyle(fontSize: 13)),
          onTap: () async {
            final result = await showConfirmationDialog(
              context: context,
              title: 'איפוס אינדקס',
              content:
                  'האם למחוק את אינדקס החיפוש? תצטרך לבנות אותו מחדש כדי להשתמש בחיפוש.',
            );
            if (!context.mounted) return;
            if (result == true) {
              context.read<IndexingBloc>().add(ClearIndex());
            }
          },
        ),
      ],
    );
  }

  Widget _buildNetworkSection(BuildContext context, SettingsState state) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final cardColor = Theme.of(context).cardColor;

    return _buildSectionCard(
      context: context,
      title: 'סינכרון ורשת',
      children: [
        // TEMPORARILY DISABLED - Sync settings hidden
        // if (!state.isOfflineMode)
        //   SwitchListTile(
        //     secondary: const Icon(FluentIcons.arrow_sync_24_regular),
        //     title: const Text('סינכרון הספרייה באופן אוטומטי',
        //         style: TextStyle(fontSize: 16)),
        //     subtitle: Text(
        //         Settings.getValue<bool>(SettingsRepository.keyAutoSync) ?? true
        //             ? 'מאגר הספרים המובנה יתעדכן אוטומטית מאתר אוצריא'
        //             : 'מאגר הספרים לא יתעדכן אוטומטית',
        //         style: const TextStyle(fontSize: 13)),
        //     value:
        //         Settings.getValue<bool>(SettingsRepository.keyAutoSync) ?? true,
        //     onChanged: (value) {
        //       Settings.setValue<bool>(SettingsRepository.keyAutoSync, value);
        //       setState(() {});
        //     },
        //   ),
        // if (!state.isOfflineMode) const Divider(height: 1),
        if (!(Platform.isAndroid || Platform.isIOS) && !state.isOfflineMode)
          SwitchListTile(
            secondary: const Icon(FluentIcons.bug_24_regular),
            title: const Text('עדכון לגרסאות מפתחים',
                style: TextStyle(fontSize: 16)),
            subtitle: Text(
                Settings.getValue<bool>('key-dev-channel') ?? false
                    ? 'קבלת עדכונים על גרסאות בדיקה, ייתכנו באגים וחוסר יציבות'
                    : 'קבלת עדכונים על גרסאות יציבות בלבד',
                style: const TextStyle(fontSize: 13)),
            value: Settings.getValue<bool>('key-dev-channel') ?? false,
            onChanged: (value) {
              Settings.setValue<bool>('key-dev-channel', value);
              setState(() {});
            },
          ),
        if (!(Platform.isAndroid || Platform.isIOS) && !state.isOfflineMode)
          const Divider(height: 1),
        KeyedSubtree(
          key: _networkModeTileKey,
          child: ListTile(
            leading: const Icon(FluentIcons.globe_24_regular),
            title: const Text('מצב חיבור לרשת', style: TextStyle(fontSize: 16)),
            subtitle: Text(
                state.isOfflineMode
                    ? 'התוכנה מנותקת לגמרי מהרשת, כל התכונות המקוונות מושבתות'
                    : 'התוכנה יכולה להתחבר לרשת',
                style: const TextStyle(fontSize: 13)),
            trailing: SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  label: Text('מקוון', style: TextStyle(fontSize: 14)),
                  icon: Icon(FluentIcons.wifi_1_24_regular),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text('מנותק', style: TextStyle(fontSize: 14)),
                  icon: Icon(FluentIcons.wifi_off_24_regular),
                ),
              ],
              selected: {state.isOfflineMode},
              onSelectionChanged: (newSelection) {
                context
                    .read<SettingsBloc>()
                    .add(UpdateOfflineMode(newSelection.first));
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
                      borderRadius: BorderRadius.circular(8)),
                ),
                backgroundColor: WidgetStateProperty.resolveWith<Color?>(
                  (states) {
                    if (states.contains(WidgetState.selected)) {
                      return primaryColor.withValues(alpha: 0.2);
                    }
                    return cardColor;
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResetSection(BuildContext context) {
    return _buildSectionCard(
      context: context,
      title: 'איפוס',
      children: [
        ListTile(
          leading: const Icon(FluentIcons.arrow_reset_24_regular),
          title: const Text('איפוס הגדרות', style: TextStyle(fontSize: 16)),
          subtitle: const Text(
              'פעולה זו תמחק את כל ההגדרות ותחזיר את התוכנה למצב ההתחלתי',
              style: TextStyle(fontSize: 13)),
          onTap: () async {
            // בדיקה אם במצב מוגן - אם כן, דרוש אימות סיסמה
            if (shouldProtectSettings(context)) {
              final verified = await verifyPasswordForAction(context);
              if (!verified || !context.mounted) {
                return;
              }
            }

            if (!context.mounted) return;

            final confirmed = await showConfirmationDialog(
              context: context,
              title: 'איפוס הגדרות?',
              content:
                  'כל ההגדרות האישיות שלך ימחקו. פעולה זו אינה הפיכה. האם להמשיך?',
              isDangerous: true,
            );

            if (confirmed == true && context.mounted) {
              Settings.clearCache();
              await showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (context) => AlertDialog(
                  title: const Text('ההגדרות אופסו'),
                  content: const Text(
                      'יש לסגור ולהפעיל מחדש את התוכנה כדי שהשינויים יכנסו לתוקף.'),
                  actions: [
                    TextButton(
                      onPressed: () {
                        if (Platform.isAndroid || Platform.isIOS) {
                          SystemNavigator.pop();
                        } else {
                          windowManager.close();
                        }
                      },
                      child: const Text('סגור את התוכנה'),
                    ),
                  ],
                ),
              );
            }
          },
        ),
        ListTile(
          leading: const Icon(FluentIcons.delete_24_regular),
          title: const Text('הסרת התוכנה', style: TextStyle(fontSize: 16)),
          subtitle: const Text(
              'מחיקת כל ההגדרות ותיקיית ההתקנה. ניתן לבחור האם למחוק גם את הספרייה',
              style: TextStyle(fontSize: 13)),
          onTap: () => _uninstallApp(context),
        ),
      ],
    );
  }

  /// הסרת התוכנה - מחיקת הגדרות ותיקיית התקנה
  Future<void> _uninstallApp(BuildContext context) async {
    // בדיקה אם במצב מוגן - אם כן, דרוש אימות סיסמה
    if (shouldProtectSettings(context)) {
      final verified = await verifyPasswordForAction(context);
      if (!verified || !context.mounted) {
        return;
      }
    }

    if (!context.mounted) return;

    // אישור ראשוני
    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'הסרת התוכנה?',
      content:
          'פעולה זו תמחק את כל ההגדרות ואת תיקיית ההתקנה של התוכנה. פעולה זו אינה הפיכה!\n\nהאם להמשיך?',
      isDangerous: true,
    );

    if (confirmed != true || !context.mounted) return;

    // שאלה לגבי מחיקת הספרייה
    final deleteLibrary = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('מחיקת הספרייה?'),
        content: const Text(
          'האם למחוק גם את ספריית הספרים?\n\n'
          'אם תבחר "כן", כל הספרים שהורדת יימחקו.\n'
          'אם תבחר "לא", הספרייה תישאר במחשב.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('לא, השאר את הספרייה'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('כן, מחק את הספרייה'),
          ),
        ],
      ),
    );

    if (!context.mounted) return;

    try {
      // מחיקת ההגדרות
      Settings.clearCache();

      // קבלת נתיבי התיקיות
      final appSupportDir = await getApplicationSupportDirectory();
      final libraryPath = await AppPaths.getLibraryPath();

      // בדיקה אם הספרייה נמצאת בתוך תיקיית ההתקנה
      final isLibraryInAppSupport = libraryPath.startsWith(appSupportDir.path);

      // יצירת סקריפט מחיקה שירוץ אחרי סגירת התוכנה
      final scriptPath = await _createUninstallScript(
        appSupportDir.path,
        deleteLibrary == true
            ? null
            : (isLibraryInAppSupport ? libraryPath : null),
        !isLibraryInAppSupport && deleteLibrary == true ? libraryPath : null,
      );

      if (!context.mounted) return;

      // הודעה על הצלחה והפעלת הסקריפט
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('התוכנה תוסר'),
          content: Text(
            deleteLibrary == true
                ? 'כל ההגדרות, תיקיית ההתקנה והספרייה יימחקו לאחר סגירת התוכנה.'
                : 'כל ההגדרות ותיקיית ההתקנה יימחקו לאחר סגירת התוכנה. הספרייה תישמר.',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                // הפעלת הסקריפט
                if (Platform.isWindows) {
                  await Process.start('cmd', ['/c', 'start', '', scriptPath],
                      mode: ProcessStartMode.detached);
                } else if (Platform.isLinux || Platform.isMacOS) {
                  await Process.start('sh', [scriptPath],
                      mode: ProcessStartMode.detached);
                }

                // סגירת התוכנה
                if (Platform.isAndroid || Platform.isIOS) {
                  SystemNavigator.pop();
                } else {
                  windowManager.close();
                }
              },
              child: const Text('סגור והסר'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('שגיאה'),
          content: Text('אירעה שגיאה בהכנת הסרת התוכנה: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('סגור'),
            ),
          ],
        ),
      );
    }
  }

  /// יצירת סקריפט מחיקה שירוץ אחרי סגירת התוכנה
  Future<String> _createUninstallScript(
    String appSupportPath,
    String? libraryToPreserve,
    String? libraryToDelete,
  ) async {
    final tempDir =
        await Directory.systemTemp.createTemp('otzaria_uninstall_');

    if (Platform.isWindows) {
      final scriptPath = p.join(tempDir.path, 'uninstall.bat');
      final script = StringBuffer();

      script.writeln('@echo off');
      script.writeln('chcp 65001 > nul');
      script.writeln('timeout /t 2 /nobreak > nul');

      // שמירת הספרייה אם נדרש
      if (libraryToPreserve != null) {
        final tempLibrary = p.join(tempDir.path, 'library_backup');
        script.writeln('echo Backing up library...');
        script.writeln('xcopy /E /I /Y /Q "$libraryToPreserve" "$tempLibrary"');
      }

      // מחיקת תיקיית ההתקנה
      script.writeln('echo Removing application data...');
      script.writeln('if exist "$appSupportPath" (');
      script.writeln('  rmdir /S /Q "$appSupportPath"');
      script.writeln(')');

      // החזרת הספרייה אם נדרש
      if (libraryToPreserve != null) {
        final tempLibrary = p.join(tempDir.path, 'library_backup');
        script.writeln('echo Restoring library...');
        script.writeln('if exist "$tempLibrary" (');
        script.writeln('  xcopy /E /I /Y /Q "$tempLibrary" "$libraryToPreserve"');
        script.writeln(')');
      }

      // מחיקת ספרייה חיצונית אם נדרש
      if (libraryToDelete != null) {
        script.writeln('echo Removing library...');
        script.writeln('if exist "$libraryToDelete" (');
        script.writeln('  rmdir /S /Q "$libraryToDelete"');
        script.writeln(')');
      }

      script.writeln('echo Uninstall complete!');
      script.writeln('timeout /t 3 /nobreak > nul');
      
      // מחיקת התיקייה הזמנית
      script.writeln('if exist "${tempDir.path}" (');
      script.writeln('  rmdir /S /Q "${tempDir.path}"');
      script.writeln(')');

      await File(scriptPath).writeAsString(script.toString());
      return scriptPath;
    } else {
      final scriptPath = p.join(tempDir.path, 'uninstall.sh');
      final script = StringBuffer();

      script.writeln('#!/bin/bash');
      script.writeln('sleep 2');

      // שמירת הספרייה אם נדרש
      if (libraryToPreserve != null) {
        final tempLibrary = p.join(tempDir.path, 'library_backup');
        script.writeln('echo "Backing up library..."');
        script.writeln('if [ -d "$libraryToPreserve" ]; then');
        script.writeln('  cp -r "$libraryToPreserve" "$tempLibrary"');
        script.writeln('fi');
      }

      // מחיקת תיקיית ההתקנה
      script.writeln('echo "Removing application data..."');
      script.writeln('if [ -d "$appSupportPath" ]; then');
      script.writeln('  rm -rf "$appSupportPath"');
      script.writeln('fi');

      // החזרת הספרייה אם נדרש
      if (libraryToPreserve != null) {
        final tempLibrary = p.join(tempDir.path, 'library_backup');
        script.writeln('echo "Restoring library..."');
        script.writeln('if [ -d "$tempLibrary" ]; then');
        script.writeln('  mkdir -p "$libraryToPreserve"');
        script.writeln('  cp -r "$tempLibrary"/* "$libraryToPreserve/"');
        script.writeln('fi');
      }

      // מחיקת ספרייה חיצונית אם נדרש
      if (libraryToDelete != null) {
        script.writeln('echo "Removing library..."');
        script.writeln('if [ -d "$libraryToDelete" ]; then');
        script.writeln('  rm -rf "$libraryToDelete"');
        script.writeln('fi');
      }

      script.writeln('echo "Uninstall complete!"');
      script.writeln('sleep 3');
      
      // מחיקת התיקייה הזמנית
      script.writeln('if [ -d "${tempDir.path}" ]; then');
      script.writeln('  rm -rf "${tempDir.path}"');
      script.writeln('fi');

      final file = File(scriptPath);
      await file.writeAsString(script.toString());
      await Process.run('chmod', ['+x', scriptPath]);
      return scriptPath;
    }
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}
