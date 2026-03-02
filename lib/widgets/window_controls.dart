import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/utils/fullscreen_helper.dart';
import 'package:otzaria/settings/settings_exports.dart';

class WindowControls extends StatefulWidget {
  const WindowControls({super.key});

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreFullscreenStatus();
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() async {
    if (!mounted) return;
    final settingsBloc = context.read<SettingsBloc>();
    if (!settingsBloc.state.isFullscreen) {
      settingsBloc.add(const UpdateIsFullscreen(true));
    }
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
  }

  @override
  void onWindowLeaveFullScreen() async {
    if (!mounted) return;
    final settingsBloc = context.read<SettingsBloc>();
    if (settingsBloc.state.isFullscreen) {
      settingsBloc.add(const UpdateIsFullscreen(false));
    }
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
  }

  Future<void> _restoreFullscreenStatus() async {
    if (!mounted) return;
    final settingsState = context.read<SettingsBloc>().state;
    if (settingsState.isFullscreen) {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    }
    await windowManager.setFullScreen(settingsState.isFullscreen);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => windowManager.minimize(),
              icon: const Icon(FluentIcons.subtract_24_regular),
              tooltip: 'מזער',
            ),
            IconButton(
              onPressed: () async {
                final newFullscreenState = !settingsState.isFullscreen;
                await FullscreenHelper.toggleFullscreen(
                    context, newFullscreenState);
              },
              icon: Icon(settingsState.isFullscreen
                  ? FluentIcons.full_screen_minimize_24_regular
                  : FluentIcons.full_screen_maximize_24_regular),
              tooltip: settingsState.isFullscreen ? 'צא ממסך מלא' : 'מסך מלא',
            ),
            IconButton(
              onPressed: () => windowManager.close(),
              icon: const Icon(FluentIcons.dismiss_24_regular),
              tooltip: 'סגור',
            ),
          ],
        );
      },
    );
  }
}