import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/utils/plugin_safe_mode.dart';
import 'package:otzaria/plugins/view/safe_mode_controls.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';

void main() {
  tearDown(PluginSafeMode.resetForTesting);

  testWidgets('normal startup adds no button; only safe mode has an exit', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SafeModeTitleBarIndicator())),
    );
    expect(find.byType(BarButton), findsNothing);
    PluginSafeMode.active.value = true;
    await tester.pump();
    expect(find.byType(BarButton), findsOneWidget);
    expect(find.text('מצב בטוח'), findsOneWidget);
    PluginSafeMode.active.value = false;
    await tester.pump();
    expect(find.byType(BarButton), findsNothing);
  });
}
