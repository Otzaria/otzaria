import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';

/// שורת הגדרה לבחירת צבע בסיס.
///
/// מציגה את הצבע הנבחר ואת שמו. בלחיצה נפתח דיאלוג עם עיגולי הצבע.
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

  String _colorName(BuildContext context) => context.settingsText(
    AppSeedColors.nameOf(currentColor) ?? 'צבע מותאם אישית',
  );

  void _showPicker(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: settingsDialogBuilder(
        context,
        (_) => _ColorPickerDialog(
          currentColor: currentColor,
          defaultColor: defaultColor,
          onChanged: onChanged,
        ),
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

  String get _selectedName => context.settingsText(
    AppSeedColors.nameOf(_selected) ?? 'צבע מותאם אישית',
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppDialogFrame(
      backgroundColor: cs.surfaceContainerHigh,
      title: context.settingsText('בחר צבע בסיס'),
      icon: FluentIcons.color_24_regular,
      width: 460,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: AppSeedColors.swatchOf(_selected),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppTokens.spaceSM),
          Text(
            _selectedName,
            style: TextStyle(
              fontSize: AppTokens.fontMD,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        ActionButton.recommended(
          onPressed: () => Navigator.of(context).pop(),
          text: context.settingsText('סגור'),
        ),
      ],
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.settingsText('בחר בצבע ברירת מחדל'),
                    style: const TextStyle(fontSize: AppTokens.fontMD),
                  ),
                ),
                ActionButton.neutral(
                  onPressed: () => _select(widget.defaultColor),
                  icon: FluentIcons.arrow_reset_24_regular,
                  text: context.settingsText('איפוס'),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.spaceMD),
            // רוחב קבוע: מספר העיגולים בשורה לא תלוי באורך הכותרת בשפה אחרת.
            Center(
              child: SizedBox(
                width: 320,
                // לוח הצבעים אינו טקסט — כיוון קבוע כדי שסדר העיגולים לא יתהפך
                // כשההגדרות מוצגות בשפה LTR.
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Wrap(
                    spacing: AppTokens.spaceSM,
                    runSpacing: AppTokens.spaceSM,
                    alignment: WrapAlignment.center,
                    children: AppSeedColors.options.map((entry) {
                      final isSelected =
                          _selected.toARGB32() == entry.color.toARGB32();
                      return Tooltip(
                        message: context.settingsText(entry.name),
                        child: GestureDetector(
                          onTap: () => _select(entry.color),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppSeedColors.swatchOf(entry.color),
                              shape: BoxShape.circle,
                              border: isSelected
                                  ? Border.all(color: cs.onSurface, width: 3)
                                  : null,
                            ),
                            child: isSelected
                                ? const Icon(
                                    FluentIcons.checkmark_24_regular,
                                    color: Colors.white,
                                    size: 20,
                                  )
                                : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
