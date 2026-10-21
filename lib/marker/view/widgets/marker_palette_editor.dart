import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/marker/models/marker_palette.dart';
import 'package:otzaria/marker/services/marker_settings.dart';
import 'package:otzaria/settings/l10n/settings_dialog_scope.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/theme/marker_colors.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// נפתח מההגדרות, ולכן בשפה ובכיווניות שלהן; התוכן נגלל בחלון נמוך.
Future<void> showMarkerPaletteEditor(BuildContext context) => showDialog<void>(
  context: context,
  builder: settingsDialogBuilder(
    context,
    (dialogContext) => AppDialog.singleAction(
      title: dialogContext.settingsText('צבעי המרקר'),
      confirmText: dialogContext.settingsText('סגירה'),
      customContent: const SizedBox(
        width: 560,
        child: SingleChildScrollView(child: MarkerPaletteEditor()),
      ),
    ),
  ),
);

/// עריכת פלטת המרקר. כל שינוי נשמר מיד; הסדר כאן הוא סדר התפריט בקורא.
/// שינוי צבע חל מיד גם על כל הסימונים שכבר צוירו בו.
class MarkerPaletteEditor extends StatelessWidget {
  const MarkerPaletteEditor({super.key});

  static const List<double> _opacities = [0.35, 0.5, 0.65, 0.8, 1];

  @override
  Widget build(BuildContext context) {
    final settings = MarkerSettings.instance;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final palette = settings.palette;
        void save(List<MarkerColor> colors, {String? defaultColorId}) =>
            settings.setPalette(
              MarkerPalette(
                colors: colors,
                defaultColorId: defaultColorId ?? palette.defaultColorId,
              ),
            );
        void replace(int index, MarkerColor color) =>
            save([...palette.colors]..[index] = color);
        void move(int index, int delta) {
          final colors = [...palette.colors];
          final color = colors.removeAt(index);
          colors.insert(index + delta, color);
          save(colors);
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.settingsText(
                'רק שמונת הצבעים הראשונים שמופעלים מוצגים בתפריט.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < palette.colors.length; i++)
              _ColorRow(
                key: ValueKey(palette.colors[i].id),
                color: palette.colors[i],
                isDefault: palette.colors[i].id == palette.defaultColorId,
                canMoveUp: i > 0,
                canMoveDown: i < palette.colors.length - 1,
                canDelete: palette.colors.length > 1,
                opacities: _opacities,
                onChanged: (color) => replace(i, color),
                onMakeDefault: () =>
                    save(palette.colors, defaultColorId: palette.colors[i].id),
                onMoveUp: () => move(i, -1),
                onMoveDown: () => move(i, 1),
                onDelete: () async {
                  final confirmed = await showWarningDialog(
                    context: context,
                    title: context.settingsText('מחיקת צבע'),
                    content: context.settingsText(
                      'למחוק את הצבע? סימונים בצבע הזה יישמרו בצבע שהיה להם.',
                    ),
                    confirmText: context.settingsText('מחיקה'),
                    cancelText: context.settingsText('ביטול'),
                  );
                  if (confirmed == true) {
                    save([...palette.colors]..removeAt(i));
                  }
                },
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (palette.colors.length < MarkerPalette.maxColors)
                  ActionButton.recommended(
                    text: context.settingsText('הוספת צבע'),
                    onPressed: () => save([
                      ...palette.colors,
                      MarkerColor(
                        id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
                        label: context.settingsText('צבע חדש'),
                        hex: MarkerColor.hexOf(
                          MarkerColors
                              .presets[palette.colors.length %
                                  MarkerColors.presets.length]
                              .toARGB32(),
                        ),
                        enabled:
                            palette.menuColors.length <
                            MarkerPalette.maxMenuColors,
                      ),
                    ]),
                  ),
                ActionButton.ghost(
                  text: context.settingsText('איפוס לברירת המחדל'),
                  onPressed: () async {
                    final confirmed = await showWarningDialog(
                      context: context,
                      title: context.settingsText('איפוס הצבעים'),
                      content: context.settingsText(
                        'להחזיר את צבעי ברירת המחדל? צבעים שהוספתם או שיניתם '
                        'יימחקו, והסימונים עצמם יישארו.',
                      ),
                      confirmText: context.settingsText('איפוס'),
                      cancelText: context.settingsText('ביטול'),
                    );
                    if (confirmed == true) {
                      await settings.setPalette(MarkerPalette.defaults());
                    }
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ColorRow extends StatefulWidget {
  final MarkerColor color;
  final bool isDefault;
  final bool canMoveUp;
  final bool canMoveDown;
  final bool canDelete;
  final List<double> opacities;
  final ValueChanged<MarkerColor> onChanged;
  final VoidCallback onMakeDefault;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;

  const _ColorRow({
    super.key,
    required this.color,
    required this.isDefault,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.canDelete,
    required this.opacities,
    required this.onChanged,
    required this.onMakeDefault,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
  });

  @override
  State<_ColorRow> createState() => _ColorRowState();
}

class _ColorRowState extends State<_ColorRow> {
  late final TextEditingController _label = TextEditingController(
    text: widget.color.label,
  );
  final FocusNode _labelFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _labelFocus.addListener(() {
      if (!_labelFocus.hasFocus) _commitLabel();
    });
  }

  @override
  void didUpdateWidget(covariant _ColorRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // שינוי מחלון אחר אינו דורס הקלדה שבאמצע.
    if (!_labelFocus.hasFocus && widget.color.label != _label.text) {
      _label.text = widget.color.label;
    }
  }

  @override
  void dispose() {
    _labelFocus.dispose();
    _label.dispose();
    super.dispose();
  }

  void _commitLabel() {
    final label = MarkerColor.normalizeLabel(_label.text);
    if (label != widget.color.label) {
      widget.onChanged(widget.color.copyWith(label: label));
    }
  }

  Future<void> _askHex() async {
    final controller = TextEditingController(text: widget.color.hex);
    try {
      final confirmed = await showTwoActionsDialog(
        context: context,
        title: context.settingsText('קוד צבע'),
        content: '',
        confirmText: context.settingsText('שמירה'),
        cancelText: context.settingsText('ביטול'),
        customContent: RtlTextField(
          controller: controller,
          autofocus: true,
          inputFormatters: [LengthLimitingTextInputFormatter(7)],
          decoration: InputDecoration(
            helperText: context.settingsText('בתבנית #RRGGBB'),
          ),
        ),
      );
      final hex = MarkerColor.normalizeHex(controller.text);
      if (confirmed == true && hex != null) {
        widget.onChanged(widget.color.copyWith(hex: hex));
      }
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final cs = Theme.of(context).colorScheme;
    final modeLabels = {
      MarkerStyleMode.background: context.settingsText('רקע לטקסט'),
      MarkerStyleMode.underline: context.settingsText('קו תחתון'),
      MarkerStyleMode.box: context.settingsText('מסגרת'),
      MarkerStyleMode.text: context.settingsText('צבע לטקסט'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 4,
        children: [
          AppPopupMenuButton<String>(
            tooltip: context.settingsText('בחירת גוון'),
            icon: Icon(
              FluentIcons.circle_24_filled,
              color: Color(color.argb),
              semanticLabel: color.label,
            ),
            onSelected: (value) => value == 'custom'
                ? _askHex()
                : widget.onChanged(color.copyWith(hex: value)),
            entries: [
              for (final preset in MarkerColors.presets)
                AppMenuEntry(
                  value: MarkerColor.hexOf(preset.toARGB32()),
                  label: MarkerColor.hexOf(preset.toARGB32()),
                  icon: FluentIcons.circle_24_filled,
                  iconColor: preset,
                  labelWidget: Row(
                    children: [
                      Text(
                        MarkerColor.hexOf(preset.toARGB32()),
                        textDirection: TextDirection.ltr,
                      ),
                    ],
                  ),
                ),
              AppMenuEntry(
                value: 'custom',
                label: context.settingsText('קוד צבע…'),
              ),
            ],
          ),
          SizedBox(
            width: 140,
            child: RtlTextField(
              controller: _label,
              focusNode: _labelFocus,
              inputFormatters: [
                LengthLimitingTextInputFormatter(MarkerColor.maxLabelLength),
              ],
              decoration: InputDecoration(
                hintText: context.settingsText('שם הצבע'),
                isDense: true,
              ),
              onSubmitted: (_) => _commitLabel(),
            ),
          ),
          AppPopupMenuButton<MarkerStyleMode>(
            tooltip: modeLabels[color.mode],
            iconData: FluentIcons.paint_brush_24_regular,
            initialValue: color.mode,
            onSelected: (mode) => widget.onChanged(color.copyWith(mode: mode)),
            entries: [
              for (final mode in MarkerStyleMode.values)
                AppMenuEntry(value: mode, label: modeLabels[mode]!),
            ],
          ),
          AppPopupMenuButton<double>(
            tooltip: context.settingsText('אטימות'),
            iconData: FluentIcons.color_background_24_regular,
            initialValue: color.opacity,
            onSelected: (opacity) =>
                widget.onChanged(color.copyWith(opacity: opacity)),
            entries: [
              for (final opacity in widget.opacities)
                AppMenuEntry(
                  value: opacity,
                  label: '${(opacity * 100).round()}%',
                ),
            ],
          ),
          Tooltip(
            message: context.settingsText('מוצג בתפריט'),
            child: Switch(
              value: color.enabled,
              onChanged: (enabled) =>
                  widget.onChanged(color.copyWith(enabled: enabled)),
            ),
          ),
          IconButton(
            tooltip: widget.isDefault
                ? context.settingsText('צבע ברירת המחדל')
                : context.settingsText('קביעה כברירת מחדל'),
            onPressed: color.enabled && !widget.isDefault
                ? widget.onMakeDefault
                : null,
            icon: Icon(
              widget.isDefault
                  ? FluentIcons.star_24_filled
                  : FluentIcons.star_24_regular,
              color: widget.isDefault ? cs.primary : null,
            ),
          ),
          IconButton(
            tooltip: context.settingsText('הזזה למעלה'),
            onPressed: widget.canMoveUp ? widget.onMoveUp : null,
            icon: const Icon(FluentIcons.arrow_up_24_regular),
          ),
          IconButton(
            tooltip: context.settingsText('הזזה למטה'),
            onPressed: widget.canMoveDown ? widget.onMoveDown : null,
            icon: const Icon(FluentIcons.arrow_down_24_regular),
          ),
          IconButton(
            tooltip: context.settingsText('מחיקת הצבע'),
            onPressed: widget.canDelete ? widget.onDelete : null,
            icon: const Icon(FluentIcons.delete_24_regular),
          ),
        ],
      ),
    );
  }
}
