import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/messages_exports.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/services/plugin_file_drop_service.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// סיומת קובץ התוסף הנקלט בגרירה.
const String _pluginExtension = '.otzplugin';

/// אזור שמקבל קובץ .otzplugin הנגרר מהמערכת ומתקין אותו.
class PluginDropZone extends StatefulWidget {
  final Widget child;

  const PluginDropZone({super.key, required this.child});

  @override
  State<PluginDropZone> createState() => _PluginDropZoneState();
}

class _PluginDropZoneState extends State<PluginDropZone>
    with PluginFileDropZoneBinding {
  PluginFileDropService get _service => dropService;

  bool _isHovering = false;

  static List<String> _pluginPaths(List<String> paths) => paths
      .where((path) => path.toLowerCase().endsWith(_pluginExtension))
      .toList();

  /// האם הסמן נמצא מעל אזור זה. הנתיבים מגיעים בפיקסלים פיזיים.
  bool _contains(Offset physicalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    if (ratio <= 0) return false;
    final local = box.globalToLocal(physicalPosition / ratio);
    return local.dx >= 0 &&
        local.dy >= 0 &&
        local.dx < box.size.width &&
        local.dy < box.size.height;
  }

  @override
  void onFileDragChanged() {
    final drag = _service.drag.value;
    final hovering =
        drag != null &&
        _pluginPaths(drag.paths).isNotEmpty &&
        _contains(drag.physicalPosition);
    _service.setZoneAccepting(this, hovering);
    if (hovering != _isHovering) setState(() => _isHovering = hovering);
  }

  @override
  Future<void> onFileDropped(PluginFileDrag drop) async {
    if (_isHovering) setState(() => _isHovering = false);
    if (!_contains(drop.physicalPosition)) return;

    final paths = _pluginPaths(drop.paths);
    if (paths.isEmpty) return;

    final verified = await verifySaferModePassword(context);
    if (!verified || !mounted) return;

    // ההתקנה פותחת דיאלוג הרשאות אחד — קבצים נוספים היו מתנגשים בו.
    if (paths.length > 1) UiSnack.show(PluginMessages.dropSinglePluginOnly);
    if (!mounted) return;
    context.read<PluginSystemBloc>().add(
      InstallPluginRequested(paths.first, isUserInitiated: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_isHovering)
          Positioned.fill(child: IgnorePointer(child: const _DropOverlay())),
      ],
    );
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppSurfaces.paneDropPreview(colorScheme),
        border: Border.all(
          color: AppSurfaces.paneDropPreviewBorder(colorScheme),
          width: 2,
        ),
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Center(
        // בחלונית צרה הטקסט היה נשבר לשורות וגולש מגובה האזור.
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  FluentIcons.arrow_download_24_regular,
                  size: 32,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  'שחרר כדי להתקין את התוסף',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
