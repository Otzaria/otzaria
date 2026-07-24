import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

void main() {
  testWidgets('Disabled app menu entries use muted foreground color', (
    tester,
  ) async {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: AppPopupMenuButton<String>(
                entries: const [
                  AppMenuEntry<String>(
                    value: 'copy',
                    label: 'העתק',
                    icon: FluentIcons.copy_24_regular,
                    enabled: false,
                  ),
                ],
                child: const Text(
                  'פתח',
                  textDirection: TextDirection.rtl,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();

    final icon = tester.widget<Icon>(find.byIcon(FluentIcons.copy_24_regular));
    expect(
      icon.color,
      theme.colorScheme.onSurface.withValues(alpha: 0.38),
    );
  });
}
