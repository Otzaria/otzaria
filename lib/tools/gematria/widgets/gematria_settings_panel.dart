// lib/tools/gematria/widgets/gematria_settings_panel.dart
//
// שינויים:
//  • מסך צר (< 800): הפאנל נפתח כ-Overlay צד מהצד (Stack+Positioned) — לא דוחק תוכן
//  • מסך רחב: AnimatedContainer בצד ימין (כמו קודם)
//
// ה-Widget עצמו מחליט לפי LayoutBuilder.
// הקריאה: GematriaSettingsPanel(isVisible, onToggle) — ללא שינוי ב-API.

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';

class GematriaSettingsPanel extends StatelessWidget {
  final bool isVisible;
  final VoidCallback onToggle;

  static const double _panelWidth = 360.0;
  static const double _narrowBreakpoint = 800.0;

  const GematriaSettingsPanel({
    super.key,
    required this.isVisible,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // LayoutBuilder כאן מקבל את הרוחב הזמין לפאנל בתוך ה-Row.
        // במסך צר, GematriaSearchScreen שולח SizedBox(width: 0) כ-fallback,
        // וה-Overlay מופעל דרך Stack בשכבת הhero.
        // לכן אנו משתמשים ב-MediaQuery לבדיקת הרוחב האמיתי.
        final screenWidth = MediaQuery.of(context).size.width;
        final isNarrow = screenWidth < _narrowBreakpoint;

        if (isNarrow) {
          // במסך צר: הפאנל מנוהל ע"י GematriaSearchScreen דרך Stack.
          // Widget זה מחזיר SizedBox.shrink כאן.
          return const SizedBox.shrink();
        }

        return _buildWidePanel(context);
      },
    );
  }

  // ── פאנל רחב (AnimatedContainer) ──────────────────────────────────────────
  Widget _buildWidePanel(BuildContext context) {
    return AnimatedContainer(
      duration: AppTokens.animSlow,
      curve: Curves.easeInOut,
      width: isVisible ? _panelWidth : 0,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerRight,
          maxWidth: _panelWidth,
          minWidth: 0,
          child: SizedBox(
            width: _panelWidth,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: _buildPanelContent(context),
            ),
          ),
        ),
      ),
    );
  }

  // ── תוכן הפאנל (משותף לצר ולרחב) ─────────────────────────────────────────
  Widget buildNarrowOverlay(BuildContext context) {
    return _NarrowOverlayPanel(
      isVisible: isVisible,
      onToggle: onToggle,
      panelWidth: _panelWidth,
      content: _buildPanelContent(context),
    );
  }

  Widget _buildPanelContent(BuildContext context) {
    return Column(
      children: [
        // ── כותרת + כפתור X ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.spaceXS,
            AppTokens.spaceMD,
            AppTokens.spaceMD,
            0,
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(FluentIcons.dismiss_24_regular, size: 20),
                onPressed: onToggle,
                tooltip: 'סגור',
                style: IconButton.styleFrom(
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const Spacer(),
              Text(
                'הגדרות',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        // ── הגדרות גימטריה ────────────────────────────────────────────────
        const Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(AppTokens.spaceMD),
            child: GematriaSettingsTab(),
          ),
        ),
      ],
    );
  }
}

// ── Overlay panel (מסך צר) ─────────────────────────────────────────────────────
// ריצה עצמאית כ-AnimatedPositioned על גבי Stack בhגdמה שבהורה.

class _NarrowOverlayPanel extends StatelessWidget {
  final bool isVisible;
  final VoidCallback onToggle;
  final double panelWidth;
  final Widget content;

  const _NarrowOverlayPanel({
    required this.isVisible,
    required this.onToggle,
    required this.panelWidth,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final effectiveWidth = panelWidth.clamp(0.0, screenWidth * 0.88);

    return Stack(
      children: [
        // ── scrim (מחשיך את הרקע) ──────────────────────────────────────────
        if (isVisible)
          GestureDetector(
            onTap: onToggle,
            child: Container(
              color: Colors.black.withValues(alpha: 0.35),
            ),
          ),
        // ── הפאנל עצמו ──────────────────────────────────────────────────────
        AnimatedPositioned(
          duration: AppTokens.animSlow,
          curve: Curves.easeInOut,
          top: 0,
          bottom: 0,
          left: isVisible ? screenWidth - effectiveWidth : screenWidth,
          child: SizedBox(
            width: effectiveWidth,
            child: Material(
              elevation: 8,
              color: AppSurfaces.panelBackground(context),
              child: SafeArea(child: content),
            ),
          ),
        ),
      ],
    );
  }
}
