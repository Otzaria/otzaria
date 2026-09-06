import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/core/messages/window_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/utils/confirm_close_tabs.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';

/// סוגר כרטיסיה ורושם אותה בהיסטוריה.
///
/// כל פונקציות הסגירה כאן לוכדות את ה-blocs לפני ה-await של דיאלוג האישור,
/// כי ה-context של תפריט ההקשר עלול להתפרק בזמן שהדיאלוג פתוח.
Future<void> closeTabWithHistory(BuildContext context, OpenedTab tab) async {
  final historyBloc = context.read<HistoryBloc>();
  final tabsBloc = context.read<TabsBloc>();
  if (!await confirmCloseTabs(context, [tab])) return;
  historyBloc.add(AddHistory(tab));
  tabsBloc.add(RemoveTab(tab));
}

/// סוגר חלונית אחת מלשונית מפוצלת; אחותה נשארת ככרטיסיה רגילה במקומה.
Future<void> closePaneWithHistory(
  BuildContext context,
  OpenedTab pane,
) async {
  final historyBloc = context.read<HistoryBloc>();
  final tabsBloc = context.read<TabsBloc>();
  if (!await confirmCloseTabs(context, [pane])) return;
  historyBloc.add(AddHistory(pane));
  tabsBloc.add(ClosePane(pane));
}

/// סוגר את כל הכרטיסיות שבבחירה המרובה בפעולה אחת.
Future<void> closeSelectedTabsWithHistory(BuildContext context) async {
  final tabsBloc = context.read<TabsBloc>();
  final historyBloc = context.read<HistoryBloc>();
  final tabsToClose = List<OpenedTab>.from(tabsBloc.state.selectedTabs);
  if (tabsToClose.isEmpty) return;
  if (!await confirmCloseTabs(context, tabsToClose)) return;
  // אירוע קבוצתי אחד — אירועי AddHistory נפרדים מעובדים במקביל ועלולים
  // לדרוס זה את זה.
  historyBloc.add(AddHistoryForTabs(tabsToClose));
  tabsBloc.add(RemoveTabs(tabsToClose));
}

/// סוגר את כל הכרטיסיות שאינן מוצמדות ורושם אותן בהיסטוריה.
Future<void> closeAllTabsWithHistory(BuildContext context) async {
  final tabsBloc = context.read<TabsBloc>();
  final historyBloc = context.read<HistoryBloc>();
  final closing = tabsBloc.state.tabs.where((t) => !t.isPinned).toList();
  if (!await confirmCloseTabs(context, closing)) return;
  historyBloc.add(
    AddHistoryForTabs(closing.where((t) => t is! SearchingTab).toList()),
  );
  tabsBloc.add(CloseAllTabs());
}

/// סוגר את כל הכרטיסיות מלבד [keepTab].
Future<void> closeOtherTabsConfirmed(
  BuildContext context,
  OpenedTab keepTab,
) async {
  final tabsBloc = context.read<TabsBloc>();
  final closing = tabsBloc.state.tabs.where((t) => t != keepTab);
  if (!await confirmCloseTabs(context, closing)) return;
  tabsBloc.add(CloseOtherTabs(keepTab));
}

/// תפריט ההקשר של כרטיסיה, משותף לרצועה העליונה ולעמודה האנכית.
///
/// [onCloseTab] / [onCloseSelectedTabs] מוזרקים כי הרצועה העליונה מקפיאה
/// את רוחב הכרטיסיות בסגירה, והעמודה האנכית לא.
List<AppContextMenuEntry> buildTabContextMenuEntries(
  BuildContext context,
  OpenedTab tab,
  TabsState state, {
  required void Function(OpenedTab tab) onCloseTab,
  required VoidCallback onCloseSelectedTabs,
}) {
  final entries = <AppContextMenuEntry>[
    AppContextMenuEntry(
      label: tab.isPinned
          ? context.settingsText('בטל הצמדת כרטיסיה')
          : context.settingsText('הצמד כרטיסיה'),
      onTap: () => context.read<TabsBloc>().add(TogglePinTab(tab)),
    ),
    // על טאב שנכלל בבחירה מרובה "סגור" הופך לסגירת כל הקבוצה (כמו בדפדפן).
    if (state.selectedTabs.length > 1 && state.selectedTabs.contains(tab))
      AppContextMenuEntry(
        label: context.settingsText(
          'סגור {count} כרטיסיות',
          args: {'count': state.selectedTabs.length},
        ),
        onTap: onCloseSelectedTabs,
      )
    else
      AppContextMenuEntry(
        label: context.settingsText('סגור'),
        onTap: () => onCloseTab(tab),
      ),
    AppContextMenuEntry(
      label: context.settingsText('סגור הכל'),
      onTap: () => closeAllTabsWithHistory(context),
    ),
    AppContextMenuEntry(
      label: context.settingsText('סגור את האחרים'),
      onTap: () => closeOtherTabsConfirmed(context, tab),
    ),
    if (tab is! ToolTab || tab.isBuiltIn)
      AppContextMenuEntry(
        label: context.settingsText('שיכפול'),
        onTap: () => context.read<TabsBloc>().add(CloneTab(tab)),
      ),
    // הכרטיסיה עוברת לחלון חדש: היא נפתחת שם ונסגרת כאן. הסדר חשוב —
    // פותחים תחילה, וסוגרים רק אחרי שהבקשה נמסרה ל-runner, כדי שכשל
    // בפתיחה לא יאבד את הכרטיסיה.
    if (MultiWindowService.isSupported)
      AppContextMenuEntry(
        label: context.settingsText('העבר לחלון חדש'),
        onTap: () => _moveTabToNewWindow(context, tab),
      ),
    // תת-תפריט של החלונות הפתוחים האחרים, בדיוק כמו "הצג לצד". מופיע רק
    // כשיש לאן להעביר — פריט מושבת לא היה מוסיף מידע.
    if (MultiWindowService.isSupported &&
        MultiWindowService.transferTargets.isNotEmpty)
      AppContextMenuEntry(
        label: context.settingsText('העבר לחלון קיים'),
        children: [
          for (final peer in MultiWindowService.transferTargets)
            AppContextMenuEntry(
              label: peer.tabCount > 1
                  ? WindowMessages.peerWithTabs(peer.title, peer.tabCount)
                  : peer.title,
              onTap: () => _moveTabToExistingWindow(context, tab, peer.slot),
            ),
        ],
      ),
    const AppContextMenuEntry.divider(),
  ];

  // טאב שכבר מפוצל אינו נכנס לפיצול נוסף: הפיצול הוא לשתי חלוניות בלבד.
  final otherTabs = tab is CombinedTab
      ? const <OpenedTab>[]
      : state.tabs.where((t) => t != tab && t is! CombinedTab).toList();
  if (otherTabs.isEmpty) {
    entries.add(
      AppContextMenuEntry(
        label: context.settingsText('הצג לצד'),
        enabled: false,
      ),
    );
  } else {
    entries.add(
      AppContextMenuEntry(
        label: context.settingsText('הצג לצד'),
        children: otherTabs
            .map(
              (otherTab) => AppContextMenuEntry(
                label: otherTab.title,
                onTap: () => context.read<TabsBloc>().add(
                  CreateCombinedTab(rightTab: tab, leftTab: otherTab),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  if (tab is CombinedTab) {
    // לחיצה ימנית אינה מחליפה טאב פעיל, לכן האירועים מקבלים אינדקס מפורש.
    final tabIndex = state.tabs.indexOf(tab);
    entries.addAll([
      AppContextMenuEntry(
        label: context.settingsText('סגור חלונית'),
        children: [
          for (final pane in leafPanes(tab))
            AppContextMenuEntry(
              label: pane.title,
              onTap: () => closePaneWithHistory(context, pane),
            ),
        ],
      ),
      AppContextMenuEntry(
        label: context.settingsText('החלף צדדים'),
        onTap: () => context.read<TabsBloc>().add(
          SwapSideBySideTabs(tabIndex: tabIndex),
        ),
      ),
      AppContextMenuEntry(
        label: context.settingsText('חזרה לתצוגה רגילה'),
        onTap: () => context.read<TabsBloc>().add(ExpandCombinedTab(tabIndex)),
      ),
    ]);
  }

  entries.addAll([
    const AppContextMenuEntry.divider(),
    _buildTabsPlacementEntry(context),
    AppContextMenuEntry(
      label: context.settingsText('כרטיסיות פתוחות'),
      // childrenBuilder + stream: הרשימה נבנית מחדש בכל שינוי במצב הכרטיסיות,
      // כך שסגירת כרטיסייה דרך ה-X מסירה את שורתה והתפריט נשאר פתוח.
      childrenBuilder: () => _openTabsMenuEntries(
        context,
        context.read<TabsBloc>().state.tabs,
        onCloseTab,
      ),
      childrenRefreshStream: context.read<TabsBloc>().stream,
    ),
    _buildMoveToWorkspaceMenuEntry(context, tab),
  ]);

  return entries;
}

/// בדיקות משותפות ל"העבר לחלון חדש" ול"העבר לחלון קיים": כרטיסיה שאינה
/// ניתנת להעברה, כרטיסיה אחרונה, ומצב ה-JS של תוסף שאובד בהעברה.
Future<bool> _confirmTabTransfer(
  BuildContext context,
  OpenedTab tab,
  TabsState state, {
  required bool opensNewWindow,
}) async {
  if (!MultiWindowService.canTransfer(tab)) {
    UiSnack.showError(WindowMessages.cannotTransferTab);
    return false;
  }
  // רק לחלון חדש, ששם היא מחליפה חלון בחלון. לחלון קיים היא כן עוברת —
  // חלון משני שהתרוקן נסגר בעקבותיה.
  if (opensNewWindow && state.tabs.length <= 1) {
    UiSnack.show(WindowMessages.cannotTransferLastTab);
    return false;
  }
  return confirmCloseTabs(context, [tab]);
}

Future<void> _moveTabToNewWindow(BuildContext context, OpenedTab tab) async {
  final tabsBloc = context.read<TabsBloc>();
  // ⚠️ נבדק **לפני** הפעולה ולא בדיעבד: `openWindow` ממתין עד 20 שניות,
  // והמשתמש היה מקבל "אפשר לפתוח עד N חלונות" רק בסופן.
  if (!await const MultiWindowService().canOpenAnotherWindow()) {
    await const MultiWindowService().reportOpenWindowFailure();
    return;
  }
  if (!context.mounted) return;
  if (!await _confirmTabTransfer(
    context,
    tab,
    tabsBloc.state,
    opensNewWindow: true,
  )) {
    return;
  }

  final opened = await const MultiWindowService().openWindow(tab: tab);
  if (opened) {
    tabsBloc.add(RemoveTab(tab));
  } else {
    await const MultiWindowService().reportOpenWindowFailure();
  }
}

Future<void> _moveTabToExistingWindow(
  BuildContext context,
  OpenedTab tab,
  int slot,
) async {
  final tabsBloc = context.read<TabsBloc>();
  if (!await _confirmTabTransfer(
    context,
    tab,
    tabsBloc.state,
    opensNewWindow: false,
  )) {
    return;
  }

  // ⚠️ ההסרה רק אחרי אישור מהיעד. הרשימה עשויה להיות מעט לא-עדכנית, וחלון
  // שנסגר בדיוק עכשיו לא יאשר — ואז הכרטיסיה נשארת כאן במקום להיעלם משני
  // הצדדים.
  final sent = await const MultiWindowService().sendTabToWindow(slot, tab);
  if (sent == true) {
    tabsBloc.add(RemoveTab(tab));
    return;
  }
  UiSnack.showError(
    sent == false
        ? WindowMessages.transferFailed
        : WindowMessages.transferUnconfirmed,
  );
}

/// החלפה בין רצועת הכרטיסיות שבכותרת לעמודה האנכית שבצד.
AppContextMenuEntry _buildTabsPlacementEntry(BuildContext context) {
  final onSide = context.read<SettingsBloc>().state.readingTabsOnSide;
  return AppContextMenuEntry(
    label: onSide
        ? context.settingsText('הצג כרטיסיות למעלה')
        : context.settingsText('הצג כרטיסיות בצד'),
    onTap: () => context.read<SettingsBloc>().add(
      UpdateReadingTabsPlacement(
        onSide
            ? SettingsRepository.readingTabsPlacementTop
            : SettingsRepository.readingTabsPlacementSide,
      ),
    ),
  );
}

List<AppContextMenuEntry> _openTabsMenuEntries(
  BuildContext context,
  List<OpenedTab> tabs,
  void Function(OpenedTab tab) onCloseTab,
) {
  // ללא מיון — הרשימה משקפת את סדר הכרטיסיות בשורת הכרטיסיות.
  return tabs.map((tab) {
    return AppContextMenuEntry(
      label: tab.title,
      onTap: () {
        final index = tabs.indexOf(tab);
        context.read<TabsBloc>().add(SetCurrentTab(index));
      },
      trailing: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: IconButton(
          tooltip: context.settingsText('סגור'),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          icon: const Icon(FluentIcons.dismiss_24_regular, size: 14),
          // סגירת הכרטיסייה מעדכנת את ה-TabsBloc; ה-childrenRefreshStream
          // יבנה מחדש את הרשימה ושורת הכרטיסייה תיעלם.
          onPressed: () => onCloseTab(tab),
          splashRadius: 16,
        ),
      ),
    );
  }).toList();
}

/// בונה פריט תפריט להעברת טאב לשולחן עבודה אחר
AppContextMenuEntry _buildMoveToWorkspaceMenuEntry(
  BuildContext context,
  OpenedTab tab,
) {
  final workspaceState = context.read<WorkspaceBloc>().state;

  final otherWorkspaces = workspaceState.workspaces
      .where((w) => w.id != workspaceState.activeWorkspaceId)
      .toList();

  if (otherWorkspaces.isEmpty) {
    return AppContextMenuEntry(
      label: context.settingsText('העבר לשולחן עבודה'),
      enabled: false,
    );
  }

  return AppContextMenuEntry(
    label: context.settingsText('העבר לשולחן עבודה'),
    children: otherWorkspaces.map((workspace) {
      return AppContextMenuEntry(
        label: workspace.name,
        onTap: () => _moveTabToWorkspace(context, tab, workspace.id),
      );
    }).toList(),
  );
}

/// מעביר טאב לשולחן עבודה אחר
Future<void> _moveTabToWorkspace(
  BuildContext context,
  OpenedTab tab,
  String targetWorkspaceId,
) async {
  final tabsBloc = context.read<TabsBloc>();
  final workspaceBloc = context.read<WorkspaceBloc>();
  // ההעברה סוגרת את הכרטיסיה כאן; מצב ה-JS של תוסף אינו עובר איתה.
  if (!await confirmCloseTabs(context, [tab])) return;
  final tabsState = tabsBloc.state;
  final workspaceState = workspaceBloc.state;

  // ⚠️ `firstWhereOrNull`: השולחן יכול להימחק בחלון אחר בין בניית התפריט
  // לבחירה, ו-`firstWhere` זרק `StateError` באמצע הפעולה.
  final targetWorkspace = workspaceState.workspaces.firstWhereOrNull(
    (w) => w.id == targetWorkspaceId,
  );
  if (targetWorkspace == null) {
    UiSnack.showError(LibraryMessages.workspaceNoLongerExists);
    return;
  }

  tabsBloc.add(RemoveTab(tab));

  final currentTabs = tabsState.tabs.where((t) => t != tab).toList();
  final newActiveIndex = currentTabs.isEmpty
      ? 0
      : tabsState.currentTabIndex.clamp(0, currentTabs.length - 1);

  // הסרת הטאב מזיזה את האינדקס, ולכן צד החלונית הפעילה תקף רק אם הטאב
  // הפעיל אחרי ההסרה הוא אותו טאב עצמו. אחרת הוא מתייחס לטאב אחר.
  final newActiveTab = currentTabs.isEmpty ? null : currentTabs[newActiveIndex];
  final activePaneToKeep = identical(newActiveTab, tabsState.currentTab)
      ? tabsState.activePaneSide
      : null;

  workspaceBloc.add(
    MoveTabToWorkspace(
      tab: tab,
      targetWorkspaceId: targetWorkspaceId,
      currentTabs: currentTabs,
      currentTabIndex: newActiveIndex,
      currentActivePane: activePaneToKeep,
    ),
  );

  UiSnack.show(LibraryMessages.tabMovedToWorkspace(targetWorkspace.name));
}
