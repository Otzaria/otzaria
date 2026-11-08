import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';
import 'package:otzaria_context_menu/otzaria_context_menu.dart' as menu;

class _Host extends StatefulWidget {
  const _Host({super.key});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int _buildCount = 0;

  void rebuild() => setState(() => _buildCount++);

  @override
  Widget build(BuildContext context) => AppContextMenuRegion(
    menuBuilder: (_, _) => [
      menu.AppContextMenuEntry(
        label: 'Copy $_buildCount',
        onTap: () {},
      ),
    ],
    child: const SizedBox.expand(),
  );
}

void main() {
  testWidgets('reader rebuilds reuse the menu presentation until theme changes', (
    tester,
  ) async {
    final key = GlobalKey<_HostState>();
    Widget app(ThemeData theme) => MaterialApp(
      theme: theme,
      home: Scaffold(body: _Host(key: key)),
    );

    await tester.pumpWidget(app(ThemeData.light()));
    final first = tester
        .widget<menu.ContextMenuRegion>(find.byType(menu.ContextMenuRegion))
        .presentation;

    key.currentState!.rebuild();
    await tester.pump();
    final second = tester
        .widget<menu.ContextMenuRegion>(find.byType(menu.ContextMenuRegion))
        .presentation;
    expect(identical(first, second), isTrue);

    await tester.pumpWidget(app(ThemeData.dark()));
    final dark = tester
        .widget<menu.ContextMenuRegion>(find.byType(menu.ContextMenuRegion))
        .presentation;
    expect(identical(second, dark), isFalse);
    expect(tester.takeException(), isNull);
  });
}
