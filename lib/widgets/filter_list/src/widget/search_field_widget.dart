import '../theme/filter_list_theme.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

class SearchFieldWidget<T> extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const SearchFieldWidget({
    super.key,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final headerTheme = FilterListTheme.of(context).headerTheme;
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius:
              BorderRadius.circular(headerTheme.searchFieldBorderRadius),
          color: headerTheme.searchFieldBackgroundColor,
        ),
        child: TextField(
          onChanged: onChanged,
          style: headerTheme.searchFieldTextStyle,
          decoration: InputDecoration(
            prefixIcon:
                Icon(FluentIcons.search_24_regular, color: headerTheme.searchFieldIconColor),
            hintText: headerTheme.searchFieldHintText,
            hintStyle: headerTheme.searchFieldHintTextStyle,
            border: headerTheme.searchFieldInputBorder,
          ),
        ),
      ),
    );
  }
}
