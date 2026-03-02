import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart'
    hide SettingsGroup;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/safer_mode/password_verification_dialog.dart';
import 'package:otzaria/settings/services/safer_mode/protected_settings_wrapper.dart';
import 'package:otzaria/settings/services/backup_service.dart';
import 'package:otzaria/core/scaffold_messenger.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/widgets/zip_extraction_progress_dialog.dart';
import 'package:otzaria/services/data_collection_service.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/widgets/custom_ui_components.dart';

/// טאב "אוצריא" — גרסאות, נתיב ספרייה, גיבוי, מצב סייפר, איפוס.
class SystemSettingsTab extends StatefulWidget {
  const SystemSettingsTab({super.key});

  @override
  State<SystemSettingsTab> createState() => _SystemSettingsTabState();
}

class _SystemSettingsTabState extends State<SystemSettingsTab> {
  final GlobalKey _networkModeTileKey = GlobalKey();

  // ── מפתחות גיבוי ──────────────────────────────────────────────────────────
  static const _keyBackupSettings = 'key-backup-settings';
  static const _keyBackupBookmarks = 'key-backup-bookmarks';
  static const _keyBackupHistory = 'key-backup-history';
  static const _keyBackupNotes = 'key-backup-notes';
  static const _keyBackupWorkspaces = 'key-backup-workspaces';
  static const _keyBackupShamorZachor = 'key-backup-shamor-zachor';
  static const _keyAutoBackupFrequency = 'key-auto-backup-frequency';

  _BackupMode _selectedBackupMode = _BackupMode.all;

  // ── מצב סייפר (expandable) ────────────────────────────────────────────────
  bool _isCypherExpanded = false;

  // ── גרסאות ────────────────────────────────────────────────────────────────
  String? _appVersion;
  String? _libraryVersion;
  int? _bookCount;

  @override
  void initState() {
    super.initState();
    _loadVersionInfo();
  }

  Future<void> _loadVersionInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final dataService = DataCollectionService();
    String? libVersion = await dataService.readLibraryVersion();
    if (libVersion == 'unknown') libVersion = 'לא ידוע';

    int? count;
    try {
      final library = await DataRepository.instance.library;
      count = library
          .getAllBooks()
          .where((b) => b.externalLibraryId == null)
          .length;
    } catch (_) {
      count = 0;
    }

    if (!mounted) return;
    setState(() {
      _appVersion = packageInfo.version;
      _libraryVersion = libVersion;
      _bookCount = count;
    });
  }

  bool _shouldInclude(String key) =>
      _selectedBackupMode == _BackupMode.all ||
      (Settings.getValue<bool>(key) ?? true);

  // ════════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          children: [
            // 1. גרסאות + נתיב ספרייה
            _buildVersionAndPathSection(context, state),
            const SizedBox(height: 16),

            // 2. עדכוני מערכת (רשת + עדכון מפתחים)
            _buildSystemUpdatesSection(context, state),
            const SizedBox(height: 16),

            // 3. תורמים (כרטיסי זיכרון)
            _buildMemorialSection(context),
            const SizedBox(height: 16),

            // 4. גיבוי (מקטע אחד מאוחד)
            _buildBackupSection(context),
            const SizedBox(height: 16),

            // 5. מצב סייפר (expandable)
            _buildCypherModeSection(context, state),
            const SizedBox(height: 16),

            // 6. איפוס
            _buildResetSection(context),
          ],
        );
      },
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  2. עדכוני מערכת (רשת + עדכון מפתחים)
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildSystemUpdatesSection(BuildContext context, SettingsState state) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final cardColor = Theme.of(context).cardColor;

    return _SectionCard(
      title: 'עדכוני מערכת',
      children: [
        KeyedSubtree(
          key: _networkModeTileKey,
          child: ListTile(
            leading: const Icon(FluentIcons.globe_24_regular),
            title:
                const Text('סינכרון ומצב רשת', style: TextStyle(fontSize: 16)),
            subtitle: Text(
              state.isOfflineMode
                  ? 'התוכנה מנותקת לגמרי מהרשת'
                  : 'התוכנה יכולה להתחבר לרשת',
              style: const TextStyle(fontSize: 13),
            ),
            trailing: SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  label: Text('מקוון'),
                  icon: Icon(FluentIcons.wifi_1_24_regular),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text('מנותק'),
                  icon: Icon(FluentIcons.wifi_off_24_regular),
                ),
              ],
              selected: {state.isOfflineMode},
              onSelectionChanged: (sel) {
                context.read<SettingsBloc>().add(UpdateOfflineMode(sel.first));
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  final ctx = _networkModeTileKey.currentContext;
                  if (ctx != null) {
                    Scrollable.ensureVisible(ctx,
                        duration: const Duration(milliseconds: 200),
                        alignment: 0.0);
                  }
                });
              },
              style: ButtonStyle(
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                backgroundColor: WidgetStateProperty.resolveWith<Color?>(
                  (states) => states.contains(WidgetState.selected)
                      ? primaryColor.withValues(alpha: 0.2)
                      : cardColor,
                ),
              ),
            ),
          ),
        ),
        if (!(Platform.isAndroid || Platform.isIOS) &&
            !state.isOfflineMode) ...[
          SwitchListTile(
            secondary: const Icon(FluentIcons.arrow_sync_24_regular),
            title: const Text(
              'סינכרון הספרייה באופן אוטומטי',
              style: TextStyle(fontSize: 16),
              textDirection: TextDirection.rtl,
            ),
            subtitle: Text(
              (Settings.getValue<bool>(SettingsRepository.keyAutoSync) ?? true)
                  ? 'מסד הנתונים של הספרייה יתעדכן אוטומטית דרך GitHub Releases'
                  : 'סינכרון הספרייה האוטומטי כבוי',
              style: const TextStyle(fontSize: 13),
              textDirection: TextDirection.rtl,
            ),
            value:
                Settings.getValue<bool>(SettingsRepository.keyAutoSync) ?? true,
            onChanged: (value) {
              Settings.setValue<bool>(SettingsRepository.keyAutoSync, value);
              setState(() {});
            },
          ),
          SwitchListTile(
            secondary: const Icon(FluentIcons.bug_24_regular),
            title: const Text('עדכון לגרסאות מפתחים',
                style: TextStyle(fontSize: 16)),
            subtitle: Text(
              Settings.getValue<bool>(SettingsRepository.keyDevChannel) ?? false
                  ? 'קבלת עדכונים על גרסאות בדיקה — ייתכנו באגים'
                  : 'קבלת עדכונים על גרסאות יציבות בלבד',
              style: const TextStyle(fontSize: 13),
            ),
            value: Settings.getValue<bool>(SettingsRepository.keyDevChannel) ??
                false,
            onChanged: (value) {
              Settings.setValue<bool>(SettingsRepository.keyDevChannel, value);
              setState(() {});
            },
          ),
        ],
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  2. גרסאות + נתיב ספרייה
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildVersionAndPathSection(
      BuildContext context, SettingsState state) {
    return _SectionCard(
      title: 'מערכת אוצריא',
      children: [
        ListTile(
          leading: const Icon(FluentIcons.info_24_regular),
          title: const Text('גרסת תוכנה', style: TextStyle(fontSize: 16)),
          subtitle: Text(_appVersion ?? 'טוען...',
              style: const TextStyle(fontSize: 13)),
          trailing: TextButton.icon(
            icon: const Icon(FluentIcons.history_24_regular, size: 16),
            label: const Text('יומן שינויים'),
            onPressed: () => _showChangelogDialog(context),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(FluentIcons.library_24_regular),
          title: const Text('גרסת ספרייה', style: TextStyle(fontSize: 16)),
          subtitle: Text(_libraryVersion ?? 'טוען...',
              style: const TextStyle(fontSize: 13)),
          trailing: TextButton.icon(
            icon: const Icon(FluentIcons.history_24_regular, size: 16),
            label: const Text('יומן שינויים'),
            onPressed: () => _showLibraryChangelogDialog(context),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(FluentIcons.book_24_regular),
          title: const Text('מספר ספרים', style: TextStyle(fontSize: 16)),
          subtitle: Text(
            _bookCount != null ? '${_bookCount!} ספרים' : 'טוען...',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (!(Platform.isAndroid || Platform.isIOS)) ...[
          const Divider(height: 1),
          ListTile(
            leading: const Icon(FluentIcons.folder_24_regular),
            title: const Text('מיקום ספריית אוצריא',
                style: TextStyle(fontSize: 16)),
            subtitle: Text(
              Settings.getValue<String>(SettingsRepository.keyLibraryPath) ??
                  'לא נבחר',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: NeutralActionButton(
              icon: FluentIcons.folder_open_24_regular,
              text: 'בחר תיקייה',
              onPressed: () async {
                final path = await FilePicker.platform.getDirectoryPath();
                if (path != null && context.mounted) {
                  _showLibraryExtractionDialog(context, path);
                }
              },
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _showLibraryExtractionDialog(
      BuildContext context, String path) async {
    await ZipExtractionProgressDialog.showAndExtract(
      context: context,
      path: path,
      onSuccess: (result) async {
        if (!context.mounted) return;
        context.read<LibraryBloc>().add(UpdateLibraryPath(path));
        await Future.delayed(const Duration(milliseconds: 500));
        if (context.mounted) {
          context.read<NavigationBloc>().add(const CheckLibrary());
          if (result.successfullyExtracted) {
            UiSnack.showSuccess(
                'הקובץ "${result.extractedFileName}" חולץ בהצלחה!');
          }
        }
      },
      onError: (err) {
        if (!context.mounted) return;
        UiSnack.showError(err);
      },
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  3. תורמים
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildMemorialSection(BuildContext context) {
    return _SectionCard(
      title: 'תורמים',
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: _MemorialCardsGrid(
            onDonationTap: () => _openDonationPage(),
          ),
        ),
      ],
    );
  }

  Future<void> _openDonationPage() async {
    final libraryPath =
        Settings.getValue<String>(SettingsRepository.keyLibraryPath);
    if (libraryPath == null || libraryPath.isEmpty) return;
    final htmlFile = File(p.join(libraryPath, 'donate.html'));
    if (!await htmlFile.exists()) {
      final uri = Uri.parse('https://nedar.im/ejco');
      if (await canLaunchUrl(uri)) await launchUrl(uri);
      return;
    }
    final uri = Uri.file(htmlFile.path);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  4. גיבוי — מקטע אחד מאוחד
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildBackupSection(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final cardColor = Theme.of(context).cardColor;
    final autoFrequency =
        Settings.getValue<String>(_keyAutoBackupFrequency) ?? 'none';

    return _SectionCard(
      title: 'גיבוי ושחזור',
      children: [
        // שורה 1: מצב גיבוי
        ListTile(
          leading: const Icon(FluentIcons.options_24_regular),
          title: const Text('מצב גיבוי', style: TextStyle(fontSize: 16)),
          trailing: SegmentedButton<_BackupMode>(
            style: ButtonStyle(
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              backgroundColor: WidgetStateProperty.resolveWith<Color?>(
                (states) => states.contains(WidgetState.selected)
                    ? primaryColor.withValues(alpha: 0.2)
                    : cardColor,
              ),
            ),
            segments: const [
              ButtonSegment<_BackupMode>(
                value: _BackupMode.all,
                label: Text('גבה הכל'),
              ),
              ButtonSegment<_BackupMode>(
                value: _BackupMode.custom,
                label: Text('מותאם אישית'),
              ),
            ],
            selected: {_selectedBackupMode},
            onSelectionChanged: (sel) =>
                setState(() => _selectedBackupMode = sel.first),
          ),
        ),

        // בחר מה לגבות (רק במצב מותאם אישית)
        if (_selectedBackupMode == _BackupMode.custom) ...[
          const Divider(height: 1),
          _BackupOptionTile(
            icon: FluentIcons.settings_24_regular,
            title: 'הגדרות',
            subtitle: 'כולל את כלל הגדרות התוכנה',
            settingKey: _keyBackupSettings,
            onChanged: () => setState(() {}),
          ),
          const Divider(height: 1),
          _BackupOptionTile(
            icon: FluentIcons.bookmark_24_regular,
            title: 'סימניות',
            subtitle: 'כל הסימניות שנשמרו',
            settingKey: _keyBackupBookmarks,
            onChanged: () => setState(() {}),
          ),
          const Divider(height: 1),
          _BackupOptionTile(
            icon: FluentIcons.history_24_regular,
            title: 'היסטוריה',
            subtitle: 'היסטוריית הלימוד',
            settingKey: _keyBackupHistory,
            onChanged: () => setState(() {}),
          ),
          const Divider(height: 1),
          _BackupOptionTile(
            icon: FluentIcons.note_24_regular,
            title: 'הערות אישיות',
            subtitle: 'כל ההערות האישיות שלך',
            settingKey: _keyBackupNotes,
            onChanged: () => setState(() {}),
          ),
          const Divider(height: 1),
          _BackupOptionTile(
            icon: FluentIcons.grid_24_regular,
            title: 'שולחנות עבודה',
            subtitle: 'כל שולחנות העבודה',
            settingKey: _keyBackupWorkspaces,
            onChanged: () => setState(() {}),
          ),
          const Divider(height: 1),
          _BackupOptionTile(
            icon: FluentIcons.book_24_regular,
            title: 'שמור וזכור',
            subtitle: 'ספרים ומעקב לימוד',
            settingKey: _keyBackupShamorZachor,
            onChanged: () => setState(() {}),
          ),
        ],

        const Divider(height: 1),

        // שורה 2: גיבוי אוטומטי
        ListTile(
          leading: const Icon(FluentIcons.calendar_clock_24_regular),
          title: const Text('גיבוי אוטומטי', style: TextStyle(fontSize: 16)),
          trailing: SegmentedButton<String>(
            style: ButtonStyle(
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              backgroundColor: WidgetStateProperty.resolveWith<Color?>(
                (states) => states.contains(WidgetState.selected)
                    ? primaryColor.withValues(alpha: 0.2)
                    : cardColor,
              ),
            ),
            segments: const [
              ButtonSegment<String>(value: 'none', label: Text('ללא')),
              ButtonSegment<String>(value: 'weekly', label: Text('שבועי')),
              ButtonSegment<String>(value: 'monthly', label: Text('חודשי')),
            ],
            selected: {autoFrequency},
            onSelectionChanged: (sel) {
              Settings.setValue<String>(_keyAutoBackupFrequency, sel.first);
              setState(() {});
            },
          ),
        ),

        const Divider(height: 1),

        // שורה 3: כפתורי צור/שחזר
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
    );
  }

  Future<void> _createBackup() async {
    try {
      final backupPath = await BackupService.createBackup(
        includeSettings: _shouldInclude(_keyBackupSettings),
        includeBookmarks: _shouldInclude(_keyBackupBookmarks),
        includeHistory: _shouldInclude(_keyBackupHistory),
        includeNotes: _shouldInclude(_keyBackupNotes),
        includeWorkspaces: _shouldInclude(_keyBackupWorkspaces),
        includeShamorZachor: _shouldInclude(_keyBackupShamorZachor),
      );
      if (!mounted) return;
      final file = File(backupPath);
      final exists = await file.exists();
      final size = exists ? await file.length() : 0;
      if (!mounted) return;
      if (exists) {
        UiSnack.showWithAction(
          message: 'הגיבוי נשמר! גודל: ${(size / 1024).toStringAsFixed(1)} KB',
          actionLabel: 'פתח תיקייה',
          onAction: () async {
            final dir = file.parent;
            if (Platform.isWindows) {
              await Process.run('explorer', [dir.path]);
            } else if (Platform.isMacOS) {
              await Process.run('open', [dir.path]);
            } else if (Platform.isLinux) {
              await Process.run('xdg-open', [dir.path]);
            }
          },
          icon: Icons.check_circle_outline_rounded,
          iconColor: Theme.of(context).colorScheme.primary,
        );
      }
    } catch (e) {
      if (!mounted) return;
      UiSnack.showError('שגיאה ביצירת הגיבוי: ${e.toString()}');
    }
  }

  Future<void> _restoreBackup() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    final filePath = result?.files.single.path;
    if (filePath == null) return;
    if (!mounted) return;

    // שימוש ב-showWarningDialog מ-custom_ui_components
    final confirmed = await showWarningDialog(
      context: context,
      title: 'שחזור מגיבוי?',
      content: 'פעולה זו תחליף את הנתונים הקיימים בנתונים מהגיבוי.',
      subtitle: 'פעולה זו אינה הפיכה!',
      cancelText: 'ביטול',
      confirmText: 'שחזר',
    );
    if (confirmed != true) return;

    try {
      await BackupService.restoreFromBackup(filePath);
      if (!mounted) return;
      await showSingleActionDialog(
        context: context,
        title: 'השחזור הושלם',
        content: 'הנתונים שוחזרו בהצלחה. יש להפעיל מחדש את התוכנה.',
        confirmText: 'סגור את התוכנה',
      );
      if (Platform.isAndroid || Platform.isIOS) {
        SystemNavigator.pop();
      } else {
        windowManager.close();
      }
    } catch (e) {
      if (!mounted) return;
      UiSnack.showError('שגיאה בשחזור הגיבוי: ${e.toString()}');
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  5. מצב סייפר (expandable)
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildCypherModeSection(BuildContext context, SettingsState state) {
    final repository = RepositoryProvider.of<SettingsRepository>(context);
    final hasPassword = repository.hasProtectedModePassword();

    return _SectionCard(
      title: 'מצב מוגן',
      children: [
        // שורה ראשית — לחיצה פותחת/סוגרת
        ListTile(
          leading: Icon(
            state.protectedModeEnabled
                ? FluentIcons.shield_lock_24_filled
                : FluentIcons.shield_lock_24_regular,
            color: state.protectedModeEnabled
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          title: const Text('מצב סייפר', style: TextStyle(fontSize: 16)),
          subtitle: const Text('נעילת הגדרות', style: TextStyle(fontSize: 13)),
          trailing: Icon(
            _isCypherExpanded
                ? FluentIcons.chevron_up_24_regular
                : FluentIcons.chevron_down_24_regular,
          ),
          onTap: () => setState(() => _isCypherExpanded = !_isCypherExpanded),
        ),

        // תוכן מורחב — אנימציה
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: _isCypherExpanded
              ? Column(
                  children: [
                    const Divider(height: 1),
                    // הפעלת מצב מוגן
                    SwitchListTile(
                      secondary: Icon(
                        state.protectedModeEnabled
                            ? FluentIcons.lock_closed_24_filled
                            : FluentIcons.lock_open_24_regular,
                      ),
                      title: const Text('הפעל מצב סייפר',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(fontSize: 16)),
                      subtitle: Text(
                        hasPassword ? 'סיסמה הוגדרה' : 'יש להגדיר סיסמה תחילה',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          fontSize: 13,
                          color: hasPassword
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.error,
                        ),
                      ),
                      value: state.protectedModeEnabled,
                      onChanged: hasPassword
                          ? (value) => _handleToggleProtectedMode(
                              context, repository, value)
                          : null,
                    ),
                    const Divider(height: 1),
                    // הגדרת/שינוי סיסמה
                    ListTile(
                      leading: const Icon(FluentIcons.key_24_regular),
                      title: const Text(
                        'סיסמה',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(fontSize: 16),
                      ),
                      trailing: RecommendedActionButton(
                        icon: FluentIcons.key_24_regular,
                        text: hasPassword ? 'שנה סיסמה' : 'בחר סיסמה',
                        onPressed: () => _handleSetPassword(
                            context, repository, hasPassword),
                      ),
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Future<void> _handleToggleProtectedMode(
    BuildContext context,
    SettingsRepository repository,
    bool newValue,
  ) async {
    if (!newValue) {
      final verified = await showDialog<bool>(
        context: context,
        builder: (context) => PasswordVerificationDialog(
          title: 'אמת סיסמה',
          hint: 'הזן את הסיסמה כדי להשבית את המצב המוגן',
          onVerify: (password) async =>
              repository.verifyProtectedModePassword(password),
        ),
      );
      if (verified != true) return;
    }
    if (context.mounted) {
      context.read<SettingsBloc>().add(UpdateProtectedModeEnabled(newValue));
      if (!newValue) UiSnack.show('המצב המוגן הושבת');
    }
  }

  Future<void> _handleSetPassword(
    BuildContext context,
    SettingsRepository repository,
    bool hasExistingPassword,
  ) async {
    if (hasExistingPassword) {
      final verified = await showDialog<bool>(
        context: context,
        builder: (context) => PasswordVerificationDialog(
          title: 'אמת סיסמה נוכחית',
          hint: 'הזן את הסיסמה הנוכחית כדי לשנות אותה',
          onVerify: (password) async =>
              repository.verifyProtectedModePassword(password),
        ),
      );
      if (verified != true) return;
    }
    if (!context.mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => SetPasswordDialog(
        onSetPassword: (password) async {
          context
              .read<SettingsBloc>()
              .add(UpdateProtectedModePassword(password));
        },
      ),
    );
    if (result == true && context.mounted && !hasExistingPassword) {
      context.read<SettingsBloc>().add(const UpdateProtectedModeEnabled(true));
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  6. איפוס
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildResetSection(BuildContext context) {
    return _SectionCard(
      title: 'איפוס',
      children: [
        ListTile(
          hoverColor: Colors.transparent,
          leading: const Icon(FluentIcons.arrow_reset_24_regular),
          title: const Text('איפוס הגדרות', style: TextStyle(fontSize: 16)),
          subtitle: const Text('מחיקת כל ההגדרות וחזרה למצב ההתחלתי',
              style: TextStyle(fontSize: 13)),
          trailing: NeutralActionButton(
            icon: FluentIcons.arrow_reset_24_regular,
            text: 'אפס הגדרות',
            onPressed: () async {
              if (shouldProtectSettings(context)) {
                final verified = await verifyPasswordForAction(context);
                if (!verified || !context.mounted) return;
              }
              if (!context.mounted) return;

              final confirmed = await showWarningDialog(
                context: context,
                title: 'איפוס הגדרות?',
                content: 'כל ההגדרות האישיות שלך ימחקו.',
                subtitle: 'פעולה זו אינה הפיכה!',
                cancelText: 'ביטול',
                confirmText: 'אפס',
              );
              if (confirmed == true && context.mounted) {
                Settings.clearCache();
                await showSingleActionDialog(
                  context: context,
                  title: 'ההגדרות אופסו',
                  content: 'יש לסגור ולהפעיל מחדש את התוכנה.',
                  confirmText: 'סגור את התוכנה',
                );
                if (Platform.isAndroid || Platform.isIOS) {
                  SystemNavigator.pop();
                } else {
                  windowManager.close();
                }
              }
            },
          ),
        ),
      ],
    );
  }

  // ── Changelog dialogs ──────────────────────────────────────────────────────

  Future<void> _showChangelogDialog(BuildContext context) async {
    String changelog;
    try {
      changelog = await rootBundle.loadString('assets/יומן שינויים.md');
    } catch (_) {
      changelog = 'לא נמצא קובץ יומן שינויים.';
    }
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('יומן שינויים בתוכנה'),
          content: SizedBox(
            width: 600,
            height: 400,
            child: Markdown(data: changelog),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('סגור')),
          ],
        ),
      ),
    );
  }

  Future<void> _showLibraryChangelogDialog(BuildContext context) async {
    final libraryPath =
        Settings.getValue<String>(SettingsRepository.keyLibraryPath) ?? '';
    final changelogPath =
        p.join(libraryPath, 'אוצריא', 'אודות התוכנה', 'עדכוני ספריה.md');
    final file = File(changelogPath);
    final changelog = (await file.exists())
        ? await file.readAsString()
        : 'קובץ יומן השינויים לא נמצא.';
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('יומן שינויים בספרייה'),
          content: SizedBox(
            width: 600,
            height: 400,
            child: Markdown(data: changelog),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('סגור')),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  כרטיסי זיכרון
// ══════════════════════════════════════════════════════════════════════════════

class _MemorialCardsGrid extends StatelessWidget {
  final VoidCallback onDonationTap;
  const _MemorialCardsGrid({required this.onDonationTap});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final spacing = 12.0;
      final itemWidth = (constraints.maxWidth - spacing * 2) / 3;
      const itemHeight = 150.0;
      final aspectRatio = itemWidth / itemHeight;

      return GridView.count(
        crossAxisCount: 3,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: aspectRatio,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _MemorialCard(
            name: "לע\"נ ר' משה בן יהודה ראה ז\"ל",
            description: 'סכום משמעותי לפיתוח התוכנה',
          ),
          // 2 כרטיסי תרומה עם כפתור נדרים+
          _DonationMemorialCard(onTap: onDonationTap),
          _DonationMemorialCard(onTap: onDonationTap),
        ],
      );
    });
  }
}

class _MemorialCard extends StatelessWidget {
  final String name;
  final String description;

  const _MemorialCard({required this.name, required this.description});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_fire_department,
                color: Colors.orange[700], size: 24),
            const SizedBox(height: 6),
            Text(name,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(description,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}

class _DonationMemorialCard extends StatelessWidget {
  final VoidCallback onTap;
  const _DonationMemorialCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_fire_department,
                color: Colors.orange[300], size: 24),
            const SizedBox(height: 6),
            const Text(
              'מקום זה יכול להיות מונצח לע"נ יקירך',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // כפתור נדרים+
            RecommendedActionButton(
              icon: FluentIcons.payment_24_regular,
              text: 'נדרים+',
              onPressed: onTap,
            ),
          ],
        ),
      ),
    );
  }
}

// ── _BackupOptionTile ─────────────────────────────────────────────────────────

class _BackupOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String settingKey;
  final VoidCallback onChanged;

  const _BackupOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.settingKey,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(icon),
      title: Text(title, style: const TextStyle(fontSize: 16)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 13)),
      value: Settings.getValue<bool>(settingKey) ?? true,
      onChanged: (value) {
        Settings.setValue<bool>(settingKey, value);
        onChanged();
      },
    );
  }
}

// ── _SectionCard ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4, left: 4, bottom: 8, top: 4),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
              letterSpacing: 0.3,
            ),
          ),
        ),
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: _addDividers(children)),
        ),
      ],
    );
  }

  List<Widget> _addDividers(List<Widget> items) {
    if (items.length <= 1) return items;
    final result = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      result.add(items[i]);
      if (i < items.length - 1) {
        result.add(const Divider(height: 1, indent: 0, endIndent: 0));
      }
    }
    return result;
  }
}

enum _BackupMode { all, custom }
