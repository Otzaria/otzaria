import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/settings/settings_card.dart';

/// טאב הגדרות עורך הספרים
class EditorSettingsTab extends StatefulWidget {
  const EditorSettingsTab({super.key});

  @override
  State<EditorSettingsTab> createState() => _EditorSettingsTabState();
}

class _EditorSettingsTabState extends State<EditorSettingsTab> {
  late double previewDebounce;
  late double cleanupDays;
  late double draftsQuota;

  @override
  void initState() {
    super.initState();
    previewDebounce =
        Settings.getValue<double>('key-editor-preview-debounce') ?? 150.0;
    cleanupDays =
        Settings.getValue<double>('key-editor-draft-cleanup-days') ?? 30.0;
    draftsQuota = Settings.getValue<double>('key-editor-drafts-quota') ?? 100.0;
  }

  @override
  Widget build(BuildContext context) {
    // [תיקון] הסרת SingleChildScrollView — ToolsSettingsTab גולל את הכל
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsCard(
            title: 'עורך הספרים',
            children: [
              _buildSlider(
                icon: FluentIcons.timer_24_regular,
                label: 'זמן עיכוב במילישניות',
                value: previewDebounce,
                min: 50,
                max: 300,
                divisions: 5,
                onChanged: (value) {
                  setState(() => previewDebounce = value);
                  Settings.setValue<double>(
                      'key-editor-preview-debounce', value);
                },
              ),
              _buildSlider(
                icon: FluentIcons.delete_dismiss_24_regular,
                label: 'ניקוי טיוטות ישנות (ימים)',
                value: cleanupDays,
                min: 7,
                max: 90,
                divisions: 12,
                onChanged: (value) {
                  setState(() => cleanupDays = value);
                  Settings.setValue<double>(
                      'key-editor-draft-cleanup-days', value);
                },
              ),
              _buildSlider(
                icon: FluentIcons.database_24_regular,
                label: 'מכסת טיוטות (MB)',
                value: draftsQuota,
                min: 50,
                max: 100,
                divisions: 5,
                onChanged: (value) {
                  setState(() => draftsQuota = value);
                  Settings.setValue<double>('key-editor-drafts-quota', value);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSlider({
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(
                child:
                    Text(label, style: Theme.of(context).textTheme.titleMedium),
              ),
              Text(
                '${value.toInt()}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: value.toInt().toString(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
