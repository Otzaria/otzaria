import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
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
import 'package:otzaria/widgets/feedback/scrollable_positioned_list_scrollbar.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../test_helpers/memory_cache_provider.dart';

const int _lineCount = 40;

List<String> _content() =>
    List.generate(_lineCount, (i) => List.filled(40, 'מילה$i').join(' '));

TextBookLoaded _loadedState(List<String> content) => TextBookLoaded(
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
  scrollController: ItemScrollController(),
  positionsListener: ItemPositionsListener.create(),
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

  Future<void> pumpView(
    WidgetTester tester, {
    required bool isPreviewMode,
    required double textMaxWidth,
    Size size = const Size(900, 700),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final content = _content();
    final textBookBloc = _TestTextBookBloc(_loadedState(content));
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
            body: CombinedView(
              data: content,
              openBookCallback: (_) {},
              openLeftPaneTab: (_, {searchText}) {},
              textSize: 18,
              showCommentaryAsExpansionTiles: false,
              tab: tab,
              isPreviewMode: isPreviewMode,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// השוליים של השורה הראשונה משני צדי אזור התוכן של הרשימה. בתצוגה הרגילה
  /// המרווח שממרכז את הטקסט מול המסילה יושב בתוך הרשימה, בקצה הסוף.
  ({double start, double end}) lineInsets(
    WidgetTester tester, {
    double listEndPadding = ScrollablePositionedListScrollbar.trackWidth,
  }) {
    final list = tester.getRect(find.byType(ScrollablePositionedList));
    final line = tester.getRect(find.byType(SmartTextWidget).first);
    return (
      start: list.right - line.right,
      end: line.left - list.left - listEndPadding,
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
      await pumpView(tester, isPreviewMode: false, textMaxWidth: -1);
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
        textMaxWidth: -11,
        size: const Size(420, 700),
      );
      final insets = lineInsets(tester, listEndPadding: 0);
      expect(insets.start, 0.0);
      expect(insets.end, 0.0);
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
}
