import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';

/// שורת הגדרה לבחירת צבע בסיס.
///
/// מציגה את הצבע הנבחר ושמו בעברית. בלחיצה נפתח דיאלוג עם עיגולי הצבע.
class ColorPickerTile extends StatelessWidget {
  final Color currentColor;
  final Color defaultColor;
  final ValueChanged<Color> onChanged;

  const ColorPickerTile({
    super.key,
    required this.currentColor,
    required this.defaultColor,
    required this.onChanged,
  });

  String _colorName(BuildContext context) =>
      AppSeedColors.nameOf(currentColor) ??
      context.settingsText('צבע מותאם אישית');

  void _showPicker(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _ColorPickerDialog(
        currentColor: currentColor,
        defaultColor: defaultColor,
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      hoverColor: Colors.transparent,
      leading: const Icon(FluentIcons.color_24_regular),
      title: Text(context.settingsText('צבע בסיס')),
      subtitle: Text(
        _colorName(context),
        style: AppTextStyles.settingSubtitle,
      ),
      trailing: FilledButton(
        onPressed: () => _showPicker(context),
        child: Text(context.settingsText('שינוי צבע')),
      ),
    );
  }
}

class _ColorPickerDialog extends StatefulWidget {
  final Color currentColor;
  final Color defaultColor;
  final ValueChanged<Color> onChanged;

  const _ColorPickerDialog({
    required this.currentColor,
    required this.defaultColor,
    required this.onChanged,
  });

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late Color _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentColor;
  }

  void _select(Color color) {
    setState(() => _selected = color);
    widget.onChanged(color);
  }

  String get _selectedName =>
      AppSeedColors.nameOf(_selected) ??
      context.settingsText('צבע מותאם אישית');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: cs.surfaceContainerHigh,
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // שורת כותרת — RTL: צבע נבחר בשמאל, כותרת בימין
          Row(
            children: [
              Text(context.settingsText('בחר צבע בסיס')),
              const Spacer(),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: _selected,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppTokens.spaceSM),
              Text(
                _selectedName,
                style: TextStyle(
                  fontSize: AppTokens.fontMD,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceMD),
          // כפתור ברירת מחדל — מתחת לכותרת, טקסט בימין וכפתור בסוף השורה
          Row(
            children: [
              Text(
                context.settingsText('בחר בצבע ברירת מחדל'),
                style: const TextStyle(
                  fontSize: AppTokens.fontMD,
                  fontWeight: FontWeight.normal,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => _select(widget.defaultColor),
                icon: const Icon(FluentIcons.arrow_reset_24_regular, size: 16),
                label: Text(context.settingsText('איפוס')),
              ),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Wrap(
            spacing: AppTokens.spaceSM,
            runSpacing: AppTokens.spaceSM,
            alignment: WrapAlignment.center,
            children: AppSeedColors.options.map((entry) {
              final isSelected = _selected.toARGB32() == entry.color.toARGB32();
              return Tooltip(
                message: entry.name,
                child: GestureDetector(
                  onTap: () => _select(entry.color),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: entry.color,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: cs.onSurface, width: 3)
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.settingsText('סגור')),
        ),
      ],
    );
  }
}
