// נגישות חוצת מסכים: תפריט הקשר במקלדת באתר אמיתי (ItemsListView), פתיחה
// במקש Menu ו-Shift+F10, ניווט בחיצים, ו-Escape שמחזיר פוקוס. כל אתר
// `AppContextMenuRegion` עובר באותה חבילה (otzaria_context_menu).
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/widgets/commentary/links_list_view.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/controls/bar_split_button.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/smart_text/raised_markers.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:otzaria/widgets/dialogs/input_dialog.dart';
import 'package:otzaria/widgets/lists/items_list_view.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../test_helpers/stub_settings_bloc.dart';
import 'responsive_harness.dart';

final _items = [
  for (final title in ['ספר ראשון', 'ספר שני', 'ספר שלישי'])
    Bookmark(
      ref: title,
      book: TextBook(title: title),
      index: 0,
    ),
];

typedef _Log = ({List<String> edited, List<String> deleted});

_Log _newLog() => (edited: <String>[], deleted: <String>[]);

late _Log _log;

Widget _list(_Log log) => ItemsListView(
  items: _items,
  onItemTap: (_, _, _) {},
  onDelete: (_, index) => log.deleted.add('$index'),
  onClearAll: (_) {},
  onEdit: (_, _, index) => log.edited.add('$index'),
  hintText: 'חיפוש',
  emptyText: 'ריק',
  notFoundText: 'לא נמצא',
  clearAllText: 'נקה הכל',
);

FocusNode _focusRow(WidgetTester tester, String title) {
  final node = Focus.of(tester.element(find.text(title).first));
  node.requestFocus();
  return node;
}

Future<void> _shiftF10(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.f10);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.f10);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => Settings.init(cacheProvider: MemorySettingsCache()));

  group('תפריט הקשר במקלדת', () {
    testResponsive(
      'Shift+F10 על שורה ברשימה פותח תפריט שניתן להפעיל במקלדת',
      build: (_) {
        _log = _newLog();
        return _list(_log);
      },
      act: (tester, run) async {
        final row = _focusRow(tester, 'ספר שני');
        await tester.pump();
        await _shiftF10(tester);
        expectVisible(tester, run, find.text('ערוך תיאור'), name: 'ערוך תיאור');
        expectVisible(tester, run, find.text('מחק'), name: 'מחק');
        expect(row.hasPrimaryFocus, isFalse, reason: 'הפוקוס עבר לתפריט');

        // החץ מעביר לפריט הבא, Enter מפעיל אותו.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
      },
      verify: (tester, run) async {
        expect(_log.deleted, ['1'], reason: 'המחיקה היא על "ספר שני"');
        expect(_log.edited, isEmpty);
        expect(find.text('ערוך תיאור'), findsNothing);
      },
    );

    testWidgets('Escape סוגר את התפריט ומחזיר את הפוקוס לשורה', (tester) async {
      final log = _newLog();
      await pumpResponsive(
        tester,
        const ResponsiveViewport(800, 600),
        (_) => _list(log),
      );
      final row = _focusRow(tester, 'ספר ראשון');
      await tester.pump();
      await _shiftF10(tester);
      expect(find.text('ערוך תיאור'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('ערוך תיאור'), findsNothing);
      expect(row.hasPrimaryFocus, isTrue);
      expect(log.edited, isEmpty);
      expect(log.deleted, isEmpty);
    });

    testWidgets('מקש Menu פותח את אותו תפריט', (tester) async {
      await pumpResponsive(
        tester,
        const ResponsiveViewport(800, 600),
        (_) => _list(_newLog()),
      );
      _focusRow(tester, 'ספר שלישי');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      expect(find.text('ערוך תיאור'), findsOneWidget);
    });
  });

  group('פוקוס בדיאלוגי AppDialogFrame', () {
    // פותח דיאלוג מכפתור ממוקד במקלדת, כמו משתמש מקלדת אמיתי.
    Future<({FocusNode opener, Future<Object?> Function() result})> openFrom(
      WidgetTester tester,
      Future<Object?> Function(BuildContext) open,
    ) async {
      Future<Object?>? pending;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  key: const ValueKey('opener'),
                  onPressed: () => pending = open(context),
                  child: const Text('פתח'),
                ),
              ),
            ),
          ),
        ),
      );
      final opener = Focus.of(tester.element(find.text('פתח')));
      opener.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(pending, isNotNull, reason: 'הדיאלוג נפתח');
      return (opener: opener, result: () => pending!);
    }

    bool focusInsideDialog() =>
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<Dialog>() !=
        null;

    final dialogs = <String, Future<Object?> Function(BuildContext)>{
      'showSingleActionDialog': (context) => showSingleActionDialog(
        context: context,
        title: 'הודעה',
        content: 'תוכן',
        confirmText: 'הבנתי',
      ),
      'showTwoActionsDialog': (context) => showTwoActionsDialog(
        context: context,
        title: 'שאלה',
        content: 'תוכן',
        cancelText: 'ביטול',
        confirmText: 'אישור',
      ),
      'showInputDialog': (context) => showInputDialog(
        context: context,
        title: 'שם',
        labelText: 'שם התיקייה',
        cancelText: 'ביטול',
        confirmText: 'צור',
      ),
    };

    for (final entry in dialogs.entries) {
      testWidgets('${entry.key}: הפוקוס הראשוני בתוך הדיאלוג', (tester) async {
        await openFrom(tester, entry.value);
        expect(focusInsideDialog(), isTrue, reason: 'הפוקוס נשאר בדף שמאחור');
      });

      testWidgets('${entry.key}: Tab נשאר בתוך הדיאלוג', (tester) async {
        await openFrom(tester, entry.value);
        for (var i = 0; i < 6; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(
            focusInsideDialog(),
            isTrue,
            reason: 'Tab מספר $i יצא מהדיאלוג',
          );
        }
      });

      testWidgets('${entry.key}: Escape סוגר ומחזיר פוקוס לכפתור הפותח', (
        tester,
      ) async {
        final opened = await openFrom(tester, entry.value);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(opened.opener.hasPrimaryFocus, isTrue);
      });
    }
  });

  group('הגדלת טקסט במדידות ידניות', () {
    const scales = [1.3, 1.5, 2.0];

    // כפתור עם אייקון וטקסט ממורכז: ההחלטה "נכנס בשורה אחת" נמדדת עם אותה
    // הגדלה שהטקסט מצויר בה. בלי זה טקסט מוגדל נשבר באמצע מילה ולא מאוזן.
    testResponsive(
      'ActionButton ממורכז עם אייקון: טקסט שלא נכנס מתאזן לשתי שורות',
      viewports: [
        for (final scale in scales)
          ResponsiveViewport(800, 600, textScale: scale),
      ],
      build: (_) => Center(
        child: SizedBox(
          width: 230,
          child: ActionButton.neutral(
            text: 'שמור והמשך לשלב הבא',
            icon: Icons.save,
            textAlign: TextAlign.center,
            onPressed: () {},
          ),
        ),
      ),
      verify: (tester, run) async {
        final scale = run.viewport.textScale;
        final texts = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .where((t) => t.contains('שמור'))
            .toList();
        expect(texts, hasLength(1));
        expect(
          texts.single,
          contains('\n'),
          reason:
              'בהגדלה $scale הטקסט רחב מהכפתור, לכן מתאזן לשתי שורות במקום '
              'להישבר בשבירה אקראית',
        );
        expectVisible(tester, run, find.byType(ActionButton), name: 'כפתור');
      },
    );

    // אות מורמת (הערת שוליים, עוגן מפרש): מצוירת מעל הגליף השקוף, ולכן חייבת
    // לגדול ולעלות יחד עם הפסקה שמוגדלת.
    testWidgets('אות מורמת גדלה ועולה עם הגדלת הטקסט', (tester) async {
      Future<RaisedMarkerPlacement> placementAt(double scale) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: const Scaffold(
                  body: Align(
                    alignment: Alignment.topRight,
                    child: SizedBox(
                      width: 700,
                      child: SmartTextWidget(
                        text: 'על ידי חום האש <sup>(א)</sup> או תולדותיה.',
                        settings: RenderSettings(fontSize: 25),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return tester
            .renderObject<RenderRaisedMarkerOverlay>(
              find.byType(RaisedMarkerOverlay),
            )
            .debugPlacements()
            .single;
      }

      final plain = await placementAt(1.0);
      final big = await placementAt(1.5);
      expect(
        big.paintRect.height / plain.paintRect.height,
        closeTo(1.5, 0.1),
        reason: 'גובה האות המורמת צריך לגדול כמו הפסקה',
      );
      expect(
        big.paintRect.width / plain.paintRect.width,
        closeTo(1.5, 0.1),
        reason: 'רוחב האות המורמת צריך לגדול כמו הפסקה',
      );
      expect(
        big.anchorRect.height / plain.anchorRect.height,
        closeTo(1.5, 0.1),
        reason: 'הגליף השקוף שמתחתיה גדל, והאות חייבת להתאים לו',
      );
    });

    // סרגל עליון: כותרת ארוכה וכפתורים בכל הגדלה נשארים בתוך הסרגל.
    testResponsive(
      'AppTopBar: כותרת ארוכה וכפתורים בהגדלת טקסט',
      viewports: [
        const ResponsiveViewport(800, 600),
        for (final scale in scales)
          ResponsiveViewport(800, 600, textScale: scale),
        for (final scale in scales)
          ResponsiveViewport(360, 640, textScale: scale, touch: true),
      ],
      build: (_) => Column(
        children: [
          AppTopBar(
            leadingItems: [
              AppTopBarItem(
                widget: IconButton(
                  tooltip: 'תפריט',
                  icon: const Icon(Icons.menu),
                  onPressed: () {},
                ),
              ),
            ],
            center: const Text(
              'שולחן ערוך אורח חיים סימן רמ"ג הלכות ברכת המזון ושאר דברים',
              overflow: TextOverflow.ellipsis,
            ),
            trailingItems: [
              AppTopBarItem(
                widget: IconButton(
                  tooltip: 'חיפוש',
                  icon: const Icon(Icons.search),
                  onPressed: () {},
                ),
              ),
            ],
          ),
          const Expanded(child: SizedBox()),
        ],
      ),
      verify: (tester, run) async {
        final bar = tester.getRect(find.byType(AppTopBar));
        for (final element
            in find
                .descendant(
                  of: find.byType(AppTopBar),
                  matching: find.byType(RichText),
                )
                .evaluate()) {
          final render = element.renderObject;
          if (render is! RenderParagraph || render.text.toPlainText().isEmpty) {
            continue;
          }
          final rect = MatrixUtils.transformRect(
            render.getTransformTo(null),
            Offset.zero & render.size,
          );
          expect(
            rect.top,
            greaterThanOrEqualTo(bar.top - 0.5),
            reason: 'הטקסט יוצא מעל הסרגל',
          );
          expect(
            rect.bottom,
            lessThanOrEqualTo(bar.bottom + 0.5),
            reason: 'הטקסט יוצא מתחת לסרגל',
          );
        }
        await expectReachable(
          tester,
          run,
          find.byTooltip('חיפוש'),
          name: 'כפתור חיפוש',
        );
      },
    );
  });

  group('פריטי רשימת הקישורים נגישים במקלדת', () {
    final link = _ContentLink(
      heRef: 'רש"י על שבת',
      index1: 5,
      path2: 'רש"י על שבת',
      index2: 3,
      connectionType: 'commentary',
    );

    Future<List<OpenedTab>> pumpList(WidgetTester tester) async {
      final opened = <OpenedTab>[];
      // בלי דורות במטמון, המיון לפי דורות פונה למסד שאינו קיים בבדיקה.
      CommentaryService.seedEraCache({link.path2: CommentaryEra.acharonim});
      addTearDown(CommentaryService.clearEraCache);
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SettingsBloc>.value(
            value: StubSettingsBloc(),
            child: Scaffold(
              body: LinksListView(
                displayProfile: TextDisplayProfile.defaults,
                links: [link],
                chipSourceLinks: [link],
                openBookTitle: 'שבת',
                selectedLinkTypes: const {},
                onSelectedLinkTypesChanged: (_) {},
                openBookCallback: opened.add,
                fontSize: 16,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // הפריטים מקופלים עד הקשה על הכותרת.
      await tester.tap(find.textContaining('רש"י').first);
      await tester.pumpAndSettle();
      return opened;
    }

    final item = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_KeyboardActivatableItem',
    );

    testWidgets('הפריט חשוף לקורא מסך ככפתור עם פעולת הקשה', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpList(tester);
      expect(item, findsOneWidget);
      final node = tester.getSemantics(item).getSemanticsData();
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('Tab מגיע לפריט ו-Enter פותח את הקישור', (tester) async {
      final opened = await pumpList(tester);
      FocusNode? onItem;
      for (var i = 0; i < 12 && onItem == null; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focus = FocusManager.instance.primaryFocus;
        final context = focus?.context;
        if (context != null && _isInside(context, item.evaluate().single)) {
          onItem = focus;
        }
      }
      expect(onItem, isNotNull, reason: 'Tab לא הגיע לפריט הקישור');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(opened, hasLength(1), reason: 'Enter פותח את יעד הקישור');
    });
  });

  group('הדגשת פוקוס ב-BarSplitButton רק בניווט מקלדת', () {
    // InkWell מצייר מילוי פוקוס כל עוד הוא ממוקד, וגם אחרי לחיצת עכבר: בדסקטופ
    // לחיצת עכבר לא מוציאה את ההדגשה ממצב traditional.
    // מה שמצויר בפועל הוא ה-overlayColor במצב focused: InkWell נותן לו קדימות
    // על focusColor ברגע שהוא מחזיר ערך שאינו null.
    List<double> focusedOverlayAlphas(WidgetTester tester) => tester
        .widgetList<InkWell>(
          find.descendant(
            of: find.byType(BarSplitButton<String>),
            matching: find.byType(InkWell),
          ),
        )
        .map((w) => w.overlayColor!.resolve({WidgetState.focused})?.a ?? 0)
        .toList();

    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: BarSplitButton<String>(
              icon: FluentIcons.bookmark_24_regular,
              tooltip: 'שמור',
              onPressed: () {},
              entries: const [AppMenuEntry(value: 'a', label: 'אפשרות א')],
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    testWidgets('אחרי לחיצת עכבר אין מילוי פוקוס, אחרי Tab יש', (tester) async {
      await pump(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(
        location: tester.getCenter(
          find.byIcon(FluentIcons.bookmark_24_regular),
        ),
      );
      await mouse.down(
        tester.getCenter(find.byIcon(FluentIcons.bookmark_24_regular)),
      );
      await mouse.up();
      await tester.pump();
      expect(
        focusedOverlayAlphas(tester),
        everyElement(0),
        reason: 'מילוי הפוקוס לא נשאר אחרי עכבר',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab, character: null);
      await tester.pump();
      expect(
        focusedOverlayAlphas(tester),
        everyElement(closeTo(0.10, 0.005)),
        reason: 'אחרי Tab מוצג מילוי הפוקוס',
      );
    });
  });
}

/// קישור שתוכנו נטען מיד, בלי קובץ ספר.
class _ContentLink extends Link {
  _ContentLink({
    required super.heRef,
    required super.index1,
    required super.path2,
    required super.index2,
    required super.connectionType,
  });

  @override
  Future<String> get content => Future.value('פירוש קצר על הקטע');

  @override
  Future<String> get displayReference => Future.value(fallbackDisplayReference);
}

bool _isInside(BuildContext inner, Element ancestor) {
  var found = false;
  inner.visitAncestorElements((e) {
    if (identical(e, ancestor)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}
