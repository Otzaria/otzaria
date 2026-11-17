import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor_dialog.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import '../test_helpers/memory_cache_provider.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';

final _reference = List.filled(
  40,
  'טקסט ארוך מן הספר עם הקשר להערה.',
).join(' ');
final _editorBox = find.ancestor(
  of: find.byType(quill.QuillEditor),
  matching: find.byWidgetPredicate(
    (widget) => widget is SizedBox && widget.child is RawGestureDetector,
  ),
);
final _outerScroll = find.ancestor(
  of: find.byType(quill.QuillEditor),
  matching: find.byType(Scrollable),
);
final _save = find.widgetWithText(ActionButton, 'שמור');

Future<void> _open(
  WidgetTester tester, {
  required Size size,
  double inset = 0,
  double scale = 1,
  Brightness brightness = Brightness.light,
  AppThemeVariant variant = AppThemeVariant.standard,
  Future<void> Function(PersonalNoteEditorResult)? onSave,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: inset);
  addTearDown(tester.view.reset);
  final cs = AppThemeData.createColorScheme(Colors.blueGrey, brightness);
  await tester.pumpWidget(
    RepositoryProvider(
      create: (_) => SettingsRepository(),
      child: BlocProvider(
        create: (context) =>
            SettingsBloc(repository: context.read<SettingsRepository>()),
        child: MaterialApp(
          theme: brightness == Brightness.dark
              ? AppThemeData.dark(cs, compactMenuMode: false)
              : AppThemeData.light(
                  cs,
                  compactMenuMode: false,
                  variant: variant,
                ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: ActionButton.neutral(
                text: 'פתח',
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => PersonalNoteEditorDialog(
                    title: 'עריכת הערה עם כותרת ארוכה במיוחד מתוך הספר',
                    referenceText: _reference,
                    initialContent: List.filled(
                      50,
                      'שורת הערה לעריכה',
                    ).join('\n'),
                    onSave: onSave,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('פתח'));
  await tester.pumpAndSettle();
}

void _expectUsable(WidgetTester tester, Size size, double inset) {
  expect(tester.takeException(), isNull);
  final screen = Offset.zero & Size(size.width, size.height - inset);
  final save = tester.getRect(_save);
  expect(screen.contains(save.topLeft), isTrue);
  expect(screen.contains(save.bottomRight), isTrue);
  expect(_save.hitTestable(), findsOneWidget);
  final editor = tester.widget<quill.QuillEditor>(
    find.byType(quill.QuillEditor),
  );
  var visibleEditor = tester.getRect(_editorBox);
  var visibleText = tester
      .getRect(_editorBox)
      .deflate(editor.config.padding.resolve(TextDirection.rtl).top);
  for (final element in _outerScroll.evaluate()) {
    final viewport = tester.getRect(
      find.byElementPredicate((e) => e == element),
    );
    visibleText = visibleText.intersect(viewport);
    visibleEditor = visibleEditor.intersect(viewport);
  }
  visibleText = visibleText.intersect(screen);
  visibleEditor = visibleEditor.intersect(screen);
  // שורת טקסט נראית גם אחרי חיתוך viewport וריפוד Quill, ולא רק RenderBox גדול.
  expect(visibleText.height, greaterThanOrEqualTo(32));
  expect(visibleText.width, greaterThan(100));
  expect(editor.focusNode.hasFocus, isTrue);
  final renderEditor = tester
      .state<quill.QuillRawEditorState>(find.byType(quill.QuillRawEditor))
      .renderEditor;
  final caret = renderEditor.getLocalRectForCaret(
    TextPosition(offset: editor.controller.selection.extentOffset),
  );
  final globalCaret = caret.shift(renderEditor.localToGlobal(Offset.zero));
  expect(globalCaret.top, greaterThanOrEqualTo(visibleEditor.top - 1));
  expect(globalCaret.bottom, lessThanOrEqualTo(visibleEditor.bottom + 1));
}

void main() {
  setUp(() async => Settings.init(cacheProvider: MemoryCacheProvider()));
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => '/tmp');
  });

  for (final theme in [
    (Brightness.light, AppThemeVariant.standard),
    (Brightness.dark, AppThemeVariant.standard),
    (Brightness.light, AppThemeVariant.white),
  ]) {
    for (final scenario in [
      (const Size(360, 640), 360.0),
      (const Size(640, 360), 180.0),
      (const Size(1200, 640), 360.0),
      (const Size(360, 800), 0.0),
      (const Size(1200, 800), 0.0),
    ]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('מקלדת ${theme.$1}/${theme.$2} ${scenario.$1} ×$scale', (
          tester,
        ) async {
          await _open(
            tester,
            size: scenario.$1,
            inset: scenario.$2,
            scale: scale,
            brightness: theme.$1,
            variant: theme.$2,
          );
          _expectUsable(tester, scenario.$1, scenario.$2);
          expect(
            find.ancestor(of: _save, matching: find.byType(AppDialogHeader)),
            scenario.$1.height - scenario.$2 < 480
                ? findsOneWidget
                : findsNothing,
          );
          final editor = tester.widget<quill.QuillEditor>(
            find.byType(quill.QuillEditor),
          );
          editor.scrollController.jumpTo(
            editor.scrollController.position.maxScrollExtent,
          );
          await tester.pump();
          expect(editor.scrollController.offset, greaterThan(0));
          final outerStates = tester
              .stateList<ScrollableState>(_outerScroll)
              .toList();
          if (outerStates.isNotEmpty) {
            await tester.ensureVisible(find.byTooltip('מודגש'));
          }
          await tester.pumpAndSettle();
          expect(find.byTooltip('מודגש').hitTestable(), findsOneWidget);
          await tester.tap(find.byTooltip('מודגש'));
          await tester.pumpAndSettle();
          expect(
            editor.controller.getSelectionStyle().attributes,
            contains('bold'),
          );
          for (final body in outerStates) {
            body.position.jumpTo(body.position.maxScrollExtent);
          }
          editor.controller.replaceText(
            0,
            0,
            'נוסף ',
            const TextSelection.collapsed(offset: 5),
          );
          await tester.pumpAndSettle();
          expect(editor.controller.document.toPlainText(), startsWith('נוסף '));
          _expectUsable(tester, scenario.$1, scenario.$2);
        });
      }
    }
  }

  testWidgets(
    'פתיחה וסגירה של המקלדת שומרות מסמך, בחירה, undo ופוקוס עד השמירה',
    (tester) async {
      const size = Size(360, 640);
      PersonalNoteEditorResult? saved;
      await _open(tester, size: size, onSave: (result) async => saved = result);
      final before = tester.widget<quill.QuillEditor>(
        find.byType(quill.QuillEditor),
      );
      final rawState = tester.state(find.byType(quill.QuillRawEditor));
      before.controller.replaceText(
        0,
        0,
        'חדש ',
        const TextSelection.collapsed(offset: 4),
      );
      await tester.pumpAndSettle();
      for (final inset in [360.0, 0.0, 360.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        await tester.pumpAndSettle();
        final after = tester.widget<quill.QuillEditor>(
          find.byType(quill.QuillEditor),
        );
        expect(after.controller, same(before.controller));
        expect(after.focusNode, same(before.focusNode));
        expect(tester.state(find.byType(quill.QuillRawEditor)), same(rawState));
        expect(
          after.controller.selection,
          const TextSelection.collapsed(offset: 4),
        );
        expect(after.controller.hasUndo, isTrue);
        _expectUsable(tester, size, inset);
      }
      before.controller.undo();
      await tester.pumpAndSettle();
      expect(
        before.controller.document.toPlainText(),
        isNot(startsWith('חדש ')),
      );
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(find.byType(PersonalNoteEditorDialog), findsNothing);
    },
  );

  testWidgets('Escape בכותרת עם מקלדת פתוחה סוגר בלי לשנות הערה', (
    tester,
  ) async {
    await _open(tester, size: const Size(360, 640), inset: 360);
    final save = tester.widget<ActionButton>(_save);
    save.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PersonalNoteEditorDialog), findsNothing);
  });
  for (final closeFromHeader in [false, true]) {
    testWidgets(
      'שינויים לא נשמרים בסגירה ${closeFromHeader ? 'מהכותרת' : 'ב-Escape'} עם מקלדת',
      (tester) async {
        await _open(tester, size: const Size(360, 640), inset: 200);
        final editor = tester.widget<quill.QuillEditor>(
          find.byType(quill.QuillEditor),
        );
        editor.controller.replaceText(
          0,
          0,
          'טיוטה ',
          const TextSelection.collapsed(offset: 6),
        );
        await tester.pumpAndSettle();
        if (closeFromHeader) {
          await tester.tap(find.byTooltip('סגור'));
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        }
        await tester.pumpAndSettle();
        expect(editor.focusNode.hasFocus, isFalse);
        expect(find.text('ההערה לא נשמרה. לשמור טיוטה?'), findsOneWidget);
        await tester.tap(find.widgetWithText(ActionButton, 'ביטול'));
        await tester.pumpAndSettle();
        expect(find.byType(PersonalNoteEditorDialog), findsOneWidget);
        expect(editor.controller.document.toPlainText(), startsWith('טיוטה '));
      },
    );
  }
  testWidgets('Enter בשמור שבכותרת שומר עם מקלדת פתוחה', (tester) async {
    PersonalNoteEditorResult? saved;
    await _open(
      tester,
      size: const Size(360, 640),
      inset: 360,
      onSave: (result) async => saved = result,
    );
    tester.widget<ActionButton>(_save).focusNode!.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(find.byType(PersonalNoteEditorDialog), findsNothing);
  });
}
