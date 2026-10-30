import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/widgets/selection_gutter_painter.dart';
import 'package:otzaria/widgets/feedback/scrollable_positioned_list_scrollbar.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/layout/reading_area_width.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

import '../../../test_helpers/memory_cache_provider.dart';

const int _lineCount = 40;

List<String> _content([int lineCount = _lineCount]) =>
    List.generate(lineCount, (i) => List.filled(40, 'מילה$i').join(' '));

TextBookLoaded _loadedState(
  List<String> content, {
  BookProtection protection = BookProtection.none,
}) => TextBookLoaded(
  book: TextBook(title: 'ספר בדיקה'),
  showLeftPane: false,
  content: content,
  fontSize: 18,
  showSplitView: false,
  showPageShapeView: false,
  activeCommentators: const [],
  commentatorGroups: const [],
  availableCommentators: const [],
  links: const [],
  visibleLinks: const [],
  linksByLine: const {},
  tableOfContents: const [],
  removeNikud: false,
  visibleIndices: const [0],
  selectedIndex: null,
  pinLeftPane: false,
  searchText: '',
  protection: protection,
);

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _TestPersonalNotesBloc(super.initialState) {
    on<PersonalNotesEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// כמה פיקסלים הדיו של [word] בולט משמאל לתיבת המילה, כלומר אחרי סופה.
Future<double> _inkPastWordEnd(WidgetTester tester, String word) async {
  final painter = TextPainter(
    text: TextSpan(
      text: word,
      style: const TextStyle(
        fontFamily: 'FrankRuhlCLM',
        fontSize: 60,
        color: Color(0xFF000000),
      ),
    ),
    textDirection: TextDirection.rtl,
  )..layout();
  const origin = 100, width = 600, height = 160;
  var minX = width;
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Offset(origin + 0.0, 20));
    final image = await recorder.endRecording().toImage(width, height);
    final bytes = (await image.toByteData())!;
    image.dispose();
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < minX; x++) {
        if (bytes.getUint8((y * width + x) * 4 + 3) > 0) minX = x;
      }
    }
  });
  painter.dispose();
  return (origin - minX).toDouble();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    final font = File('fonts/FrankRuehlCLM-Medium.ttf').readAsBytesSync();
    final loader = FontLoader('FrankRuhlCLM')
      ..addFont(Future.value(ByteData.sublistView(font)));
    await loader.load();
  });

  Future<TextBookTab> pumpView(
    WidgetTester tester, {
    required bool isPreviewMode,
    required double textMaxWidth,
    Size size = const Size(900, 700),
    BookProtection protection = BookProtection.none,
    int lineCount = _lineCount,
    Widget Function(Widget view)? wrap,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final content = _content(lineCount);
    final textBookBloc = _TestTextBookBloc(
      _loadedState(content, protection: protection),
    );
    final personalNotesBloc = _TestPersonalNotesBloc(
      const PersonalNotesState.initial(),
    );
    final settingsBloc = _TestSettingsBloc(
      SettingsState.initial().copyWith(textMaxWidth: textMaxWidth),
    );
    final tab = TextBookTab(book: TextBook(title: 'ספר בדיקה'), index: 0);
    addTearDown(textBookBloc.close);
    addTearDown(personalNotesBloc.close);
    addTearDown(settingsBloc.close);
    addTearDown(tab.dispose);

    final view = CombinedView(
      data: content,
      openBookCallback: (_) {},
      openLeftPaneTab: (_, {searchText}) {},
      textSize: 18,
      showCommentaryAsExpansionTiles: false,
      tab: tab,
      isPreviewMode: isPreviewMode,
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he', 'IL'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('he', 'IL')],
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: wrap == null ? view : wrap(view),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return tab;
  }

  /// השוליים של השורה הראשונה משני צדי אזור התוכן של הרשימה, מעבר לשולי סמן
  /// הבחירה. בתצוגה הרגילה המרווח שממרכז את הטקסט מול המסילה יושב בתוך הרשימה,
  /// בקצה הסוף.
  ({double start, double end}) lineInsets(
    WidgetTester tester, {
    double listEndPadding = ScrollablePositionedListScrollbar.trackWidth,
  }) {
    final list = tester.getRect(find.byType(ScrollablePositionedList));
    final line = tester.getRect(find.byType(SmartTextWidget).first);
    return (
      start: list.right - line.right - kSelectionGutterWidth,
      end: line.left - list.left - listEndPadding - kSelectionGutterWidth,
    );
  }

  /// השוליים של השורה הראשונה משני צדי אזור הקריאה כולו — כולל המסילה.
  ({double start, double end}) viewportInsets(WidgetTester tester) {
    final area = tester.getRect(find.byType(CombinedView));
    final line = tester.getRect(find.byType(SmartTextWidget).first);
    return (start: area.right - line.right, end: line.left - area.left);
  }

  group('שולי עמודת הטקסט בתצוגה המשולבת', () {
    testWidgets('ללא הגבלת רוחב — הטקסט ממלא את הרשימה בשני הצדדים', (
      tester,
    ) async {
      await pumpView(tester, isPreviewMode: false, textMaxWidth: 0);
      final insets = lineInsets(tester);
      expect(insets.start, 0.0);
      expect(insets.end, 0.0);
    });

    testWidgets('עם הגבלת רוחב — השוליים שווים בשני הצדדים', (tester) async {
      await pumpView(tester, isPreviewMode: false, textMaxWidth: 500);
      final insets = lineInsets(tester);
      expect(insets.start, greaterThan(0));
      expect(insets.start, closeTo(insets.end, 0.5));
    });

    testWidgets('הטקסט ממורכז בין דפנות אזור הקריאה, לא רק בתוך הרשימה', (
      tester,
    ) async {
      await pumpView(tester, isPreviewMode: false, textMaxWidth: 0);
      expect(
        find.byKey(ScrollablePositionedListScrollbar.thumbKey),
        findsOneWidget,
        reason: 'בלי מסילה מוצגת אין מה למדוד',
      );
      final insets = viewportInsets(tester);
      expect(insets.start, closeTo(insets.end, 0.5));
    });

    testWidgets('בתצוגה מקדימה הגבלת הרוחב אינה מצרה את הטקסט', (tester) async {
      await pumpView(
        tester,
        isPreviewMode: true,
        textMaxWidth: 300,
        size: const Size(420, 700),
      );
      final insets = lineInsets(tester, listEndPadding: 0);
      expect(insets.start, 0.0);
      expect(insets.end, 0.0);
    });

    testWidgets(
      'גרירת חלון שמצרה את העמודה ברשימה גדולה נדחית עד שהרוחב מתייצב',
      (
        tester,
      ) async {
        final tab = await pumpView(
          tester,
          isPreviewMode: false,
          textMaxWidth: 800,
          lineCount: 5000,
        );
        final list = tab.lines.itemController.listController!;
        Object? estimationKey() => tester
            .widget<ScrollablePositionedList>(
              find.byType(ScrollablePositionedList),
            )
            .estimationKey;
        final key = estimationKey();
        final refreshes = list.estimateRefreshStats!.refreshCount;
        final before = list.extentForIndex(4999).$1;

        for (var frame = 1; frame <= 10; frame++) {
          final width = 900.0 - 30 * frame;
          tester.view.physicalSize = Size(width, 700);
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            list.estimateRefreshStats!.refreshCount,
            refreshes,
            reason: 'פריים $frame',
          );
        }
        expect(estimationKey(), same(key));
        await tester.pump();
        await tester.pump();
        expect(list.estimateRefreshStats!.refreshCount, refreshes + 1);
        expect(list.extentForIndex(4999).$1, greaterThan(before));
      },
    );

    /// מודד את פריט 0, קופץ לסוף ומצר את הרשימה בלי לשנות את עמודת הטקסט.
    Future<(double, bool)> firstItemAfterNarrowing(
      WidgetTester tester, {
      BookProtection protection = BookProtection.none,
    }) async {
      final tab = await pumpView(
        tester,
        isPreviewMode: false,
        textMaxWidth: 500,
        protection: protection,
      );
      final list = tab.lines.itemController.listController!;
      final firstLine = find.byKey(const ValueKey('html_ספר בדיקה_0'));
      expect(firstLine, findsOneWidget);
      expect(list.extentForIndex(0).$2, isFalse);

      tab.lines.itemController.jumpTo(index: _lineCount - 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(firstLine, findsNothing, reason: 'פריט 0 מחוץ לאזור המטמון');

      tester.view.physicalSize = const Size(800, 700);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      return list.extentForIndex(0);
    }

    testWidgets(
      'שינוי רוחב שאינו משנה את עמודת הטקסט שומר מדידות של פריטים מחוץ למסך',
      (tester) async {
        final (_, estimated) = await firstItemAfterNarrowing(tester);
        expect(estimated, isFalse);
      },
    );

    testWidgets('עם באנר מקור ברוחב מלא שינוי הרוחב מרענן את ההערכות', (
      tester,
    ) async {
      final (_, estimated) = await firstItemAfterNarrowing(
        tester,
        protection: const BookProtection(bannerText: 'מקור הספר'),
      );
      expect(estimated, isTrue);
    });

    testWidgets('טעם שבולט אחרי המילה האחרונה בשורה אינו נחתך (issue #1791)', (
      tester,
    ) async {
      // סגול וזרקא (מלכים ב כג, יג) בגודל הגופן המרבי.
      var overhang = 0.0;
      for (final word in ['הַמַּשְׁחִית֒', 'הַמַּשְׁחִית֮']) {
        overhang = max(overhang, await _inkPastWordEnd(tester, word));
      }
      expect(overhang, greaterThan(0), reason: 'בלי בליטה אין מה להוכיח');

      await pumpView(tester, isPreviewMode: false, textMaxWidth: 0);
      final line = tester.renderObject<RenderBox>(
        find.byType(SmartTextWidget).first,
      );
      final clip = RenderAbstractViewport.of(line) as RenderBox;
      final room =
          line.localToGlobal(Offset.zero).dx -
          clip.localToGlobal(Offset.zero).dx;
      expect(room, greaterThanOrEqualTo(overhang));
    });
  });

  group('רוחב יעד קבוע', () {
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    /// רוחב עמודת הטקסט ורוחב הפריט שבתוכו היא ממורכזת; null כשאין הגבלה.
    ({double column, double item})? column(WidgetTester tester) {
      final box = find.ancestor(
        of: find.byType(SmartTextWidget).first,
        matching: find.byWidgetPredicate(
          (w) => w is ConstrainedBox && w.constraints.maxWidth.isFinite,
        ),
      );
      if (box.evaluate().isEmpty) return null;
      final item = find.ancestor(of: box.first, matching: find.byType(Center));
      return (
        column: tester.getSize(box.first).width,
        item: tester.getSize(item.first).width,
      );
    }

    testWidgets('שינוי חלון ולוח שכן ב-Row לא משנים את העמודה כשיש מקום', (
      tester,
    ) async {
      final panel = ValueNotifier<bool>(false);
      addTearDown(panel.dispose);
      await pumpView(
        tester,
        isPreviewMode: false,
        textMaxWidth: 600,
        size: const Size(1400, 700),
        wrap: (view) => ValueListenableBuilder<bool>(
          valueListenable: panel,
          builder: (_, open, _) => Row(
            children: [
              if (open) const SizedBox(width: 300),
              Expanded(child: view),
            ],
          ),
        ),
      );
      expect(column(tester)!.column, 600);

      tester.view.physicalSize = const Size(1000, 700);
      await settle(tester);
      expect(column(tester)!.column, 600);

      panel.value = true;
      await settle(tester);
      expect(column(tester)!.column, 600);

      panel.value = false;
      await settle(tester);
      expect(column(tester)!.column, 600);

      tester.view.physicalSize = const Size(500, 700);
      await settle(tester);
      final narrow = column(tester)!;
      expect(narrow.column, narrow.item - 2 * kTextColumnMinMargin);
    });

    testWidgets('פתיחה וסגירה של AdaptiveSidePane לא משנות את העמודה', (
      tester,
    ) async {
      final pane = ValueNotifier<bool>(false);
      addTearDown(pane.dispose);
      await pumpView(
        tester,
        isPreviewMode: false,
        textMaxWidth: 600,
        size: const Size(1400, 700),
        wrap: (view) => ValueListenableBuilder<bool>(
          valueListenable: pane,
          builder: (_, open, _) => AdaptiveSidePane(
            isOpen: open,
            mainContent: view,
            paneContent: const Text('מפרשים'),
            paneWidth: 340,
            onClose: () {},
            autoHandleResponsiveVisibility: false,
          ),
        ),
      );
      expect(column(tester)!.column, 600);

      pane.value = true;
      await settle(tester);
      expect(column(tester)!.column, 600);

      pane.value = false;
      await settle(tester);
      expect(column(tester)!.column, 600);
    });

    testWidgets('רוחב מלא (0) — אין עמודה מוגבלת גם אחרי שינוי חלון', (
      tester,
    ) async {
      await pumpView(
        tester,
        isPreviewMode: false,
        textMaxWidth: 0,
        size: const Size(1400, 700),
      );
      expect(column(tester), isNull);

      tester.view.physicalSize = const Size(1000, 700);
      await settle(tester);
      expect(column(tester), isNull);
    });
  });
}
