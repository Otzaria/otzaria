import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_page_number_display.dart';
import 'package:otzaria/pdf_book/view/pdf_thumbnails_screen.dart';
import 'package:pdfrx/pdfrx.dart';

class _TestController extends PdfViewerController {
  _TestController({required this.page, required this.count});

  int page;
  int count;
  bool ready = true;
  final List<VoidCallback> _listeners = [];

  @override
  bool get isReady => ready;

  @override
  int? get pageNumber => page;

  @override
  int get pageCount => count;

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void emit() {
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }
}

void main() {
  testWidgets('PageNumberDisplay אינו נבנה מחדש כשהעמוד לא השתנה', (
    tester,
  ) async {
    final controller = _TestController(page: 3, count: 20);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PageNumberDisplay(controller: controller)),
      ),
    );
    final element = tester.element(find.byType(PageNumberDisplay));
    expect(element.dirty, isFalse);

    controller.emit();

    expect(element.dirty, isFalse);
    expect(find.text('3/20'), findsOneWidget);
  });

  testWidgets('PageNumberDisplay מתעדכן כשהעמוד או מספר העמודים משתנים', (
    tester,
  ) async {
    final controller = _TestController(page: 3, count: 20);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PageNumberDisplay(controller: controller)),
      ),
    );
    final element = tester.element(find.byType(PageNumberDisplay));

    controller
      ..page = 4
      ..emit();
    expect(element.dirty, isTrue);
    await tester.pump();
    expect(find.text('4/20'), findsOneWidget);

    controller
      ..count = 21
      ..emit();
    expect(element.dirty, isTrue);
    await tester.pump();
    expect(find.text('4/21'), findsOneWidget);
  });

  testWidgets('PageNumberDisplay מחליף listener יחד עם ה-controller', (
    tester,
  ) async {
    final oldController = _TestController(page: 3, count: 20);
    final newController = _TestController(page: 5, count: 30);
    Widget build(_TestController controller) => MaterialApp(
      home: Scaffold(body: PageNumberDisplay(controller: controller)),
    );
    await tester.pumpWidget(build(oldController));
    await tester.pumpWidget(build(newController));
    final element = tester.element(find.byType(PageNumberDisplay));
    expect(find.text('5/30'), findsOneWidget);

    oldController
      ..page = 4
      ..emit();
    expect(element.dirty, isFalse);

    newController
      ..page = 6
      ..emit();
    expect(element.dirty, isTrue);
    await tester.pump();
    expect(find.text('6/30'), findsOneWidget);
  });

  testWidgets('PageNumberDisplay מוסתר כשה-controller מפסיק להיות מוכן', (
    tester,
  ) async {
    final controller = _TestController(page: 3, count: 20);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PageNumberDisplay(controller: controller)),
      ),
    );

    controller
      ..ready = false
      ..emit();
    await tester.pump();

    expect(find.text('3/20'), findsNothing);
  });

  testWidgets('ThumbnailsView אינו נבנה מחדש כשהעמוד לא השתנה', (
    tester,
  ) async {
    final controller = _TestController(page: 3, count: 20);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThumbnailsView(documentRef: null, controller: controller),
        ),
      ),
    );
    await tester.pump();
    final element = tester.element(find.byType(ThumbnailsView));
    expect(element.dirty, isFalse);

    controller.emit();

    expect(element.dirty, isFalse);
  });

  testWidgets('ThumbnailsView נבנה מחדש כשהעמוד משתנה', (tester) async {
    final controller = _TestController(page: 3, count: 20);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThumbnailsView(documentRef: null, controller: controller),
        ),
      ),
    );
    await tester.pump();
    final element = tester.element(find.byType(ThumbnailsView));

    controller
      ..page = 4
      ..emit();

    expect(element.dirty, isTrue);
  });

  testWidgets('ThumbnailsView מחליף listener יחד עם ה-controller', (
    tester,
  ) async {
    final oldController = _TestController(page: 3, count: 20);
    final newController = _TestController(page: 5, count: 30);
    Widget build(_TestController controller) => MaterialApp(
      home: Scaffold(
        body: ThumbnailsView(documentRef: null, controller: controller),
      ),
    );
    await tester.pumpWidget(build(oldController));
    await tester.pumpWidget(build(newController));
    await tester.pump();
    final element = tester.element(find.byType(ThumbnailsView));

    oldController
      ..page = 4
      ..emit();
    expect(element.dirty, isFalse);

    newController
      ..page = 6
      ..emit();
    expect(element.dirty, isTrue);
  });
}
