import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/layout/floating_panel.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

class PdfZoomBar extends StatelessWidget {
  final double currentZoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onResetZoom;

  const PdfZoomBar({
    super.key,
    required this.currentZoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onResetZoom,
  });

  @override
  Widget build(BuildContext context) {
    final zoomPercentage = (currentZoom * 100).round();
    final divider = Theme.of(context).colorScheme.outlineVariant;

    return FloatingPanel(
      color: AppSurfaces.card(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: AppTokens.borderRadiusAll,
          border: Border.all(
            color: divider,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // כפתור איפוס
            ActionButton.ghost(text: 'אפס', onPressed: onResetZoom),
            Container(
              width: 1,
              height: 24,
              color: divider,
              margin: const EdgeInsets.symmetric(horizontal: 4),
            ),
            // כפתור הגדלה
            IconButton(
              icon: const Icon(
                FluentIcons.add_24_regular,
                size: AppTokens.iconMD,
              ),
              onPressed: onZoomIn,
              tooltip: 'הגדל את התצוגה',
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
            ),
            Container(
              width: 1,
              height: 24,
              color: divider,
              margin: const EdgeInsets.symmetric(horizontal: 4),
            ),
            // כפתור הקטנה
            IconButton(
              icon: const Icon(
                FluentIcons.subtract_24_regular,
                size: AppTokens.iconMD,
              ),
              onPressed: onZoomOut,
              tooltip: 'הקטן את התצוגה',
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
            ),
            const SizedBox(width: 12),
            // תצוגת אחוזים
            SizedBox(
              width: 50,
              child: Text(
                '$zoomPercentage%',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
