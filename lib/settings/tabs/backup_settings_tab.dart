import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:math' as math;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import 'package:otzaria/settings/backup_service.dart';
import 'package:otzaria/widgets/confirmation_dialog.dart';
import 'package:otzaria/settings/settings_card.dart';

/// טאב הגדרות גיבוי
class BackupSettingsTab extends StatefulWidget {
  const BackupSettingsTab({super.key});

  @override
  State<BackupSettingsTab> createState() => _BackupSettingsTabState();
}

class _BackupSettingsTabState extends State<BackupSettingsTab> {
  static const _keyBackupSettings = 'key-backup-settings';
  static const _keyBackupBookmarks = 'key-backup-bookmarks';
  static const _keyBackupHistory = 'key-backup-history';
  static const _keyBackupNotes = 'key-backup-notes';
  static const _keyBackupWorkspaces = 'key-backup-workspaces';
  static const _keyBackupShamorZachor = 'key-backup-shamor-zachor';
  static const _keyAutoBackupFrequency = 'key-auto-backup-frequency';

  _BackupMode _selectedBackupMode = _BackupMode.all;

  bool _shouldInclude(String key) {
    return _selectedBackupMode == _BackupMode.all ||
        (Settings.getValue<bool>(key) ?? true);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'הגיבוי נשמר בהצלחה!\nנתיב: $backupPath\nגודל: ${(fileSize / 1024).toStringAsFixed(1)} KB'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'פתח תיקייה',
              onPressed: () async {
                final dir = Directory(file.parent.path);
                if (Platform.isWindows) {
                  await Process.run('explorer', [dir.path]);
                } else if (Platform.isMacOS) {
                  await Process.run('open', [dir.path]);
                } else if (Platform.isLinux) {
                  await Process.run('xdg-open', [dir.path]);
                }
              },
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה: הקובץ לא נוצר בנתיב:\n$backupPath'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e, stackTrace) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'שגיאה ביצירת הגיבוי:\n$e\n\nStack trace:\n${stackTrace.toString().substring(0, math.min(stackTrace.toString().length, 200))}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 10),
        ),
      );
    }
  }

  Future<void> _restoreBackup() async {
    String? filePath = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    ).then((result) => result?.files.single.path);

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'שגיאה בשחזור הגיבוי: $e\n\nStack trace: ${stackTrace.toString().substring(0, math.min(stackTrace.toString().length, 200))}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 10),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final cardColor = Theme.of(context).cardColor;
    final autoBackupFrequency =
        Settings.getValue<String>(_keyAutoBackupFrequency) ?? 'none';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // פעולות גיבוי
          SettingsCard(
            title: 'פעולות גיבוי',
            children: [
              ListTile(
                leading: const Icon(FluentIcons.calendar_clock_24_regular),
                title:
                    const Text('גיבוי אוטומטי', style: TextStyle(fontSize: 16)),
                trailing: SegmentedButton<String>(
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
                  segments: const [
                    ButtonSegment<String>(value: 'none', label: Text('ללא')),
                    ButtonSegment<String>(
                        value: 'weekly', label: Text('כל שבוע')),
                    ButtonSegment<String>(
                        value: 'monthly', label: Text('כל חודש')),
                  ],
                  selected: {autoBackupFrequency},
                  onSelectionChanged: (newSelection) {
                    Settings.setValue<String>(
                        _keyAutoBackupFrequency, newSelection.first);
                    setState(() {});
                  },
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _createBackup,
                        icon: const Icon(FluentIcons.arrow_upload_24_regular),
                        label: const Text('צור גיבוי עכשיו'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _restoreBackup,
                        icon: const Icon(FluentIcons.arrow_download_24_regular),
                        label: const Text('שחזר מגיבוי'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // בחירת מה לגבות
          SettingsCard(
            title: 'בחר מה לגבות',
            children: [
              ListTile(
                leading: const Icon(FluentIcons.options_24_regular),
                title: const Text('מצב גיבוי', style: TextStyle(fontSize: 16)),
                trailing: SegmentedButton<_BackupMode>(
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
                  onSelectionChanged: (newSelection) {
                    setState(() {
                      _selectedBackupMode = newSelection.first;
                    });
                  },
                ),
              ),
              if (_selectedBackupMode == _BackupMode.custom) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildColumns(3, [
                    _buildBackupOption(
                      icon: FluentIcons.settings_24_regular,
                      title: 'הגדרות',
                      subtitle: 'כולל את כלל הגדרות התוכנה',
                      settingKey: _keyBackupSettings,
                    ),
                    _buildBackupOption(
                      icon: FluentIcons.bookmark_24_regular,
                      title: 'סימניות',
                      subtitle: 'כל הסימניות שנשמרו',
                      settingKey: _keyBackupBookmarks,
                    ),
                    _buildBackupOption(
                      icon: FluentIcons.history_24_regular,
                      title: 'היסטוריה',
                      subtitle: 'היסטוריית הלימוד',
                      settingKey: _keyBackupHistory,
                    ),
                    _buildBackupOption(
                      icon: FluentIcons.note_24_regular,
                      title: 'הערות אישיות',
                      subtitle: 'כל ההערות האישיות שלך',
                      settingKey: _keyBackupNotes,
                    ),
                    _buildBackupOption(
                      icon: FluentIcons.grid_24_regular,
                      title: 'שולחנות עבודה',
                      subtitle: 'כל שולחנות העבודה',
                      settingKey: _keyBackupWorkspaces,
                    ),
                    _buildBackupOption(
                      icon: FluentIcons.book_24_regular,
                      title: 'שמור וזכור',
                      subtitle: 'ספרים ומעקב לימוד',
                      settingKey: _keyBackupShamorZachor,
                    ),
                  ]),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBackupOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required String settingKey,
  }) {
    return Column(
      children: [
        SwitchListTile(
          secondary: Icon(icon),
          title: Text(title, style: const TextStyle(fontSize: 16)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 13)),
          value: Settings.getValue<bool>(settingKey) ?? true,
          onChanged: (value) {
            Settings.setValue<bool>(settingKey, value);
            setState(() {});
          },
        ),
        const Divider(height: 1),
      ],
    );
  }
}

enum _BackupMode { all, custom }
