import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

/// שדה חיפוש בהגדרות, מעל אזור התוכן.
class SettingsSearchField extends StatefulWidget {
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
  State<SettingsSearchField> createState() => _SettingsSearchFieldState();
}

class _SettingsSearchFieldState extends State<SettingsSearchField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.isNotEmpty;

    return OtzariaSearchField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      onChanged: widget.onChanged,
      slim: true,
      hintText: context.settingsText('חיפוש בהגדרות'),
      // גלגל השיניים שבתוך העדשה נמרח לכתם ב-18 הפיקסלים של שדה החיפוש;
      // בגודל הזה זכוכית פשוטה היא האייקון הקריא (issue #1205).
      icon: OtzariaIcons.search_24_regular,
      trailingActions: [
        if (hasText)
          OtzariaSearchAction.icon(
            iconData: FluentIcons.dismiss_24_regular,
            tooltip: context.settingsText('נקה חיפוש'),
            onPressed: () {
              widget.controller.clear();
              widget.onChanged('');
              widget.onClear?.call();
            },
          ),
      ],
    );
  }
}
