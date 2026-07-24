import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

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
    final colorScheme = Theme.of(context).colorScheme;
    final hasText = widget.controller.text.isNotEmpty;

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: AppTokens.borderRadiusAll,
        border: Border.all(
          color: colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: RtlTextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        onChanged: widget.onChanged,
        style: const TextStyle(fontSize: 13),
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: 'חיפוש בהגדרות',
          hintStyle: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurfaceVariant,
          ),
          prefixIcon: Icon(
            FluentIcons.search_24_regular,
            color: colorScheme.onSurfaceVariant,
            size: 16,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 32,
            minHeight: 32,
          ),
          suffixIcon: hasText
              ? IconButton(
                  icon: const Icon(FluentIcons.dismiss_24_regular, size: 14),
                  tooltip: 'נקה חיפוש',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  onPressed: () {
                    widget.controller.clear();
                    widget.onChanged('');
                    widget.onClear?.call();
                  },
                )
              : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 28,
            minHeight: 28,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 6,
          ),
          isDense: true,
        ),
        textAlign: TextAlign.right,
      ),
    );
  }
}
