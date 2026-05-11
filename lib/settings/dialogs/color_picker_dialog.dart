import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/theme_exports.dart';

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

  String get _colorName =>
      AppSeedColors.nameOf(currentColor) ?? 'צבע מותאם אישית';

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
      title: const Text('צבע בסיס', textDirection: TextDirection.rtl),
      subtitle: Text(
        _colorName,
        textDirection: TextDirection.rtl,
        style: AppTextStyles.settingSubtitle,
      ),
      trailing: FilledButton(
        onPressed: () => _showPicker(context),
        child: const Text('שינוי צבע', textDirection: TextDirection.rtl),
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
      AppSeedColors.nameOf(_selected) ?? 'צבע מותאם אישית';

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
            textDirection: TextDirection.rtl,
            children: [
              const Text('בחר צבע בסיס', textDirection: TextDirection.rtl),
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
                textDirection: TextDirection.rtl,
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
            textDirection: TextDirection.rtl,
            children: [
              const Text(
                'בחר בצבע ברירת מחדל',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: AppTokens.fontMD,
                  fontWeight: FontWeight.normal,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => _select(widget.defaultColor),
                icon: const Icon(FluentIcons.arrow_reset_24_regular, size: 16),
                label: const Text('איפוס', textDirection: TextDirection.rtl),
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
          child: const Text('סגור'),
        ),
      ],
    );
  }
}
