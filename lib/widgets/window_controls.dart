import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:window_manager/window_manager.dart';

class WindowControls extends StatefulWidget {
  const WindowControls({super.key});

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> {
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    _checkFullscreenStatus();
  }

  Future<void> _checkFullscreenStatus() async {
    final isFullscreen = await windowManager.isFullScreen();
    if (mounted) {
      setState(() {
        _isFullscreen = isFullscreen;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
            setState(() {
              _isFullscreen = !_isFullscreen;
            });
            await windowManager.setFullScreen(_isFullscreen);
          },
          icon: Icon(_isFullscreen ? FluentIcons.full_screen_minimize_24_regular : FluentIcons.full_screen_maximize_24_regular),
          tooltip: _isFullscreen ? 'צא ממסך מלא' : 'מסך מלא',
        ),
        IconButton(
          onPressed: () => windowManager.close(),
          icon: const Icon(FluentIcons.dismiss_24_regular),
          tooltip: 'סגור',
        ),
      ],
    );
  }
}
