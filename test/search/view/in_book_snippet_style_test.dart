import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/view/in_book_snippet_style.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

void main() {
  group('withHolyNamesSetting', () {
    const text = 'ויאמר יהוה אל משה';

    test('replaces the holy names when the setting asks', () {
      final settings = SettingsState.initial().copyWith(replaceHolyNames: true);
      expect(
        withHolyNamesSetting(text, settings),
        utils.replaceHolyNames(text, style: settings.holyNameStyle),
      );
    });

    test('keeps the text as is otherwise', () {
      final settings = SettingsState.initial().copyWith(
        replaceHolyNames: false,
      );
      expect(withHolyNamesSetting(text, settings), text);
    });
  });

  testWidgets('InBookSnippetStyle highlights in bold and larger', (
    tester,
  ) async {
    late InBookSnippetStyle style;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            style = InBookSnippetStyle(context, SettingsState.initial());
            return const SizedBox();
          },
        ),
      ),
    );

    expect(style.text.fontSize, 16);
    expect(style.highlight.fontSize, 18);
    expect(style.highlight.fontWeight, FontWeight.bold);
  });
}
