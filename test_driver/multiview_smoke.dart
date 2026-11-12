// Intentional use of window_manager 0.6's legacy facade during the
// staged nativeapi migration; remove after moving these callers to Window.
// ignore_for_file: deprecated_member_use

// יעד `flutter drive` לבדיקת ריבוי התצוגות באפליקציה האמיתית: binding אמיתי
// (לא של בדיקות), ולכן בעלי החלונות מותקן וחלונות Dart נפתחים באמת.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Pointer;
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/multiview/in_process_tab_drop.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/multiview/view_window_opener.dart';
import 'package:otzaria/core/windowing/multiview/view_window_registry.dart';
import 'package:otzaria/core/windowing/window_opener.dart';
import 'package:otzaria/main.dart' as app;
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';
import 'package:window_manager/legacy.dart';

const _toolId = 'builtin.measurements';

void main() {
  // בלי מצב נייד האפליקציה הייתה כותבת לפרופיל האמיתי (APPDATA) ומתנגשת במופע הפתוח.
  if (!AppPaths.isPortable) {
    enableFlutterDriverExtension(
      handler: (_) async => jsonEncode({
        'error':
            'portable.marker missing next to ${Platform.resolvedExecutable}',
      }),
    );
    return;
  }
  // הרמטי: סשן שנשאר מריצה קודמת משוחזר לחלון הראשי ומטה את הבדיקה.
  final data = Directory(
    p.join(p.dirname(Platform.resolvedExecutable), 'otzaria_data'),
  );
  if (data.existsSync()) data.deleteSync(recursive: true);
  enableFlutterDriverExtension(
    handler: _handle,
    enableTextEntryEmulation: false,
  );
  app.main(const []);
}

ViewWindowRegistry get _registry => ViewWindowOpener.instance.registry;

TabsBloc? _tabsOf(AppWindowKeys? keys) {
  final context = keys?.navigator.currentContext;
  if (context == null || !context.mounted) return null;
  return context.read<TabsBloc>();
}

TabsBloc? get _mainTabs => _tabsOf(AppWindowKeys.byId(AppWindowId.primary));

ViewWindowEntry? _view(int slot) =>
    _registry.windows.where((w) => w.slot == slot).firstOrNull;

Future<void> _until(bool Function() done, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('timed out waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

List<String> _toolTabs(TabsBloc? bloc) => [
  for (final tab in bloc?.state.tabs ?? const <OpenedTab>[])
    if (tab is ToolTab) tab.toolId,
];

Future<Map<String, Object?>> _state() async {
  return {
    'multiview': MultiViewMode.enabled,
    'ownerInstalled': MultiViewMode.ownerInstalled,
    'opener': WindowOpener.current.runtimeType.toString(),
    'mainReady': _mainTabs != null,
    'mainVisible': await windowManager.isVisible(),
    'mainToolTabs': _toolTabs(_mainTabs),
    'canOpenAnother': _registry.canOpenAnotherWindow,
    'maxWindows': ViewWindowRegistry.maxWindows,
    'views': [
      for (final w in _registry.windows)
        {
          'slot': w.slot,
          'hasHwnd': w.handle.hwnd != null,
          'visible':
              w.handle.hwnd != null &&
              IsWindowVisible(HWND(Pointer.fromAddress(w.handle.hwnd!))),
          'toolTabs': _toolTabs(_tabsOf(w.keys)),
        },
    ],
  };
}

Future<String> _handle(String? message) async {
  try {
    final request = jsonDecode(message ?? '{}') as Map<String, Object?>;
    final result = await _run(request);
    // פריים אחרי כל פעולה: החלון הראשי עדיין מצייר.
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    return jsonEncode({...result, 'state': await _state()});
  } catch (e, st) {
    Object? state;
    try {
      state = await _state();
    } catch (_) {}
    return jsonEncode({'error': '$e\n$st', 'state': state});
  }
}

Future<Map<String, Object?>> _run(Map<String, Object?> request) async {
  switch (request['type']) {
    case 'ready':
      await _until(() => _mainTabs != null, 'main window tree');
      return {};
    case 'state':
      return {};
    case 'open_empty':
      return {'ok': await WindowOpener.current.openEmptyWindow()};
    case 'move_main_tab_to_new_window':
      // כמו "העבר לחלון חדש" בתפריט הכרטיסיה: פתיחה עם הכרטיסיה ואז הסרה מהמקור.
      final main = _mainTabs!;
      main.add(AddTab(ToolTab(toolId: _toolId, title: 'מדות ושיעורים')));
      await _until(() => _toolTabs(main).contains(_toolId), 'tab in main');
      final tab = main.state.tabs.whereType<ToolTab>().first;
      final opened = await WindowOpener.current.openWindow(tab: tab);
      if (!opened) return {'ok': false};
      main.add(RemoveTab(tab));
      await _until(() => !_toolTabs(main).contains(_toolId), 'removal');
      return {'ok': true};
    case 'send_view_tab_to_main':
      // כמו "העבר לחלון" בתפריט הכרטיסיה, מחלון Dart אל הראשי.
      final entry = _view(request['slot']! as int)!;
      final bloc = _tabsOf(entry.keys)!;
      await _until(() => _toolTabs(bloc).isNotEmpty, 'tab in view');
      final tab = bloc.state.tabs.whereType<ToolTab>().first;
      final sent = await InProcessTabDrops.current.sendTabToWindow(
        InProcessTabDrops.mainSlot,
        tab,
      );
      if (sent == true) bloc.add(RemoveTab(tab));
      await _until(() => _toolTabs(_mainTabs).contains(_toolId), 'arrival');
      return {'ok': sent == true};
    case 'close_view':
      // WM_CLOSE אמיתי: עובר דרך ה-delegate של המסגרת ומסלול הסגירה של החלון.
      final slot = request['slot']! as int;
      final hwnd = _view(slot)!.handle.hwnd!;
      PostMessage(
        HWND(Pointer.fromAddress(hwnd)),
        WM_CLOSE,
        const WPARAM(0),
        const LPARAM(0),
      );
      await _until(() => _view(slot) == null, 'view $slot destroyed');
      return {'ok': true};
    case 'fill_to_cap':
      var opened = 0;
      while (_registry.canOpenAnotherWindow) {
        if (!await WindowOpener.current.openWindow()) break;
        opened++;
      }
      return {
        'opened': opened,
        'pastCap': await WindowOpener.current.openWindow(),
      };
    case 'close_all_views':
      for (final w in _registry.windows) {
        PostMessage(
          HWND(Pointer.fromAddress(w.handle.hwnd!)),
          WM_CLOSE,
          const WPARAM(0),
          const LPARAM(0),
        );
      }
      await _until(() => _registry.windows.isEmpty, 'all views destroyed');
      return {'ok': true};
  }
  throw ArgumentError('unknown request: ${request['type']}');
}
