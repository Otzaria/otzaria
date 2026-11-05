import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/view/plugin_install_screen.dart';

Finder get _dialogSurface => find
    .descendant(of: find.byType(Dialog), matching: find.byType(Material))
    .first;

Future<void> _openDialog(
  WidgetTester tester, {
  Size size = const Size(1280, 900),
  double textScale = 1,
  double keyboardHeight = 0,
  bool longContent = false,
  String name = 'תוסף לדוגמה',
  void Function(Map<String, bool>)? onConfirm,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final manifest = PluginManifest.fromJson({
    'id': 'layout.example',
    'name': name,
    'version': '2.0.0',
    'entrypoint': 'index.html',
    'author': 'צוות הפיתוח',
    'description': longContent
        ? List.filled(20, 'תיאור של האפשרויות החדשות בתוסף.').join('\n')
        : 'כלי עזר לעבודה עם התוכנה.',
    'permissions': longContent ? ['notes.read', 'notes.write'] : <String>[],
  });

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he'),
      supportedLocales: const [Locale('he')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: EdgeInsets.only(bottom: keyboardHeight),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => PluginInstallScreen(
                manifest: manifest,
                tempDirPath: '',
                previousVersion: '1.0.0',
                onConfirm: onConfirm ?? (_) {},
                onCancel: () {},
              ),
            ),
            child: const Text('פתח'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('פתח'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('עדכון קצר מתאים לתוכן ואינו ממלא את גובה המסך', (tester) async {
    await _openDialog(tester);

    final surface = tester.getRect(_dialogSurface);
    expect(surface.width, lessThanOrEqualTo(560));
    expect(surface.height, lessThan(600));
    expect(find.text('עדכן').hitTestable(), findsOneWidget);
    expect(find.text('ביטול').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('במסך רחב מאוד רוחב חלונית העדכון נשאר מוגבל', (tester) async {
    await _openDialog(tester, size: const Size(2560, 1440));

    expect(tester.getSize(_dialogSurface).width, lessThanOrEqualTo(560));
    expect(tester.getSize(_dialogSurface).height, lessThan(600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('שם ארוך בחלון נמוך עם טקסט מוגדל משאיר פעולות ושם מלא נגישים', (
    tester,
  ) async {
    const name = 'MMMMMMMMMMMMMM';
    const title = 'עדכון תוסף: $name';
    await _openDialog(
      tester,
      size: const Size(320, 400),
      textScale: 2,
      longContent: true,
      name: name,
    );

    expect(find.text('עדכן').hitTestable(), findsOneWidget);
    expect(find.text('ביטול').hitTestable(), findsOneWidget);
    expect(
      tester
          .renderObject(find.text(title))
          .getTransformTo(null)
          .getMaxScaleOnAxis(),
      closeTo(1, 0.001),
    );
    await tester.longPress(find.text(title));
    await tester.pumpAndSettle();
    expect(find.text(title), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  for (final scenario in [
    (size: const Size(360, 640), scale: 1.0, keyboard: 0.0),
    (size: const Size(430, 800), scale: 2.0, keyboard: 0.0),
    (size: const Size(900, 400), scale: 1.5, keyboard: 0.0),
    (size: const Size(430, 800), scale: 1.5, keyboard: 300.0),
  ]) {
    testWidgets(
      'תוכן ארוך נגלל והפעולות נגישות: ${scenario.size}, '
      'טקסט ${scenario.scale}, מקלדת ${scenario.keyboard}',
      (tester) async {
        Map<String, bool>? granted;
        await _openDialog(
          tester,
          size: scenario.size,
          textScale: scenario.scale,
          keyboardHeight: scenario.keyboard,
          longContent: true,
          onConfirm: (permissions) => granted = permissions,
        );

        final surface = tester.getRect(_dialogSurface);
        expect(surface.left, greaterThanOrEqualTo(0));
        expect(surface.right, lessThanOrEqualTo(scenario.size.width));
        expect(surface.top, greaterThanOrEqualTo(0));
        expect(
          surface.bottom,
          lessThanOrEqualTo(scenario.size.height - scenario.keyboard),
        );
        final confirmBefore = tester.getRect(find.text('עדכן'));
        expect(find.text('עדכן').hitTestable(), findsOneWidget);
        expect(find.text('ביטול').hitTestable(), findsOneWidget);

        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable),
        );
        expect(scrollable.position.maxScrollExtent, greaterThan(0));
        scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
        await tester.pumpAndSettle();

        expect(tester.getRect(find.text('עדכן')), confirmBefore);
        expect(
          find.text('ניתן לשנות הרשאות בכל עת מהגדרות התוסף').hitTestable(),
          findsOneWidget,
        );
        await tester.tap(find.text('עדכן'));
        await tester.pumpAndSettle();
        expect(granted, {'notes.read': true, 'notes.write': true});
        expect(find.byType(PluginInstallScreen), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Enter ללא כפתור ממוקד אינו מתקין ו-Escape סוגר', (tester) async {
    var confirmed = false;
    await _openDialog(tester, onConfirm: (_) => confirmed = true);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(confirmed, isFalse);
    expect(find.byType(PluginInstallScreen), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);
    expect(find.byType(PluginInstallScreen), findsNothing);
  });
}
