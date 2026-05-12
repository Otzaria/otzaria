import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/personal_notes/view/personal_notes_screen.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/measurement_converter/measurement_converter_screen.dart';
import 'package:otzaria/tools/gematria/gematria_search_screen.dart';
import 'package:otzaria/tools/acronyms_dictionary/acronyms_dictionary_screen.dart';
import 'package:otzaria/tools/aramaic_dictionary/aramaic_dictionary_screen.dart';
import 'package:otzaria/tools/shamor_zachor/shamor_zachor.dart';
import 'package:otzaria/tools/calendar/calendar_screen.dart';
import 'package:otzaria/widgets/navigation/keyboard_navigator.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/widgets/navigation/sidebar_nav_item.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/view/plugin_side_panel.dart';
import 'package:otzaria/plugins/view/plugin_tab_page.dart';
import 'package:otzaria/widgets/layout/context_overlay_panel.dart';
import 'package:otzaria/plugins/utils/fluent_icon_resolver.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/settings_card.dart';
import 'package:otzaria/tour/tour_target_keys.dart';

/// מזהה הכלי שפעיל כרגע ב-ToolsScreen, או `null` אם המסך לא מוצג.
/// משמש את ה-MainWindowScreen כדי להדגיש את התוסף שבחרת בסרגל הניווט/הבר
/// כשנבחרה לשונית של תוסף-מוצמד-לסרגל.
final ValueNotifier<String?> activeToolIdNotifier = ValueNotifier<String?>(null);

abstract class ToolDescriptor {
  final String toolId;
  final String label;
  final int order;
  const ToolDescriptor(
      {required this.toolId, required this.label, required this.order});
  Widget buildTab(BuildContext context);
  Widget buildPage(BuildContext context);
  TopNavItem buildTopNavItem({required bool isSelected, required VoidCallback onTap, Key? key});
  SidebarNavItem buildSidebarNavItem({required bool isSelected, required VoidCallback onTap, Key? key});
}

class BuiltInToolDescriptor extends ToolDescriptor {
  final IconData? icon;
  final IconData? iconFilled;
  final String? imageIcon;
  final Widget Function() pageBuilder;

  const BuiltInToolDescriptor({
    required super.toolId,
    required super.label,
    required super.order,
    this.icon,
    this.iconFilled,
    this.imageIcon,
    required this.pageBuilder,
  });

  @override
  Widget buildTab(BuildContext context) {
    if (imageIcon != null) {
      return SizedBox(
        width: 100,
        child:
            Tab(text: label, icon: ImageIcon(AssetImage(imageIcon!), size: 20)),
      );
    }
    return SizedBox(
      width: 100,
      child: Tab(text: label, icon: Icon(icon, size: 20)),
    );
  }

  @override
  Widget buildPage(BuildContext context) => pageBuilder();

  @override
  TopNavItem buildTopNavItem({required bool isSelected, required VoidCallback onTap, Key? key}) {
    return TopNavItem(
      key: key,
      icon: icon,
      iconFilled: iconFilled,
      imageAsset: imageIcon,
      label: label,
      isSelected: isSelected,
      onTap: onTap,
    );
  }

  @override
  SidebarNavItem buildSidebarNavItem({required bool isSelected, required VoidCallback onTap, Key? key}) {
    return SidebarNavItem(
      key: key,
      icon: icon,
      iconFilled: iconFilled,
      imageAsset: imageIcon,
      label: label,
      isSelected: isSelected,
      onTap: onTap,
    );
  }
}

class PluginToolDescriptor extends ToolDescriptor {
  final InstalledPlugin plugin;
  PluginToolDescriptor({required this.plugin})
      : super(
            toolId: plugin.pluginId,
            label: plugin.manifest.toolTabTitle,
            order: plugin.manifest.toolTabOrder);

  @override
  Widget buildTab(BuildContext context) {
    final iconData = fluentIconFromName(plugin.manifest.toolTabIconName);
    return SizedBox(
      width: 100,
      child: Tab(
        text: label,
        icon: iconData != null ? Icon(iconData, size: 20) : null,
      ),
    );
  }

  @override
  Widget buildPage(BuildContext context) => PluginTabPage(
        key: ValueKey(plugin.pluginId),
        plugin: plugin,
      );

  IconData get _pluginIcon =>
      fluentIconFromName(plugin.manifest.toolTabIconName) ??
      FluentIcons.puzzle_piece_24_regular;

  @override
  TopNavItem buildTopNavItem({required bool isSelected, required VoidCallback onTap, Key? key}) {
    final icon = _pluginIcon;
    return TopNavItem(
      key: key,
      icon: icon,
      iconFilled: icon,
      label: label,
      isSelected: isSelected,
      onTap: onTap,
    );
  }

  @override
  SidebarNavItem buildSidebarNavItem({required bool isSelected, required VoidCallback onTap, Key? key}) {
    final icon = _pluginIcon;
    return SidebarNavItem(
      key: key,
      icon: icon,
      iconFilled: icon,
      label: label,
      isSelected: isSelected,
      onTap: onTap,
    );
  }
}

class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});

  @override
  ToolsScreenState createState() => ToolsScreenState();
}

class ToolsScreenState extends State<ToolsScreen>
    with AutomaticKeepAliveClientMixin {
  static const int _calendarFocusRetryCount = 6;

  final GlobalKey<CalendarWidgetState> _calendarKey =
      GlobalKey<CalendarWidgetState>();
  final GlobalKey<GematriaSearchScreenState> _gematriaKey =
      GlobalKey<GematriaSearchScreenState>();
  final FocusNode _contentFocusNode = FocusNode(skipTraversal: true);
  final ScrollController _contentScrollController = ScrollController();

  List<ToolDescriptor> _descriptors = [];
  List<Widget> _pages = [];
  String? _selectedToolId;
  bool _isPanelOpen = false;
  bool _showMobileMenu = true;
  InstalledPlugin? _transientPlugin;
  bool _didInitFromBloc = false;
  // מונע rebuild מרובה של הטאבים כאשר הזהות המלאה של הלשוניות לא השתנתה
  String _lastDescriptorsSignature = '';

  // גלילת שורת הטאבים בדסקטופ
  final ScrollController _tabScrollController = ScrollController();
  bool _canTabScrollLeft = false;
  bool _canTabScrollRight = false;

  // בקשת פתיחה ממתינה לכלי שעדיין אין לו descriptor (בעיקר תוספים שטרם
  // נטענו מ-PluginSystemBloc). תיפתח באוטומט ב-_applyTabState הבא, או
  // תיכשל עם UiSnack לאחר timeout.
  String? _pendingToolIdToOpen;
  Timer? _pendingToolTimeoutTimer;
  static const Duration _pendingToolTimeout = Duration(seconds: 5);

  static const _mobileGroupDefs = [
    (label: 'לוח שנה', toolIds: <String>['builtin.calendar']),
    (
      label: 'תורה שלמדתי',
      toolIds: <String>['builtin.shamor_zachor', 'builtin.notes']
    ),
    (
      label: 'דקדוקי סופרים',
      toolIds: <String>[
        'builtin.measurements',
        'builtin.gematria',
        'builtin.aramaic_dictionary',
        'builtin.acronyms_dictionary'
      ]
    ),
  ];

  // ─── Focus management ────────────────────────────────────────────────────────

  String _descriptorSignature(List<ToolDescriptor> descriptors) {
    return descriptors.map((d) {
      if (d is PluginToolDescriptor) {
        return '${d.toolId}|${d.label}|${d.order}|${d.plugin.pinned}|${d.plugin.manifest.toolTabIconName}|${d.plugin.updatedAt.millisecondsSinceEpoch}';
      }
      return '${d.toolId}|${d.label}|${d.order}';
    }).join('::');
  }

  void _requestCalendarFocus(
      {int remainingAttempts = _calendarFocusRetryCount}) {
    if (!mounted) return;
    final calendarState = _calendarKey.currentState;
    if (calendarState != null) {
      calendarState.requestKeyboardFocus();
      return;
    }
    if (remainingAttempts <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future<void>.delayed(const Duration(milliseconds: 50), () {
        if (mounted) {
          _requestCalendarFocus(remainingAttempts: remainingAttempts - 1);
        }
      });
    });
  }

  /// מעדכן את ה-screen restorer של מסך הכלים.
  ///
  /// הקריטריון הוא מה מחובר לעץ הפוקוס בפועל, לא _showMobileMenu:
  /// - בdesktop, _contentFocusNode תמיד בעץ גם כש-_showMobileMenu==true
  /// - בmobile menu, _contentFocusNode לא מחובר → canRestore=false טבעית
  void _registerMoreRestorer() {
    FocusRepository().setScreenRestorer(
      restore: () {
        if (!mounted) return;
        if (_selectedToolId == 'builtin.calendar') {
          _requestCalendarFocus();
        } else if (_contentFocusNode.enclosingScope != null) {
          _contentFocusNode.requestFocus();
        }
      },
      canRestore: () {
        if (!mounted) return false;
        if (_selectedToolId == 'builtin.calendar') {
          return _calendarKey.currentState != null;
        }
        return _contentFocusNode.enclosingScope != null;
      },
    );
  }

  void requestActiveTabFocus() {
    // עדכון restorer מיידי לפי מצב נוכחי, לפני כל addPostFrameCallback
    _registerMoreRestorer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // אין unfocus גלובלי — זה עלול להשאיר את האפליקציה ללא פוקוס כלל
      // אם ה-requestFocus שאחריו נכשל (למשל בזמן resize ב-Windows).
      if (_selectedToolId == 'builtin.calendar') {
        _requestCalendarFocus();
      } else if (_contentFocusNode.enclosingScope != null &&
          !_contentFocusNode.hasFocus) {
        _contentFocusNode.requestFocus();
      }
    });
  }

  // ─── Tab / descriptor management ────────────────────────────────────────────

  List<ToolDescriptor> _buildBaseDescriptors() {
    return [
      BuiltInToolDescriptor(
        toolId: 'builtin.calendar',
        label: 'לוח שנה',
        icon: FluentIcons.calendar_24_regular,
        iconFilled: FluentIcons.calendar_24_filled,
        order: 10,
        pageBuilder: () => BlocBuilder<CalendarCubit, CalendarState>(
          builder: (context, _) => CalendarWidget(key: _calendarKey),
        ),
      ),
      BuiltInToolDescriptor(
        toolId: 'builtin.shamor_zachor',
        label: 'שמור וזכור',
        imageIcon: 'assets/icon/שמור וזכור שחור ריק.png',
        order: 20,
        pageBuilder: () => ShamorZachorWidget(onTitleChanged: (_) {}),
      ),
      BuiltInToolDescriptor(
        toolId: 'builtin.measurements',
        label: 'מדות ושיעורים',
        icon: FluentIcons.ruler_24_regular,
        iconFilled: FluentIcons.ruler_24_filled,
        order: 30,
        pageBuilder: () => const MeasurementConverterScreen(),
      ),
      BuiltInToolDescriptor(
        toolId: 'builtin.notes',
        label: 'הערות אישיות',
        icon: FluentIcons.note_24_regular,
        iconFilled: FluentIcons.note_24_filled,
        order: 40,
        pageBuilder: () => const PersonalNotesManagerScreen(),
      ),
      BuiltInToolDescriptor(
        toolId: 'builtin.gematria',
        label: 'גימטריה',
        icon: FluentIcons.calculator_24_regular,
        iconFilled: FluentIcons.calculator_24_filled,
        order: 50,
        pageBuilder: () => GematriaSearchScreen(key: _gematriaKey),
      ),
      BuiltInToolDescriptor(
        toolId: 'builtin.aramaic_dictionary',
        label: 'מילון ארמי-עברי',
        icon: FluentIcons.translate_24_regular,
        iconFilled: FluentIcons.translate_24_filled,
        order: 60,
        pageBuilder: () => const AramaicDictionaryScreen(),
      ),
      BuiltInToolDescriptor(
        toolId: 'builtin.acronyms_dictionary',
        label: 'ראשי תיבות',
        icon: FluentIcons.text_quote_24_regular,
        iconFilled: FluentIcons.text_quote_24_filled,
        order: 70,
        pageBuilder: () => const AcronymsDictionaryScreen(),
      ),
    ];
  }

  void _closeTransientPanelsForToolId(String? toolId) {
    if (toolId == 'builtin.calendar') {
      _calendarKey.currentState?.closeTransientPanels();
    }
  }

  void closeTransientPanels() {
    _closeTransientPanelsForToolId(_selectedToolId);
  }

  void _setSelectedToolId(String? id) {
    _selectedToolId = id;
    activeToolIdNotifier.value = id;
  }

  void _changeTab(int index) {
    if (index < 0 || index >= _descriptors.length) return;
    final toolId = _descriptors[index].toolId;
    if (_selectedToolId == toolId && !_showMobileMenu) {
      requestActiveTabFocus();
      return;
    }
    _closeTransientPanelsForToolId(_selectedToolId);
    setState(() {
      _setSelectedToolId(toolId);
      _showMobileMenu = false;
    });
    requestActiveTabFocus();
  }

  void openPluginTransiently(InstalledPlugin plugin) {
    final isOfflineMode = context.read<SettingsBloc>().state.isOfflineMode;
    if (isOfflineMode && plugin.requiresNetwork) {
      UiSnack.showError(
          'התוסף "${plugin.name}" דורש חיבור אינטרנט ולא ניתן לפתוח אותו במצב מנותק');
      return;
    }
    if (plugin.pinned) {
      // לתוסף שמוצמד-ללשוניות יש (או יהיה) descriptor רגיל. מנתבים דרך
      // requestOpenTool כדי לקבל את מנגנון ה-pending/timeout במקרה שה-bloc
      // עדיין לא טען את הרשימה ברגע הלחיצה.
      requestOpenTool(plugin.pluginId);
      return;
    }
    // לתוסף שלא מוצמד ללשוניות — מצב transient (מחושב כאן ולא מחכה ל-bloc)
    _transientPlugin = plugin;
    _setSelectedToolId(plugin.pluginId);
    final blocState = context.read<PluginSystemBloc>().state;
    if (blocState is PluginSystemLoaded) {
      _rebuildTabs(
        blocState.pinnedPlugins.filterForOfflineMode(isOfflineMode),
        transient: _transientPlugin,
      );
    }
  }

  void _applyTabState(
    List<InstalledPlugin> pinnedPlugins, {
    InstalledPlugin? transient,
    required bool notify,
  }) {
    final newDescriptors = <ToolDescriptor>[
      ..._buildBaseDescriptors(),
      ...pinnedPlugins.map((p) => PluginToolDescriptor(plugin: p)),
    ];
    if (transient != null) {
      if (!pinnedPlugins.any((p) => p.pluginId == transient.pluginId)) {
        newDescriptors.add(PluginToolDescriptor(plugin: transient));
      }
    }

    newDescriptors.sort((a, b) => a.order.compareTo(b.order));
    final newSignature = _descriptorSignature(newDescriptors);
    if (newSignature == _lastDescriptorsSignature && _pages.isNotEmpty) {
      return;
    }
    _lastDescriptorsSignature = newSignature;

    String newToolId = _selectedToolId ?? newDescriptors.first.toolId;
    if (!newDescriptors.any((d) => d.toolId == newToolId)) {
      newToolId = newDescriptors.first.toolId;
    }

    void applyState() {
      _descriptors = newDescriptors;
      _pages = newDescriptors.map((t) => t.buildPage(context)).toList();
      _setSelectedToolId(newToolId);
    }

    if (notify) {
      setState(applyState);
    } else {
      applyState();
    }

    _flushPendingToolIfReady();
  }

  void _rebuildTabs(List<InstalledPlugin> pinnedPlugins,
      {InstalledPlugin? transient}) {
    if (!mounted) return;
    _applyTabState(pinnedPlugins, transient: transient, notify: true);
  }

  // ─── Lifecycle ────────────────────────────────────────────────────────────────

  void _onTabScrollMetrics(ScrollMetrics metrics) {
    final canLeft = metrics.pixels > metrics.minScrollExtent + 0.5;
    final canRight = metrics.pixels < metrics.maxScrollExtent - 0.5;
    if (_canTabScrollLeft != canLeft || _canTabScrollRight != canRight) {
      setState(() {
        _canTabScrollLeft = canLeft;
        _canTabScrollRight = canRight;
      });
    }
  }

  void _updateTabScrollState() {
    if (!mounted || !_tabScrollController.hasClients) return;
    final pos = _tabScrollController.position;
    if (!pos.hasContentDimensions) return;
    _onTabScrollMetrics(pos);
  }

  void _tabScrollBy(double delta) {
    if (!_tabScrollController.hasClients) return;
    final pos = _tabScrollController.position;
    final target =
        (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    _tabScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  void initState() {
    super.initState();
    FocusRepository().registerMoreScreenFocusRequester(requestActiveTabFocus);
    _applyTabState([], notify: false);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _updateTabScrollState());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInitFromBloc) {
      _didInitFromBloc = true;
      final state = context.read<PluginSystemBloc>().state;
      if (state is PluginSystemLoaded) {
        final isOfflineMode = context.read<SettingsBloc>().state.isOfflineMode;
        _applyTabState(
          state.pinnedPlugins.filterForOfflineMode(isOfflineMode),
          notify: false,
        );
      }
    }
  }

  void resetToCalendar() {
    if (_selectedToolId != 'builtin.calendar') {
      setState(() {
        _setSelectedToolId('builtin.calendar');
        _showMobileMenu = false;
      });
      return;
    }
    _requestCalendarFocus();
  }

  /// פותח לשונית כלי לפי מזהה. אם ה-descriptor עדיין לא נטען (תוסף שעוד לא
  /// הגיע מ-PluginSystemBloc), הבקשה נכנסת לתור ותתבצע אוטומטית בעת הרענון
  /// הבא של ה-descriptors. אם תוך 5 שניות עדיין לא נמצא — מוצגת שגיאה.
  ///
  /// משמש גם את ה-Guided Tour וגם את ה-deep links (`otzaria://open/tool/...`).
  void requestOpenTool(String toolId) {
    final index = _descriptors.indexWhere((d) => d.toolId == toolId);
    if (index != -1) {
      _clearPendingTool();
      _changeTab(index);
      return;
    }

    // ה-descriptor לא נמצא בלשוניות הנוכחיות. בודקים אם מדובר בתוסף שכן מותקן
    // אבל סונן מהתצוגה בגלל מצב מנותק — כדי להחזיר שגיאה תיאורית במקום
    // "הכלי לא נמצא" המטעה.
    final isOfflineMode = context.read<SettingsBloc>().state.isOfflineMode;
    if (isOfflineMode) {
      final blocState = context.read<PluginSystemBloc>().state;
      if (blocState is PluginSystemLoaded) {
        InstalledPlugin? hiddenPlugin;
        for (final p in blocState.plugins) {
          if (p.pluginId == toolId) {
            hiddenPlugin = p;
            break;
          }
        }
        if (hiddenPlugin != null && hiddenPlugin.requiresNetwork) {
          _clearPendingTool();
          UiSnack.showError(
              'התוסף "${hiddenPlugin.name}" דורש חיבור אינטרנט ולא ניתן לפתוח אותו במצב מנותק');
          return;
        }
      }
    }

    // ה-descriptor עדיין לא קיים — קורה בעיקר עם תוספים לפני ש-PluginSystemLoaded
    // הגיע. ממתינים ל-_applyTabState הבא כדי לפתוח, ומוסיפים timeout עם פידבק
    // למקרה שהכלי לא מתקיים בפועל.
    _pendingToolIdToOpen = toolId;
    _pendingToolTimeoutTimer?.cancel();
    _pendingToolTimeoutTimer = Timer(_pendingToolTimeout, () {
      if (!mounted) return;
      if (_pendingToolIdToOpen == toolId) {
        _pendingToolIdToOpen = null;
        _pendingToolTimeoutTimer = null;
        UiSnack.showError('הכלי "$toolId" לא נמצא');
      }
    });
  }

  void _clearPendingTool() {
    _pendingToolIdToOpen = null;
    _pendingToolTimeoutTimer?.cancel();
    _pendingToolTimeoutTimer = null;
  }

  void _flushPendingToolIfReady() {
    final pendingId = _pendingToolIdToOpen;
    if (pendingId == null) return;
    final index = _descriptors.indexWhere((d) => d.toolId == pendingId);
    if (index == -1) return;
    _clearPendingTool();
    // _applyTabState רץ בתוך setState; דוחים את החלפת הטאב לפריים הבא כדי לא
    // לקנן setState נוספת.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (index < _descriptors.length &&
          _descriptors[index].toolId == pendingId) {
        _changeTab(index);
      } else {
        // הסדר השתנה בין הקריאות — נחפש שוב לפי id.
        final freshIndex =
            _descriptors.indexWhere((d) => d.toolId == pendingId);
        if (freshIndex != -1) _changeTab(freshIndex);
      }
    });
  }

  @override
  void dispose() {
    FocusRepository().unregisterMoreScreenFocusRequester(requestActiveTabFocus);
    _pendingToolTimeoutTimer?.cancel();
    _contentFocusNode.dispose();
    _contentScrollController.dispose();
    _tabScrollController.dispose();
    activeToolIdNotifier.value = null;
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  // ─── UI builders ─────────────────────────────────────────────────────────────

  Widget _buildMobileMenu(Color bgColor) {
    final cs = Theme.of(context).colorScheme;

    final groupedDescriptors = <({String label, List<ToolDescriptor> tools})>[];
    for (final group in _mobileGroupDefs) {
      final tools = [
        for (final id in group.toolIds)
          ..._descriptors.where((d) => d.toolId == id),
      ];
      if (tools.isNotEmpty) {
        groupedDescriptors.add((label: group.label, tools: tools));
      }
    }

    final groupedIds = _mobileGroupDefs.expand((g) => g.toolIds).toSet();
    final ungroupedPlugins =
        _descriptors.where((d) => !groupedIds.contains(d.toolId)).toList();
    if (ungroupedPlugins.isNotEmpty) {
      groupedDescriptors.add((label: 'תוספים', tools: ungroupedPlugins));
    }

    Widget buildIcon(ToolDescriptor descriptor) {
      if (descriptor is BuiltInToolDescriptor) {
        if (descriptor.imageIcon != null) {
          return ImageIcon(AssetImage(descriptor.imageIcon!), size: 22, color: cs.primary);
        }
        return Icon(descriptor.icon, color: cs.primary);
      }
      if (descriptor is PluginToolDescriptor) {
        return Icon(descriptor._pluginIcon, color: cs.primary);
      }
      return Icon(FluentIcons.puzzle_piece_24_regular, color: cs.primary);
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('כלים', textDirection: TextDirection.rtl),
        actions: [
          IconButton(
            icon: const Icon(FluentIcons.puzzle_piece_24_regular),
            tooltip: 'תוספים',
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: PluginSidePanel(
                  onPluginSelected: (plugin) {
                    Navigator.of(context).pop();
                    openPluginTransiently(plugin);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final group in groupedDescriptors) ...[
            SettingsCard(
              title: group.label,
              children: [
                for (final descriptor in group.tools)
                  ListTile(
                    key: tourToolTabTargetKeys[descriptor.toolId],
                    leading: buildIcon(descriptor),
                    title: Text(descriptor.label),
                    trailing: const RtlIcon(FluentIcons.chevron_left_24_regular),
                    onTap: () {
                      final index = _descriptors.indexOf(descriptor);
                      if (index != -1) _changeTab(index);
                    },
                  ),
              ],
            ),
            const SizedBox(height: AppTokens.spaceSM),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileContent(Color bgColor) {
    final currentIndex =
        _descriptors.indexWhere((d) => d.toolId == _selectedToolId);
    final safeIndex = currentIndex.clamp(
        0, _descriptors.isEmpty ? 0 : _descriptors.length - 1);

    return KeyboardNavigator(
      currentTabIndex: safeIndex,
      totalTabs: _descriptors.length,
      onTabChange: _changeTab,
      onBack: () => setState(() => _showMobileMenu = true),
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: bgColor,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(
            _descriptors.isEmpty ? '' : _descriptors[safeIndex].label,
            textDirection: TextDirection.rtl,
          ),
          leading: Tooltip(
            message: 'חזור (Esc)',
            child: IconButton(
              icon: const RtlIcon(FluentIcons.arrow_right_24_regular),
              onPressed: () => setState(() => _showMobileMenu = true),
            ),
          ),
        ),
        body: Focus(
          focusNode: _contentFocusNode,
          child: ColoredBox(
            color: bgColor,
            child: _pages.isEmpty ? const SizedBox() : _pages[safeIndex],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktop(Color bgColor) {
    final currentIndex =
        _descriptors.indexWhere((d) => d.toolId == _selectedToolId);
    final safeIndex = currentIndex.clamp(
        0, _descriptors.isEmpty ? 0 : _descriptors.length - 1);

    return KeyboardNavigator(
      currentTabIndex: safeIndex,
      totalTabs: _descriptors.length,
      onTabChange: _changeTab,
      onBack: null,
      child: ColoredBox(
        color: bgColor,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent &&
                      _contentScrollController.hasClients) {
                    final newOffset =
                        _contentScrollController.offset + event.scrollDelta.dy;
                    _contentScrollController.jumpTo(
                      newOffset.clamp(0.0,
                          _contentScrollController.position.maxScrollExtent),
                    );
                  }
                },
                child: Column(
                  children: [
                    ColoredBox(
                      color: bgColor,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppTokens.spaceXS,
                        ),
                        child: Row(
                          children: [
                            // חץ ימני – מוצג כשיש תוכן נסתר בצד ימין
                            SizedBox(
                              width: 36,
                              height: 40,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: _canTabScrollLeft ? 1.0 : 0.0,
                                child: IgnorePointer(
                                  ignoring: !_canTabScrollLeft,
                                  child: IconButton(
                                    icon: const RtlIcon(
                                        FluentIcons.chevron_right_24_regular),
                                    iconSize: 18,
                                    onPressed: () => _tabScrollBy(-150),
                                    tooltip: 'גלול ימינה',
                                    constraints: const BoxConstraints(
                                        minWidth: 32, minHeight: 32),
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: NotificationListener<
                                  ScrollMetricsNotification>(
                                onNotification: (n) {
                                  if (n.metrics.axis == Axis.horizontal) {
                                    _onTabScrollMetrics(n.metrics);
                                  }
                                  return false;
                                },
                                child: NotificationListener<ScrollNotification>(
                                  onNotification: (n) {
                                    if (n.metrics.axis == Axis.horizontal) {
                                      _onTabScrollMetrics(n.metrics);
                                    }
                                    return false;
                                  },
                                  child: Center(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      controller: _tabScrollController,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          for (int index = 0;
                                              index < _descriptors.length;
                                              index++) ...[
                                            _descriptors[index].buildTopNavItem(
                                              key: tourToolTabTargetKeys[
                                                  _descriptors[index].toolId],
                                              isSelected: _selectedToolId ==
                                                  _descriptors[index].toolId,
                                              onTap: () => _changeTab(index),
                                            ),
                                            if (index < _descriptors.length - 1)
                                              const SizedBox(
                                                  width: AppTokens.spaceXS),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // חץ שמאלי – מוצג כשיש תוכן נסתר בצד שמאל
                            SizedBox(
                              width: 36,
                              height: 40,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: _canTabScrollRight ? 1.0 : 0.0,
                                child: IgnorePointer(
                                  ignoring: !_canTabScrollRight,
                                  child: IconButton(
                                    icon: const RtlIcon(
                                        FluentIcons.chevron_left_24_regular),
                                    iconSize: 18,
                                    onPressed: () => _tabScrollBy(150),
                                    tooltip: 'גלול שמאלה',
                                    constraints: const BoxConstraints(
                                        minWidth: 32, minHeight: 32),
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                            ),
                            // כפתור תוספים מוצמד לשמאל חזותי (סוף Row ב-RTL)
                            IconButton(
                              icon: const Icon(
                                  FluentIcons.puzzle_piece_24_regular),
                              onPressed: () =>
                                  setState(() => _isPanelOpen = !_isPanelOpen),
                              tooltip: 'תוספים',
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          ClipRect(
                            child: PrimaryScrollController(
                              controller: _contentScrollController,
                              child: Focus(
                                focusNode: _contentFocusNode,
                                child: ColoredBox(
                                  color: bgColor,
                                  child: _pages.isEmpty
                                      ? const SizedBox()
                                      : IndexedStack(
                                          sizing: StackFit.expand,
                                          index: safeIndex,
                                          children: _pages,
                                        ),
                                ),
                              ),
                            ),
                          ),
                          ContextOverlayPanel(
                            isOpen: _isPanelOpen,
                            onClose: () => setState(() => _isPanelOpen = false),
                            width: 300,
                            child: PluginSidePanel(
                              onPluginSelected: (plugin) {
                                openPluginTransiently(plugin);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final bgColor = AppSurfaces.panelBackground(context);

    return MultiBlocListener(
      listeners: [
        BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (prev, curr) => prev.isOfflineMode != curr.isOfflineMode,
          listener: (context, settingsState) {
            final blocState = context.read<PluginSystemBloc>().state;
            if (blocState is! PluginSystemLoaded) return;
            // אם התוסף ה-transient דורש אינטרנט ועברנו למצב מנותק — נסגור אותו.
            if (settingsState.isOfflineMode &&
                _transientPlugin != null &&
                _transientPlugin!.requiresNetwork) {
              _transientPlugin = null;
            }
            _rebuildTabs(
              blocState.pinnedPlugins
                  .filterForOfflineMode(settingsState.isOfflineMode),
              transient: _transientPlugin,
            );
          },
        ),
        BlocListener<PluginSystemBloc, PluginSystemState>(
          listener: (context, state) {
            if (state is PluginSystemLoaded) {
              if (_transientPlugin != null) {
                final updatedTransient = state.plugins.firstWhere(
                    (p) => p.pluginId == _transientPlugin!.pluginId,
                    orElse: () => _transientPlugin!);
                _transientPlugin = updatedTransient;
              }
              final isOfflineMode =
                  context.read<SettingsBloc>().state.isOfflineMode;
              _rebuildTabs(
                state.pinnedPlugins.filterForOfflineMode(isOfflineMode),
                transient: _transientPlugin,
              );
            } else if (state is PluginSystemOverwriteRequired) {
              showWarningDialog(
                context: context,
                title: 'התוסף כבר קיים',
                content:
                    'התוסף "${state.pluginName}" בגרסה ${state.version} כבר מותקן.',
                subtitle: 'האם ברצונך להתקין מחדש ולדרוס אותו?',
                cancelText: 'ביטול',
                confirmText: 'התקן מחדש',
              ).then((value) {
                if (!context.mounted) return;
                if (value == true) {
                  context.read<PluginSystemBloc>().add(
                        InstallPluginRequested(state.archivePath,
                            forceOverwrite: true),
                      );
                } else {
                  context.read<PluginSystemBloc>().add(LoadPlugins());
                }
              });
            }
          },
        ),
      ],
      child: Theme(
        data: Theme.of(context).copyWith(
          scaffoldBackgroundColor: bgColor,
          canvasColor: bgColor,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < LayoutBreakpoints.compact;
            final content = isMobile
                ? (_showMobileMenu
                    ? _buildMobileMenu(bgColor)
                    : _buildMobileContent(bgColor))
                : _buildDesktop(bgColor);

            // החזרת content ישירות — ללא AnimatedSwitcher וללא KeyedSubtree.
            // AnimatedSwitcher עם key משתנה גורם ל-Flutter לשמיד ולהקים
            // מחדש את כל ה-subtree (כולל FocusNodes) בכל מעבר mobile↔desktop,
            // וזו שורש הקריסות ואיבודי הפוקוס ב-Windows בזמן resize.
            return content;
          },
        ),
      ),
    );
  }
}

