import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/navigation/panel_tab_header.dart';
import '../helpers/memory_settings_cache.dart';

// ─── helper ───────────────────────────────────────────────────────────────────

class _SidebarTabHeaderHost extends StatefulWidget {
  final int initialIndex;
  final bool showPin;
  final bool isPinned;

  const _SidebarTabHeaderHost({
    this.initialIndex = 0,
    this.showPin = false,
    this.isPinned = false,
  });

  @override
  State<_SidebarTabHeaderHost> createState() => _SidebarTabHeaderHostState();
}

class _SidebarTabHeaderHostState extends State<_SidebarTabHeaderHost>
    with SingleTickerProviderStateMixin {
  late final TabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialIndex,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SidebarTabHeader(
      controller: _controller,
      tabs: const [
        (
          icon: FluentIcons.link_24_regular,
          iconFilled: FluentIcons.link_24_filled,
          label: 'קישורים',
        ),
        (
          icon: FluentIcons.note_24_regular,
          iconFilled: FluentIcons.note_24_filled,
          label: 'הערות',
        ),
      ],
      isPinned: widget.isPinned,
      onTogglePin: widget.showPin ? () {} : null,
    );
  }
}

Widget _wrap({
  int initialIndex = 0,
  bool showPin = false,
  bool isPinned = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: _SidebarTabHeaderHost(
        initialIndex: initialIndex,
        showPin: showPin,
        isPinned: isPinned,
      ),
    ),
  );
}

// ─── tests ────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  group('SidebarTabHeader - אייקונים', () {
    testWidgets('מציג אייקון filled לטאב הנבחר (index=0)', (tester) async {
      await tester.pumpWidget(_wrap(initialIndex: 0));
      await tester.pump();

      expect(find.byIcon(FluentIcons.link_24_filled), findsOneWidget);
      expect(find.byIcon(FluentIcons.link_24_regular), findsNothing);
    });

    testWidgets('מציג אייקון רגיל לטאב שאינו נבחר', (tester) async {
      await tester.pumpWidget(_wrap(initialIndex: 0));
      await tester.pump();

      // הטאב השני (הערות) אינו נבחר → אייקון רגיל
      expect(find.byIcon(FluentIcons.note_24_regular), findsOneWidget);
      expect(find.byIcon(FluentIcons.note_24_filled), findsNothing);
    });

    testWidgets('אחרי מעבר טאב — האייקון הנבחר מתעדכן', (tester) async {
      await tester.pumpWidget(_wrap(initialIndex: 0));
      await tester.pump();

      // לפני: קישורים נבחר
      expect(find.byIcon(FluentIcons.link_24_filled), findsOneWidget);

      // לוחצים על "הערות"
      await tester.tap(find.text('הערות'));
      await tester.pump();

      // אחרי: הערות נבחר, קישורים רגיל
      expect(find.byIcon(FluentIcons.note_24_filled), findsOneWidget);
      expect(find.byIcon(FluentIcons.link_24_regular), findsOneWidget);
    });

    testWidgets('initialIndex=1 — הטאב השני מקבל אייקון filled', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(initialIndex: 1));
      await tester.pump();

      expect(find.byIcon(FluentIcons.note_24_filled), findsOneWidget);
      expect(find.byIcon(FluentIcons.link_24_regular), findsOneWidget);
    });
  });

  group('SidebarTabHeader - כפתור pin', () {
    testWidgets('onTogglePin=null — כפתור pin לא מוצג', (tester) async {
      await tester.pumpWidget(_wrap(showPin: false));
      await tester.pump();

      expect(find.byType(PinSidebarButton), findsNothing);
    });

    testWidgets('onTogglePin מסופק — כפתור pin מוצג', (tester) async {
      await tester.pumpWidget(_wrap(showPin: true));
      await tester.pump();

      expect(find.byType(PinSidebarButton), findsOneWidget);
    });

    testWidgets('isPinned=true — אייקון pin filled מוצג', (tester) async {
      await tester.pumpWidget(_wrap(showPin: true, isPinned: true));
      await tester.pump();

      expect(find.byIcon(FluentIcons.pin_24_filled), findsOneWidget);
    });

    testWidgets('isPinned=false — אייקון pin regular מוצג', (tester) async {
      await tester.pumpWidget(_wrap(showPin: true, isPinned: false));
      await tester.pump();

      // globalPin=false (Settings לא מוגדר), isPinned=false
      expect(find.byIcon(FluentIcons.pin_24_regular), findsOneWidget);
    });
  });
}
