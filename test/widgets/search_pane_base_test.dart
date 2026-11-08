import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/plugins/models/plugin_search_field_action.dart';
import 'package:otzaria/plugins/services/plugin_search_field_actions_registry.dart';
import 'package:otzaria/plugins/services/plugin_search_field_session_service.dart';
import 'package:otzaria/plugins/view/plugin_search_field_actions.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:otzaria/widgets/navigation/search_pane_base.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

void main() {
  for (final width in [200.0, 300.0, 400.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('פעולות חיפוש אינן מצרות את השאילתה ברוחב $width, '
          'קנה מידה $scale (issues #4071, #3881)', (tester) async {
        final controller = TextEditingController(text: 'שאילתת חיפוש ארוכה');
        final focusNode = FocusNode();
        final paneWidth = ValueNotifier(width);
        final registry = PluginSearchFieldActionsRegistry.instance;
        registry.registerPayload('narrow-test', {
          'id': 'action',
          'title': 'תוסף חיפוש',
          'icon': 'mic_24_regular',
          'fields': ['inBook'],
        });
        for (var i = 0; i < 2; i++) {
          registry.registerPayload('narrow-test-extra', {
            'id': 'action$i',
            'title': 'פעולת תוסף $i',
            'icon': 'mic_24_regular',
            'fields': ['inBook'],
          });
        }
        addTearDown(() {
          controller.dispose();
          focusNode.dispose();
          paneWidth.dispose();
          registry.removeAll('narrow-test');
          registry.removeAll('narrow-test-extra');
        });
        var settingsOpened = 0;
        var toggles = 0;
        var cleared = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: ValueListenableBuilder<double>(
                    valueListenable: paneWidth,
                    builder: (context, value, _) => SizedBox(
                      width: value,
                      child: SearchPaneBase(
                        searchController: controller,
                        focusNode: focusNode,
                        onAdvancedSearch: () => settingsOpened++,
                        searchFieldExtraActions:
                            const PluginSearchFieldExtraActions(
                              PluginSearchField.inBook,
                            ),
                        searchFieldActions: [
                          OtzariaSearchAction.icon(
                            iconData: FluentIcons.text_whole_word_20_regular,
                            tooltip: 'מילים שלמות',
                            onPressed: () => toggles++,
                          ),
                          OtzariaSearchAction.icon(
                            iconData: FluentIcons.book_24_regular,
                            tooltip: 'קטע נוכחי',
                            onPressed: () {},
                          ),
                        ],
                        resultsWidget: const SizedBox.shrink(),
                        isNoResults: false,
                        resetSearchCallback: () => cleared++,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        // Selecting on focus runs after a frame; the overlay rebuilds next.
        await tester.pumpAndSettle();

        final field = tester.getRect(find.byType(EditableText));
        final editable = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        final handleLinks = {
          editable.renderEditable.startHandleLayerLink,
          editable.renderEditable.endHandleLayerLink,
        };
        final handleRects = tester
            .renderObjectList<RenderBox>(
              find.descendant(
                of: find.byWidgetPredicate(
                  (widget) =>
                      widget is CompositedTransformFollower &&
                      handleLinks.contains(widget.link),
                ),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is RawGestureDetector &&
                      widget.gestures.containsKey(PanGestureRecognizer),
                ),
              ),
            )
            .map((handle) => handle.localToGlobal(Offset.zero) & handle.size)
            .toList();
        expect(controller.selection.isCollapsed, isFalse);
        expect(editable.renderEditable.selection, controller.selection);
        expect(
          editable.selectionOverlay!.value.selection,
          controller.selection,
        );
        expect(handleRects, hasLength(2));
        // Only the normal prefix, clear action and field padding use width.
        expect(field.width, greaterThanOrEqualTo(width - 110));
        for (final tooltip in [
          'מילים שלמות',
          'קטע נוכחי',
          'הגדרות חיפוש',
          'תוסף חיפוש',
          'פעולת תוסף 0',
          'פעולת תוסף 1',
        ]) {
          final actionRect = tester.getRect(find.byTooltip(tooltip));
          expect(
            actionRect.top,
            greaterThan(field.bottom),
          );
          expect(
            handleRects.any(actionRect.overlaps),
            isFalse,
            reason: '$tooltip must remain reachable while text is selected',
          );
        }
        await tester.tap(find.byTooltip('מילים שלמות'));
        await tester.tap(find.byTooltip('הגדרות חיפוש'));
        expect(toggles, 1);
        expect(settingsOpened, 1);
        await tester.tap(find.byIcon(FluentIcons.dismiss_24_regular));
        await tester.pump();
        expect(controller.text, isEmpty);
        expect(cleared, 1);
        expect(focusNode.hasFocus, isTrue);
        await tester.tap(find.byTooltip('תוסף חיפוש'));
        await tester.pump();
        final sessions = PluginSearchFieldSessionService.instance;
        final binding =
            tester.state(find.byType(PluginSearchFieldActions))
                as PluginSearchFieldBinding;
        final session = sessions.sessionFor(binding, 'narrow-test', 'action')!;
        paneWidth.value = width == 200 ? 400 : 200;
        await tester.pump();
        expect(
          sessions.sessionFor(binding, 'narrow-test', 'action'),
          same(session),
        );
        sessions.setFieldText(
          'narrow-test',
          session.id,
          'חיפוש לאחר שינוי רוחב',
        );
        expect(controller.text, 'חיפוש לאחר שינוי רוחב');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('בתוך חלונית ניווט השדה והפעולות שלו מצוירים בחלונית עצמה', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final host = NavPanelSearchHost();

    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
      host.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NavPanelSearchScope(
            host: host,
            child: NavPanelSearchSlot(
              index: 0,
              child: SearchPaneBase(
                searchController: controller,
                focusNode: focusNode,
                resultsWidget: const SizedBox.shrink(),
                isNoResults: false,
                resetSearchCallback: () {},
                searchFieldActions: const [
                  Icon(Icons.abc, key: ValueKey('wholeWordToggle')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(RtlTextField), findsOneWidget);
    expect(find.byKey(const ValueKey('wholeWordToggle')), findsOneWidget);
  });

  testWidgets('searchFieldActions מוצגות גם בשדה המקומי (מחוץ לחלונית)', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();

    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchPaneBase(
            searchController: controller,
            focusNode: focusNode,
            resultsWidget: const SizedBox.shrink(),
            isNoResults: false,
            resetSearchCallback: () {},
            searchFieldActions: const [
              Icon(Icons.abc, key: ValueKey('wholeWordToggle')),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('wholeWordToggle')), findsOneWidget);
  });

  testWidgets('מציג toolbar של תוצאות באותה שורה מול מונה התוצאות', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'נחל');
    final focusNode = FocusNode();

    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchPaneBase(
            searchController: controller,
            focusNode: focusNode,
            resultToolbar: const Text(
              '1 מתוך 4',
              textDirection: TextDirection.rtl,
            ),
            resultCountString: 'נמצאו 4 תוצאות',
            resultsWidget: const SizedBox.shrink(),
            isNoResults: false,
            resetSearchCallback: () {},
          ),
        ),
      ),
    );

    final toolbarFinder = find.text('1 מתוך 4');
    final counterFinder = find.text('נמצאו 4 תוצאות');

    expect(toolbarFinder, findsOneWidget);
    expect(counterFinder, findsOneWidget);
    final toolbarRect = tester.getRect(toolbarFinder);
    final counterRect = tester.getRect(counterFinder);

    expect(
      (toolbarRect.center.dy - counterRect.center.dy).abs(),
      lessThan(4),
    );
    expect(toolbarRect.left, greaterThan(counterRect.left));
  });

  testWidgets('צובע את אזור התוצאות ב-Material שקוף כך שהדגשת הכרטיסייה הפעילה '
      'לא דולפת אליו ולא לשדה החיפוש', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    const resultsKey = ValueKey('resultsContent');
    const tabHighlightColor = Colors.orange;

    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // מדמה כרטיסייה פעילה עם צבע הדגשה מסביב לפאנל
          body: Material(
            color: tabHighlightColor,
            child: SearchPaneBase(
              searchController: controller,
              focusNode: focusNode,
              resultsWidget: const SizedBox(key: resultsKey),
              isNoResults: false,
              resetSearchCallback: () {},
            ),
          ),
        ),
      ),
    );

    final nearestMaterial = tester.widget<Material>(
      find
          .ancestor(of: find.byKey(resultsKey), matching: find.byType(Material))
          .first,
    );
    expect(nearestMaterial.color, Colors.transparent);

    final searchFieldDecoration = tester
        .widget<TextField>(find.byType(TextField))
        .decoration;
    expect(searchFieldDecoration?.fillColor, isNot(tabHighlightColor));
  });

  testWidgets('כאשר יש errorMessage מוצגת הודעת השגיאה ולא "אין תוצאות"', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'נחל');
    final focusNode = FocusNode();

    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchPaneBase(
            searchController: controller,
            focusNode: focusNode,
            resultsWidget: const SizedBox.shrink(),
            isNoResults: true,
            errorMessage: 'שגיאה בחיפוש',
            resetSearchCallback: () {},
          ),
        ),
      ),
    );

    expect(find.text('שגיאה בחיפוש'), findsOneWidget);
    expect(find.text('אין תוצאות'), findsNothing);
  });

  testWidgets(
    'ללא errorMessage ועם isNoResults מוצגת ההודעה הגנרית "אין תוצאות"',
    (tester) async {
      final controller = TextEditingController(text: 'נחל');
      final focusNode = FocusNode();

      addTearDown(() {
        controller.dispose();
        focusNode.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchPaneBase(
              searchController: controller,
              focusNode: focusNode,
              resultsWidget: const SizedBox.shrink(),
              isNoResults: true,
              resetSearchCallback: () {},
            ),
          ),
        ),
      );

      expect(find.text('אין תוצאות'), findsOneWidget);
    },
  );

  testWidgets('בחלונית מרחפת Esc ראשון מנקה את השדה והשני סוגר אותה', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    var resets = 0;
    var closed = 0;

    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveSidePane(
            isOpen: true,
            floatOverContent: true,
            onClose: () => closed++,
            mainContent: const SizedBox.expand(),
            paneContent: SearchPaneBase(
              searchController: controller,
              focusNode: focusNode,
              resultsWidget: const SizedBox.shrink(),
              isNoResults: false,
              resetSearchCallback: () => resets++,
            ),
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();
    await tester.enterText(find.byType(RtlTextField), 'בראשית');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(controller.text, isEmpty);
    expect(resets, 1);
    expect(closed, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(closed, 1);
    expect(focusNode.hasFocus, isFalse, reason: 'הקלדה לא תיכנס לשדה נסתר');
  });
}
