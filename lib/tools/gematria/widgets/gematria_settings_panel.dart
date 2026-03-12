// lib/tools/gematria/widgets/gematria_settings_panel.dart
//
// פאנל הגדרות גימטריה — מוצג/מוסתר עם אנימציה מצד ימין של המסך.
// הוצא מ-gematria_search_screen.dart לרכיב עצמאי.

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';

class GematriaSettingsPanel extends StatelessWidget {
  final bool isVisible;

  /// קריאה לסגירת/פתיחת הפאנל
  final VoidCallback onToggle;

  static const double _panelWidth = 400.0;

  const GematriaSettingsPanel({
    super.key,
    required this.isVisible,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppTokens.animSlow,
      curve: Curves.easeInOut,
      width: isVisible ? _panelWidth : 0,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerRight,
          maxWidth: _panelWidth,
          minWidth: 0,
          child: Container(
            width: _panelWidth,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                _PanelHeader(onToggle: onToggle),
                const Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(AppTokens.spaceMD),
                    child: GematriaSettingsTab(),
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

// ─── Panel header ─────────────────────────────────────────────────────────────

class _PanelHeader extends StatelessWidget {
  final VoidCallback onToggle;
  const _PanelHeader({required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceMD),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(FluentIcons.settings_24_regular),
            tooltip: 'סגור הגדרות',
            onPressed: onToggle,
          ),
          const Spacer(),
          const Text(
            'הגדרות גימטריה',
            style: TextStyle(
              fontSize: AppTokens.fontXL,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
