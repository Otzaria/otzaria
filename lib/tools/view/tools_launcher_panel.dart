import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/tool_catalog_entry.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/widgets/layout/app_card.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// כותרות שני מקטעי הרשת.
const String kBuiltInToolsGroupLabel = 'כלים';
const String kPluginsGroupLabel = 'תוספים';

/// מנרמל טקסט להשוואת חיפוש: גרשיים, מקפים וניקוד אינם אמורים למנוע התאמה.
@visibleForTesting
String normalizeToolSearchText(String value) {
  return value
      .replaceAll(RegExp(r'[֑-ׇ]'), '')
      .replaceAll(RegExp(r'''["'`׳״\-–—]'''), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();
}

/// מסנן רשומות לפי מחרוזת חיפוש, מול התווית ומול שם התוסף.
@visibleForTesting
List<ToolCatalogEntry> filterToolEntries(
  List<ToolCatalogEntry> entries,
  String query,
) {
  final normalized = normalizeToolSearchText(query);
  if (normalized.isEmpty) return entries;
  return entries.where((entry) {
    if (normalizeToolSearchText(entry.label).contains(normalized)) return true;
    final pluginName = entry.plugin?.name;
    return pluginName != null &&
        normalizeToolSearchText(pluginName).contains(normalized);
  }).toList();
}

typedef ToolGroup = ({String label, List<ToolCatalogEntry> entries});

/// מפצל את הרשומות לשני מקטעים: כלים מובנים ואז תוספים, בשמירת הסדר בכל
/// מקטע. מקטע ריק אינו מוחזר.
@visibleForTesting
List<ToolGroup> groupToolEntries(List<ToolCatalogEntry> entries) {
  final builtIns = entries.where((entry) => !entry.isPlugin).toList();
  final plugins = entries.where((entry) => entry.isPlugin).toList();
  return [
    if (builtIns.isNotEmpty)
      (label: kBuiltInToolsGroupLabel, entries: builtIns),
    if (plugins.isNotEmpty) (label: kPluginsGroupLabel, entries: plugins),
  ];
}

/// סדר הקוביות כפי שהן מוצגות בפועל. ניווט המקלדת ממופה לאינדקס ברשימה הזו,
/// ולכן היא חייבת להישאר זהה לסדר הרינדור.
@visibleForTesting
List<ToolCatalogEntry> orderedToolEntries(List<ToolCatalogEntry> entries) => [
  for (final group in groupToolEntries(entries)) ...group.entries,
];

/// רוחב היעד לקובייה, ממנו נגזר מספר העמודות. הפאנל ניתן לגרירה ולכן החישוב
/// מבוסס על הרוחב בפועל ולא על breakpoints קבועים.
@visibleForTesting
const double kToolTileTargetWidth = 104;

/// מספר העמודות ברשת לרוחב פאנל נתון.
@visibleForTesting
int toolGridColumns(double width) =>
    (width / kToolTileTargetWidth).floor().clamp(2, 5);

/// האינדקס המסומן הבא בניווט מקלדת. נעצר בקצוות ואינו גולש למחזוריות, כדי
/// שחץ ברצף לא "יקפוץ" מהקובייה האחרונה לראשונה.
@visibleForTesting
int nextHighlightIndex({
  required int current,
  required int delta,
  required int total,
}) {
  if (total <= 0) return 0;
  return (current + delta).clamp(0, total - 1);
}

/// תוכן פאנל הכלים: חיפוש למעלה, ומתחתיו רשת קוביות מקובצת.
class ToolsLauncherPanel extends StatefulWidget {
  final ValueChanged<ToolCatalogEntry> onToolSelected;
  final VoidCallback onClose;
  final bool showDevTools;

  const ToolsLauncherPanel({
    super.key,
    required this.onToolSelected,
    required this.onClose,
    this.showDevTools = kDebugMode,
  });

  @override
  State<ToolsLauncherPanel> createState() => _ToolsLauncherPanelState();
}

class _ToolsLauncherPanelState extends State<ToolsLauncherPanel> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _query = '';

  /// הקובייה המסומנת בניווט מקלדת, כאינדקס ברשימה המסוננת השטוחה.
  int _highlightedIndex = 0;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _installPlugin() async {
    final verified = await verifySaferModePassword(context);
    if (!verified || !mounted) return;
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['otzplugin'],
      lockParentWindow: true,
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    context.read<PluginSystemBloc>().add(InstallPluginRequested(path));
  }

  Future<void> _loadDevPlugin() async {
    final verified = await verifySaferModePassword(context);
    if (!verified || !mounted) return;
    final rootPath = await FilePicker.getDirectoryPath(lockParentWindow: true);
    if (rootPath == null || !mounted) return;
    context.read<PluginSystemBloc>().add(
      LoadDevelopmentPluginRequested(rootPath),
    );
  }

  Future<void> _loadLocalhostPlugin() async {
    final verified = await verifySaferModePassword(context);
    if (!verified || !mounted) return;
    final bloc = context.read<PluginSystemBloc>();
    final url = await showInputDialog(
      context: context,
      title: 'טעינת תוסף מ-localhost',
      labelText: 'Base URL',
      hintText: 'http://localhost:3000',
      initialValue: 'http://localhost:3000',
      cancelText: 'ביטול',
      confirmText: 'טען',
    );
    if (url == null || url.isEmpty) return;
    bloc.add(LoadLocalhostPluginRequested(url));
  }

  // ─── ניווט מקלדת ─────────────────────────────────────────────────────────

  void _moveHighlight(int delta, int total) {
    if (total == 0) return;
    setState(() {
      _highlightedIndex = nextHighlightIndex(
        current: _highlightedIndex,
        delta: delta,
        total: total,
      );
    });
  }

  KeyEventResult _handleKey(
    KeyEvent event,
    List<ToolCatalogEntry> entries,
    int columns,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        widget.onClose();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _moveHighlight(columns, entries.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _moveHighlight(-columns, entries.length);
        return KeyEventResult.handled;
      // ב-RTL הקובייה הבאה נמצאת משמאל, ולכן החיצים מתהפכים ביחס ל-LTR.
      case LogicalKeyboardKey.arrowLeft:
        _moveHighlight(1, entries.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _moveHighlight(-1, entries.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        if (_highlightedIndex < entries.length) {
          widget.onToolSelected(entries[_highlightedIndex]);
        }
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settingsState = context.watch<SettingsBloc>().state;
    final pluginState = context.watch<PluginSystemBloc>().state;
    final allEntries = buildToolCatalog(
      hiddenBuiltInToolIds: settingsState.hiddenBuiltInToolIds,
      isOfflineMode: settingsState.isOfflineMode,
      pluginState: pluginState,
    );
    final entries = orderedToolEntries(filterToolEntries(allEntries, _query));
    final openToolIds = _openToolIds(context.watch<TabsBloc>().state);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        const SizedBox(height: AppTokens.spaceSM),
        _buildSearchField(entries),
        const SizedBox(height: AppTokens.spaceMD),
        Expanded(
          child: entries.isEmpty
              ? _buildEmptyState(settingsState.isOfflineMode, allEntries)
              : _buildGrid(entries, openToolIds),
        ),
      ],
    );
  }

  Set<String> _openToolIds(TabsState state) => {
    for (final tab in state.tabs)
      for (final pane in leafPanes(tab))
        if (pane is ToolTab) pane.toolId,
  };

  Widget _buildHeader() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(FluentIcons.dismiss_24_regular, size: 20),
          tooltip: 'סגור',
          visualDensity: VisualDensity.compact,
          onPressed: widget.onClose,
        ),
        const Expanded(
          child: Text(
            'כלים ותוספים',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: AppTokens.fontXL,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(FluentIcons.add_24_regular, size: 20),
          tooltip: 'התקן תוסף חדש',
          visualDensity: VisualDensity.compact,
          onPressed: _installPlugin,
        ),
        if (widget.showDevTools) ...[
          IconButton(
            icon: const Icon(FluentIcons.folder_add_24_regular, size: 20),
            tooltip: 'טען תיקיית תוסף',
            visualDensity: VisualDensity.compact,
            onPressed: _loadDevPlugin,
          ),
          IconButton(
            icon: const Icon(FluentIcons.globe_add_24_regular, size: 20),
            tooltip: 'טען תוסף מ-localhost',
            visualDensity: VisualDensity.compact,
            onPressed: _loadLocalhostPlugin,
          ),
          IconButton(
            icon: const Icon(FluentIcons.arrow_sync_24_regular, size: 20),
            tooltip: 'רענן תוספים',
            visualDensity: VisualDensity.compact,
            onPressed: () =>
                context.read<PluginSystemBloc>().add(RefreshPlugins()),
          ),
        ],
      ],
    );
  }

  Widget _buildSearchField(List<ToolCatalogEntry> entries) {
    return RtlTextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      autofocus: true,
      decoration: const InputDecoration(
        hintText: 'חיפוש כלי או תוסף',
        prefixIcon: Icon(FluentIcons.search_24_regular, size: 20),
        isDense: true,
        border: OutlineInputBorder(borderRadius: AppTokens.borderRadiusAll),
      ),
      onChanged: (value) => setState(() {
        _query = value;
        _highlightedIndex = 0;
      }),
      onSubmitted: (_) {
        if (entries.isNotEmpty) {
          widget.onToolSelected(
            entries[_highlightedIndex.clamp(
              0,
              entries.length - 1,
            )],
          );
        }
      },
    );
  }

  Widget _buildEmptyState(bool isOfflineMode, List<ToolCatalogEntry> all) {
    final message = _query.trim().isNotEmpty
        ? 'לא נמצאו כלים התואמים לחיפוש'
        : (isOfflineMode
              ? 'אין כלים זמינים במצב מנותק'
              : 'לא נמצאו כלים זמינים');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLG),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }

  Widget _buildGrid(List<ToolCatalogEntry> entries, Set<String> openToolIds) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = toolGridColumns(constraints.maxWidth);
        final groups = groupToolEntries(entries);
        var runningIndex = 0;

        final theme = Theme.of(context);
        return Focus(
          autofocus: false,
          onKeyEvent: (_, event) => _handleKey(event, entries, columns),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (var i = 0; i < groups.length; i++) ...[
                if (i > 0)
                  const Padding(
                    padding: EdgeInsets.only(
                      top: AppTokens.spaceMD,
                      bottom: AppTokens.spaceSM,
                    ),
                    child: Divider(height: 1),
                  ),
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppTokens.spaceSM,
                    bottom: AppTokens.spaceSM,
                  ),
                  child: Text(
                    groups[i].label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.secondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: AppTokens.spaceSM,
                  crossAxisSpacing: AppTokens.spaceSM,
                  childAspectRatio: 1.0,
                  children: [
                    for (final entry in groups[i].entries)
                      ToolTile(
                        entry: entry,
                        isOpen: openToolIds.contains(entry.toolId),
                        isHighlighted: runningIndex++ == _highlightedIndex,
                        onTap: () => widget.onToolSelected(entry),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppTokens.spaceMD),
            ],
          ),
        );
      },
    );
  }
}

/// קובייה בודדת ברשת הכלים — עיצוב כרטיסי הספרייה: אייקון בתוך ריבוע
/// `secondaryContainer` מעוגל, וכותרת מתחתיו. הקובייה מרובעת (1:1) והתוכן ממורכז.
class ToolTile extends StatelessWidget {
  /// ריבוע האייקון והאייקון שבתוכו — זהים לכרטיסי הספרייה.
  static const double iconBoxSize = 32;
  static const double iconSize = 16;

  final ToolCatalogEntry entry;
  final bool isOpen;
  final bool isHighlighted;
  final VoidCallback onTap;

  const ToolTile({
    super.key,
    required this.entry,
    required this.isOpen,
    required this.isHighlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Tooltip(
      message: entry.plugin?.name ?? entry.label,
      waitDuration: const Duration(milliseconds: 600),
      child: AppCard(
        onTap: onTap,
        selected: isHighlighted,
        child: Stack(
          children: [
            // Center + mainAxisSize.min ממרכז את הצמד אייקון+טקסט כגוש אחד,
            // כך שהמרכוז אינו תלוי במספר שורות הכותרת.
            Center(
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.spaceXS),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: iconBoxSize,
                      height: iconBoxSize,
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer,
                        borderRadius: AppTokens.borderRadiusAll,
                      ),
                      child: Center(child: _buildIcon(cs)),
                    ),
                    const SizedBox(height: AppTokens.spaceXS),
                    Flexible(
                      child: Text(
                        entry.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (entry.isDevelopment)
              PositionedDirectional(
                top: 2,
                start: 2,
                child: _Badge(label: 'DEV', color: cs.tertiary),
              ),
            if (isOpen)
              PositionedDirectional(
                top: 2,
                end: 2,
                child: Icon(
                  FluentIcons.checkmark_circle_16_filled,
                  size: 12,
                  color: cs.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(ColorScheme cs) {
    if (entry.imageIcon != null) {
      return ImageIcon(
        AssetImage(entry.imageIcon!),
        size: iconSize,
        color: cs.onSecondaryContainer,
      );
    }
    return Icon(entry.icon, size: iconSize, color: cs.onSecondaryContainer);
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onTertiary,
        ),
      ),
    );
  }
}
