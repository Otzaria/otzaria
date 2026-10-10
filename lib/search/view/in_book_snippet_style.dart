import 'package:otzaria/theme/app_fonts.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

/// The text styles of a result snippet in the in-book search panes.
class InBookSnippetStyle {
  InBookSnippetStyle(BuildContext context, SettingsState settings)
    : text = TextStyle(
        fontSize: 16,
        fontFamily: AppFonts.renderFontFamily(settings.fontFamily),
        color: Theme.of(context).colorScheme.onSurface,
        height: 1.5,
      ),
      highlight = TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 18,
        color: Theme.of(context).colorScheme.error,
      );

  /// The style of the snippet's text.
  final TextStyle text;

  /// The style of the matches in it.
  final TextStyle highlight;
}

/// [text] with the holy names written as [settings] ask, for the result
/// snippets and headers of the in-book search panes.
String withHolyNamesSetting(String text, SettingsState settings) =>
    settings.replaceHolyNames
    ? utils.replaceHolyNames(text, style: settings.holyNameStyle)
    : text;
