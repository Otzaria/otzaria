import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';

void main() {
  Future<ButtonStyle?> pumpIconButton(
    WidgetTester tester, {
    required Brightness brightness,
    required bool selected,
    ToolbarActionButtonEmphasis emphasis =
        ToolbarActionButtonEmphasis.prominent,
  }) async {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.brown,
        brightness: brightness,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: ToolbarActionButton(
            tooltip: 'בדיקה',
            icon: FluentIcons.book_24_regular,
            selected: selected,
            emphasis: emphasis,
            onPressed: () {},
          ),
        ),
      ),
    );

    final iconButton = tester.widget<IconButton>(find.byType(IconButton));
    return iconButton.style;
  }

  testWidgets('selected state in light mode uses primary and onPrimary',
      (tester) async {
    final lightScheme = ColorScheme.fromSeed(
      seedColor: Colors.brown,
      brightness: Brightness.light,
    );
    final selectedStyle = await pumpIconButton(
      tester,
      brightness: Brightness.light,
      selected: true,
    );
    final unselectedStyle = await pumpIconButton(
      tester,
      brightness: Brightness.light,
      selected: false,
    );

    final selectedBg =
        selectedStyle!.backgroundColor!.resolve(<WidgetState>{})!;
    final selectedFg = selectedStyle.foregroundColor!.resolve(<WidgetState>{})!;
    final unselectedBg =
        unselectedStyle!.backgroundColor!.resolve(<WidgetState>{})!;

    expect(selectedBg, lightScheme.primary);
    expect(selectedFg, lightScheme.onPrimary);
    expect(unselectedBg, Colors.transparent);
  });

  testWidgets('selected state in dark mode uses primary and onPrimary',
      (tester) async {
    final darkScheme = ColorScheme.fromSeed(
      seedColor: Colors.brown,
      brightness: Brightness.dark,
    );
    final selectedStyle = await pumpIconButton(
      tester,
      brightness: Brightness.dark,
      selected: true,
    );
    final unselectedStyle = await pumpIconButton(
      tester,
      brightness: Brightness.dark,
      selected: false,
    );

    final selectedFg =
        selectedStyle!.foregroundColor!.resolve(<WidgetState>{})!;
    final unselectedFg =
        unselectedStyle!.foregroundColor!.resolve(<WidgetState>{})!;
    final selectedBg = selectedStyle.backgroundColor!.resolve(<WidgetState>{})!;

    expect(selectedBg, darkScheme.primary);
    expect(selectedFg, darkScheme.onPrimary);
    expect(selectedFg, isNot(unselectedFg));
  });

  testWidgets('subtle selected state uses softened secondary container colors',
      (tester) async {
    final lightScheme = ColorScheme.fromSeed(
      seedColor: Colors.brown,
      brightness: Brightness.light,
    );
    final selectedStyle = await pumpIconButton(
      tester,
      brightness: Brightness.light,
      selected: true,
      emphasis: ToolbarActionButtonEmphasis.subtle,
    );

    final selectedBg =
        selectedStyle!.backgroundColor!.resolve(<WidgetState>{})!;
    final selectedFg = selectedStyle.foregroundColor!.resolve(<WidgetState>{})!;

    expect(
      selectedBg,
      lightScheme.secondaryContainer.withValues(alpha: 0.72),
    );
    expect(selectedFg, lightScheme.onSecondaryContainer);
  });
}
