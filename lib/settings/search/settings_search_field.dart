import 'package:flutter/material.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

/// שדה חיפוש בהגדרות, מעל אזור התוכן.
class SettingsSearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  const SettingsSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.focusNode,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return OtzariaSearchField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      slim: true,
      hintText: context.settingsText('חיפוש בהגדרות'),
      icon: OtzariaIcons.search_in_settings_24_regular,
      onClear: () {
        onChanged('');
        onClear?.call();
      },
    );
  }
}
