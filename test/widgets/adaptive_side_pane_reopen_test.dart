import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';

// פתיחה מחדש של חלונית בהרחבת חלון (סעיף 18, החלטת הבעלים א): חלונית שנסגרה
// אוטומטית בצמצום (או שהמסך פתח אותה סגורה בחלון צר) נפתחת כשיש מקום; חלונית
// שהמשתמש סגר בעצמו נשארת סגורה.

class _Screen extends StatefulWidget {
  const _Screen({required this.initiallyOpen});

  final bool initiallyOpen;

  @override
  State<_Screen> createState() => _ScreenState();
}

class _ScreenState extends State<_Screen> {
  late bool isOpen = widget.initiallyOpen;
  int opens = 0;

  void setOpen(bool value) => setState(() => isOpen = value);

  @override
  Widget build(BuildContext context) {
    return AdaptiveSidePane(
      isOpen: isOpen,
      paneWidth: 300,
      minMainContentWidth: 400,
      onClose: () => setOpen(false),
      onOpen: () {
        opens++;
        setOpen(true);
      },
      mainContent: const SizedBox.expand(),
      paneContent: const Text('pane'),
    );
  }
}

void main() {
  const wide = Size(1000, 600);
  const narrow = Size(500, 600);

  Future<_ScreenState> pump(
    WidgetTester tester, {
    required Size size,
    bool initiallyOpen = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: _Screen(initiallyOpen: initiallyOpen)),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state<_ScreenState>(find.byType(_Screen));
  }

  Future<void> resize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    await tester.pumpAndSettle();
  }

  testWidgets('נסגרה אוטומטית בצמצום: נפתחת שוב בהרחבה', (tester) async {
    final screen = await pump(tester, size: wide);
    await resize(tester, narrow);
    expect(screen.isOpen, isFalse, reason: 'הצמצום סוגר אוטומטית');

    await resize(tester, wide);

    expect(screen.isOpen, isTrue);
    expect(screen.opens, 1);
  });

  testWidgets('המסך פתח אותה סגורה בחלון צר: נפתחת בהרחבה', (tester) async {
    final screen = await pump(tester, size: narrow, initiallyOpen: false);

    await resize(tester, wide);

    expect(screen.isOpen, isTrue);
  });

  testWidgets('המשתמש סגר אותה בחלון צר: נשארת סגורה בהרחבה', (tester) async {
    final screen = await pump(tester, size: wide);
    await resize(tester, narrow);
    screen.setOpen(true);
    await tester.pumpAndSettle();
    expect(find.text('pane'), findsOneWidget);
    // לחיצה על ההצללה, מחוץ לחלונית (שמאל המסך; החלונית בימין).
    await tester.tapAt(const Offset(20, 300));
    await tester.pumpAndSettle();
    expect(screen.isOpen, isFalse);

    await resize(tester, wide);

    expect(screen.isOpen, isFalse);
    expect(screen.opens, 0);
  });

  testWidgets('המשתמש סגר אותה בחלון רחב: צמצום והרחבה לא פותחים אותה', (
    tester,
  ) async {
    final screen = await pump(tester, size: wide);
    screen.setOpen(false);
    await tester.pumpAndSettle();

    await resize(tester, narrow);
    await resize(tester, wide);

    expect(screen.isOpen, isFalse);
    expect(screen.opens, 0);
  });

  testWidgets('פתיחה ידנית מבטלת את סגירת המשתמש: צמצום והרחבה פותחים שוב', (
    tester,
  ) async {
    final screen = await pump(tester, size: wide);
    screen.setOpen(false);
    await tester.pumpAndSettle();
    screen.setOpen(true);
    await tester.pumpAndSettle();

    await resize(tester, narrow);
    expect(screen.isOpen, isFalse);
    await resize(tester, wide);

    expect(screen.isOpen, isTrue);
  });
}
