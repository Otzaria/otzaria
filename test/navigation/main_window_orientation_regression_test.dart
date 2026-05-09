import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Main window orientation regression', () {
    testWidgets(
      'שומר על העמוד הפעיל כשכיוון ה-PageView משתנה בעקבות החלפת אוריינטציה',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final widgetKey = GlobalKey<_OrientationAwarePageViewState>();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _OrientationAwarePageView(
                key: widgetKey,
                initialPage: 2,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('page-2'), findsOneWidget);
        expect(find.text('page-1'), findsNothing);
        expect(find.text('page-3'), findsNothing);

        final initialController = widgetKey.currentState!.controller;

        await tester.binding.setSurfaceSize(const Size(900, 600));
        await tester.pump();
        await tester.pump();

        expect(widgetKey.currentState!.controller, isNot(same(initialController)));
        expect(find.text('page-2'), findsOneWidget);
        expect(find.text('page-1'), findsNothing);
        expect(find.text('page-3'), findsNothing);
      },
    );
  });
}

class _OrientationAwarePageView extends StatefulWidget {
  const _OrientationAwarePageView({
    super.key,
    required this.initialPage,
  });

  final int initialPage;

  @override
  State<_OrientationAwarePageView> createState() =>
      _OrientationAwarePageViewState();
}

class _OrientationAwarePageViewState extends State<_OrientationAwarePageView> {
  late PageController _controller;
  Orientation? _previousOrientation;
  late int _currentPageIndex;

  PageController get controller => _controller;

  @override
  void initState() {
    super.initState();
    _currentPageIndex = widget.initialPage;
    _controller = PageController(initialPage: _currentPageIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleOrientationChange(Orientation orientation) {
    if (_previousOrientation == orientation) {
      return;
    }

    final isFirstDetection = _previousOrientation == null;
    _previousOrientation = orientation;
    if (isFirstDetection) {
      return;
    }

    final oldController = _controller;
    _controller = PageController(initialPage: _currentPageIndex);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldController.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        _handleOrientationChange(orientation);

        return PageView(
          controller: _controller,
          scrollDirection:
              orientation == Orientation.landscape ? Axis.vertical : Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          children: List.generate(
            5,
            (index) => Center(
              child: Text('page-$index'),
            ),
          ),
        );
      },
    );
  }
}