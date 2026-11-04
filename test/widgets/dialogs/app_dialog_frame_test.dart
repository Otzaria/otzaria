import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/theme/layout_tokens.dart';
import 'package:otzaria/widgets/widgets_exports.dart' show ActionButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpDialog(
    WidgetTester tester, {
    String title = 'כותרת',
    bool scrollable = true,
    bool fitTitle = true,
    Size size = const Size(800, 600),
    Widget child = const SizedBox.shrink(),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: AppDialogFrame(
            title: title,
            icon: FluentIcons.list_24_regular,
            size: AppDialogSize.large,
            fitTitle: fitTitle,
            scrollable: scrollable,
            child: child,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('חסימת סגירה משאירה Tab, Enter ו-Space לביטול פעולה', (
    tester,
  ) async {
    var cancelled = 0;
    final dismissible = ValueNotifier(false);
    addTearDown(dismissible.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => ValueListenableBuilder<bool>(
                valueListenable: dismissible,
                builder: (_, canDismiss, _) => AppDialogFrame(
                  title: 'התקנה',
                  icon: FluentIcons.puzzle_piece_24_regular,
                  closeEnabled: canDismiss,
                  actions: [
                    ActionButton.ghost(
                      text: 'ביטול פריסה',
                      onPressed: () => cancelled++,
                    ),
                  ],
                  child: const Text('תוכן'),
                ),
              ),
            ),
            child: const Text('פתח'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('התקנה'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(cancelled, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(cancelled, 2);
    expect(find.text('התקנה'), findsOneWidget);

    dismissible.value = true;
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('התקנה'), findsNothing);
  });

  group('AppDialogFrame — fitTitle', () {
    testWidgets('הכותרת בשורה אחת ב-FittedBox עם BoxFit.scaleDown', (
      tester,
    ) async {
      const longTitle = 'כותרת ארוכה מאוד שעשויה לגלוש בתצוגה רגילה';
      await pumpDialog(tester, size: const Size(350, 700), title: longTitle);

      expect(tester.widget<Text>(find.text(longTitle)).maxLines, 1);
      expect(
        tester
            .widgetList<FittedBox>(find.byType(FittedBox))
            .where((fb) => fb.fit == BoxFit.scaleDown),
        isNotEmpty,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('AppDialogFrame — גלילה', () {
    testWidgets(
      'scrollable: פס גלילה גלוי, והריפוד dialogPadding בתוך הגלילה',
      (
        tester,
      ) async {
        const childKey = Key('dialog-content');
        await pumpDialog(
          tester,
          child: const SizedBox(key: childKey, height: 10),
        );

        expect(find.byType(Scrollbar), findsOneWidget);
        final scrollView = tester.widget<SingleChildScrollView>(
          find.byType(SingleChildScrollView),
        );
        expect(scrollView.padding, AppTokens.dialogPadding);
        final scrollbarRect = tester.getRect(find.byType(Scrollbar));
        final contentRect = tester.getRect(find.byKey(childKey));
        expect(
          scrollbarRect.right - contentRect.right,
          closeTo(AppTokens.spaceLG, 0.5),
        );
      },
    );

    testWidgets('בלי scrollable — אין Scrollbar ואין SingleChildScrollView', (
      tester,
    ) async {
      await pumpDialog(tester, scrollable: false);

      expect(find.byType(Scrollbar), findsNothing);
      expect(find.byType(SingleChildScrollView), findsNothing);
    });
  });

  group('AppDialogFrame — גובה קבוע ומשטח', () {
    Future<void> pumpFixed(
      WidgetTester tester, {
      required double height,
      Key? surfaceKey,
      String? subtitle,
      int? subtitleMaxLines,
    }) async {
      tester.view.physicalSize = const Size(800, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: AppDialogFrame(
              title: 'חיפוש',
              icon: FluentIcons.search_24_regular,
              size: AppDialogSize.large,
              height: height,
              surfaceKey: surfaceKey,
              subtitle: subtitle,
              subtitleMaxLines: subtitleMaxLines,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('גובה קבוע אינו נחתך ל-85%, רק לגובה החלון', (tester) async {
      const surface = Key('surface');
      await pumpFixed(tester, height: 500, surfaceKey: surface);
      expect(tester.getSize(find.byKey(surface)), const Size(720, 500));

      await pumpFixed(tester, height: 900, surfaceKey: surface);
      expect(
        tester.getSize(find.byKey(surface)).height,
        560 - 2 * AppDialogSize.inset.top,
      );
    });

    testWidgets('subtitleMaxLines מגיע לכותרת', (tester) async {
      await pumpFixed(
        tester,
        height: 400,
        subtitle: 'שם ספר',
        subtitleMaxLines: 1,
      );
      expect(tester.widget<Text>(find.text('שם ספר')).maxLines, 1);
    });
  });

  group('AppDialogFrame — leading', () {
    Future<void> pumpLeading(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Material(
              child: AppDialogFrame(
                title: 'הדפסה',
                icon: FluentIcons.print_24_regular,
                size: AppDialogSize.full,
                leading: const SizedBox(
                  key: Key('nav'),
                  width: 250,
                  height: 40,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('בחלון רחב: בתחילת הרצועה, לפני התג', (tester) async {
      await pumpLeading(tester, const Size(1000, 700));
      final nav = tester.getRect(find.byKey(const Key('nav')));
      final badge = tester.getRect(find.byType(AppDialogIconBadge));
      expect(nav.left, greaterThan(badge.right), reason: 'RTL: מימין לתג');
      expect(nav.center.dy, closeTo(badge.center.dy, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('בחלון צר: בשורה משלו מתחת לכותרת, בלי חריגה', (tester) async {
      await pumpLeading(tester, const Size(360, 700));
      final nav = tester.getRect(find.byKey(const Key('nav')));
      final title = tester.getRect(find.text('הדפסה'));
      expect(nav.top, greaterThan(title.bottom));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('tabs: שורת הלשוניות בין הרצועה לגוף', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 2,
          child: Material(
            child: AppDialogFrame(
              title: 'דיווח',
              icon: FluentIcons.chat_24_regular,
              size: AppDialogSize.large,
              height: 500,
              padding: EdgeInsets.zero,
              tabs: const TabBar(
                tabs: [
                  Tab(text: 'ראשונה'),
                  Tab(text: 'שנייה'),
                ],
              ),
              child: const TabBarView(
                children: [Text('גוף ראשון'), Text('גוף שני')],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final header = tester.getRect(find.byType(AppDialogHeader));
    final tabs = tester.getRect(find.byType(TabBar));
    final body = tester.getRect(find.byType(TabBarView));
    expect(tabs.top, header.bottom);
    expect(body.top, tabs.bottom);
    expect(find.text('גוף ראשון'), findsOneWidget);

    await tester.tap(find.text('שנייה'));
    await tester.pumpAndSettle();
    expect(find.text('גוף שני'), findsOneWidget);
  });

  // DD-16 בחלון צר: large ו-full במסך מלא. בדסקטופ שורת הכותרת של החלון
  // (כפתורי החלון) נשארת גלויה מעליו.
  group('מסך מלא בחלון צר', () {
    for (final (platform, top) in [
      (TargetPlatform.windows, LayoutConstraints.windowCaptionHeight),
      (TargetPlatform.linux, LayoutConstraints.windowCaptionHeight),
      (TargetPlatform.macOS, LayoutConstraints.windowCaptionHeight),
      (TargetPlatform.android, 0.0),
      (TargetPlatform.iOS, 0.0),
    ]) {
      for (final size in [AppDialogSize.large, AppDialogSize.full]) {
        testWidgets('${platform.name} ${size.name}: מתחיל ב-$top', (
          tester,
        ) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          tester.view.physicalSize = const Size(360, 700);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          const surface = Key('surface');
          await tester.pumpWidget(
            MaterialApp(
              home: Material(
                child: AppDialogFrame(
                  title: 'חיפוש',
                  icon: FluentIcons.search_24_regular,
                  size: size,
                  surfaceKey: surface,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(
            tester.getRect(find.byKey(surface)),
            Rect.fromLTRB(0, top, 360, 700),
          );
          debugDefaultTargetPlatformOverride = null;
        });
      }
    }
  });

  // R2-1: מעבר מעל רוחב 600 (סיבוב טלפון, גרירת חלון) לא בונה את הגוף מחדש.
  group('מעבר מעל 600 שומר את הגוף', () {
    for (final (name, size, height) in [
      ('large עם גובה', AppDialogSize.large, 500.0),
      ('large לפי התוכן', AppDialogSize.large, null),
      ('full', AppDialogSize.full, null),
      ('medium', AppDialogSize.medium, null),
    ]) {
      testWidgets(name, (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: Material(
              child: AppDialogFrame(
                title: 'חיפוש',
                icon: FluentIcons.search_24_regular,
                size: size,
                height: height,
                child: const TextField(),
              ),
            ),
          ),
        );
        await tester.tap(find.byType(TextField));
        await tester.enterText(find.byType(TextField), 'בראשית ברא');
        await tester.pump();
        final state = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        tester
            .widget<EditableText>(find.byType(EditableText))
            .controller
            .selection = const TextSelection(
          baseOffset: 2,
          extentOffset: 6,
        );
        await tester.pump();

        for (final width in [900.0, 400.0, 900.0]) {
          tester.view.physicalSize = Size(width, 800);
          await tester.pump();
          final editable = tester.widget<EditableText>(
            find.byType(EditableText),
          );
          expect(
            tester.state<EditableTextState>(find.byType(EditableText)),
            same(state),
            reason: 'רוחב $width: השדה נבנה מחדש',
          );
          expect(editable.focusNode.hasFocus, isTrue, reason: 'רוחב $width');
          expect(editable.controller.text, 'בראשית ברא');
          expect(
            editable.controller.selection,
            const TextSelection(baseOffset: 2, extentOffset: 6),
          );
        }
      });
    }
  });

  // q12 Q8: בחלון נמוך (טלפון לרוחב, חלון שטוח) הגובה הוא האילוץ, בכל רוחב.
  group('חלון נמוך', () {
    Future<Size> surfaceOf(
      WidgetTester tester,
      Size window,
      AppDialogSize size,
    ) async {
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const surface = Key('surface');
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: AppDialogFrame(
              title: 'חיפוש בספרייה',
              icon: FluentIcons.search_24_regular,
              size: size,
              surfaceKey: surface,
              child: const SizedBox(height: 800),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      return tester.getSize(find.byKey(surface));
    }

    testWidgets('640×360: large במסך מלא', (tester) async {
      expect(
        await surfaceOf(tester, const Size(640, 360), AppDialogSize.large),
        const Size(640, 360),
      );
    });

    testWidgets('640×360: medium נשאר צף', (tester) async {
      final size = await surfaceOf(
        tester,
        const Size(640, 360),
        AppDialogSize.medium,
      );
      expect(size.width, AppDialogSize.medium.width);
      expect(size.height, lessThan(360));
    });

    // ב־844×390 (טלפון לרוחב, מעל 840) דיאלוג צף נחתך בתחתית.
    for (final window in const [Size(844, 390), Size(1280, 440)]) {
      testWidgets('${window.width.toInt()}×${window.height.toInt()}: large '
          'ו-full במסך מלא', (tester) async {
        for (final size in const [AppDialogSize.large, AppDialogSize.full]) {
          expect(await surfaceOf(tester, window, size), window);
        }
      });
    }

    testWidgets('844×390: medium נשאר צף', (tester) async {
      final size = await surfaceOf(
        tester,
        const Size(844, 390),
        AppDialogSize.medium,
      );
      expect(size.width, AppDialogSize.medium.width);
      expect(size.height, lessThan(390));
    });

    testWidgets('1024×600 (לא נמוך): large נשאר צף', (tester) async {
      final size = await surfaceOf(
        tester,
        const Size(1024, 600),
        AppDialogSize.large,
      );
      expect(size.width, AppDialogSize.large.width);
      expect(size.height, lessThan(600));
    });
  });
}
