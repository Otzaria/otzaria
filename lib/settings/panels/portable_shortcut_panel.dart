import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/portable_host_shortcut.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// כרטיס "גרסה ניידת": קיצור דרך במחשב הזה.
/// מוצג רק בעותק נייד ב-Windows שנבנה עם המפעיל.
class PortableShortcutPanel extends StatefulWidget {
  const PortableShortcutPanel({super.key, this.shortcut});

  /// ברירת המחדל: [PortableHostShortcut.forCurrentProcess].
  final PortableHostShortcut? shortcut;

  @override
  State<PortableShortcutPanel> createState() => _PortableShortcutPanelState();
}

class _PortableShortcutPanelState extends State<PortableShortcutPanel> {
  late final PortableHostShortcut? _shortcut =
      widget.shortcut ?? PortableHostShortcut.forCurrentProcess();
  bool _available = false;
  PortableShortcutState _state = PortableShortcutState.none;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final shortcut = _shortcut;
    if (shortcut == null || !await shortcut.isAvailable()) return;
    final state = await shortcut.state();
    if (!mounted) return;
    setState(() {
      _available = true;
      _state = state;
    });
  }

  Future<void> _run(Future<void> Function(PortableHostShortcut) action) async {
    setState(() => _busy = true);
    try {
      await action(_shortcut!);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _create(PortableHostShortcut shortcut) async {
    final result = await shortcut.create();
    if (result == PortableShortcutResult.created) {
      UiSnack.show(SettingsMessages.portableShortcutCreated);
    } else {
      UiSnack.showError(SettingsMessages.portableShortcutFailed);
    }
  }

  Future<void> _remove(PortableHostShortcut shortcut) async {
    if (!await shortcut.remove()) {
      UiSnack.showError(SettingsMessages.portableShortcutRemoveFailed);
      return;
    }
    UiSnack.show(SettingsMessages.portableShortcutRemoved);
  }

  @override
  Widget build(BuildContext context) {
    final shortcut = _shortcut;
    if (!_available || shortcut == null) return const SizedBox.shrink();
    return SettingsCard(
      cardId: 'system.portable',
      title: context.settingsText('גרסה ניידת'),
      subtitle: context.settingsText(
        'אוצריא רצה מהתיקייה שלה, בלי התקנה, ושומרת לידה את כל הנתונים',
      ),
      children: [
        SettingsActionTile.text(
          key: const ValueKey('portable-host-shortcut'),
          icon: FluentIcons.desktop_24_regular,
          title: context.settingsText('קיצור דרך במחשב הזה'),
          subtitle: switch (_state) {
            PortableShortcutState.none => context.settingsText(
              'סמל בשולחן העבודה שפותח את אוצריא מהדיסק, גם כשהמחשב נותן לדיסק אות אחרת',
            ),
            PortableShortcutState.thisCopy => context.settingsText(
              'בשולחן העבודה ובתפריט התחל יש קיצור "אוצריא (נייד)" שפותח את העותק הזה',
            ),
            PortableShortcutState.otherCopy => context.settingsText(
              'הקיצור במחשב הזה פותח עותק נייד אחר של אוצריא',
            ),
          },
          actions: [
            if (_state == PortableShortcutState.thisCopy)
              ActionButton.neutral(
                text: context.settingsText('הסר'),
                isLoading: _busy,
                onPressed: _busy ? null : () => _run(_remove),
              )
            else
              ActionButton.recommended(
                text: _state == PortableShortcutState.none
                    ? context.settingsText('צור קיצור')
                    : context.settingsText('החלף', context: 'shortcut'),
                isLoading: _busy,
                onPressed: _busy ? null : () => _run(_create),
              ),
          ],
        ),
      ],
    );
  }
}
