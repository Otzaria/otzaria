import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
// ignore: depend_on_referenced_packages
import 'package:irondash_message_channel/irondash_message_channel.dart';
import 'package:super_native_extensions/src/native/context.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/text_book/view/selection/selected_text_drag.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_settings_bloc.dart';

const _title = 'ספר בדיקה';

final _content = List<String>.generate(
  50,
  (i) =>
      '<b>($i) מילים${String.fromCharCode(0x5d0 + i % 22)}${String.fromCharCode(0x5d0 + i ~/ 22)} בפסקה שונות:</b>',
);

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  void emitForTest(TextBookState state) => emit(state);

  @override
  final TextBookRepository repository = _TestTextBookRepository();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTextBookRepository implements TextBookRepository {
  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => const [];

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messages = <String>[];
  final mock = MockMessageChannelContext();
  setContextOverride(mock);
  mock.registerMockMethodCallHandler('DataProviderManager', (call) {
    if (call.method == 'registerDataProvider') {
      final reps = (call.arguments as Map)['representations'] as Iterable;
      final plain = (reps.first as Map)['data'] as String;
      messages.add(plain);
      throw StateError('stop after inspecting drag payload');
    }
    return null;
  });
  setUp(() => messages.clear());
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<TextBookTab> pumpView(
    WidgetTester tester, {
    Size size = const Size(700, 600),
    int anchor = 0,
    BookProtection protection = BookProtection.none,
    bool pageShape = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final state = TextBookLoaded(
      book: TextBook(title: _title),
      protection: protection,
      showLeftPane: false,
      content: _content,
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
      visibleIndices: List<int>.generate(_content.length, (index) => index),
      selectedIndex: null,
      pinLeftPane: false,
      searchText: '',
    );
    final textBookBloc = _TestTextBookBloc(state);
    final personalNotesBloc = _TestPersonalNotesBloc(
      const PersonalNotesState.initial(),
    );
    final settingsBloc = StubSettingsBloc(SettingsState.initial());
    final tab = TextBookTab(
      book: TextBook(title: _title),
      index: anchor,
    );
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
            body: pageShape
                ? SimpleTextViewer(
                    content: _content,
                    fontSize: 18,
                    isMainText: true,
                    openBookCallback: (_) {},
                  )
                : CombinedView(
                    data: _content,
                    openBookCallback: (_) {},
                    openLeftPaneTab: (_, {searchText}) {},
                    textSize: 18,
                    showCommentaryAsExpansionTiles: false,
                    tab: tab,
                  ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return tab;
  }

  RenderParagraph paragraphFor(WidgetTester tester, int index) {
    final root = tester.renderObject(find.byType(SelectedTextDragRegion).first);
    RenderParagraph? found;
    void visit(RenderObject object) {
      if (object is RenderParagraph &&
          object.text.toPlainText().contains('($index)')) {
        found ??= object;
      } else {
        object.visitChildren(visit);
      }
    }

    visit(root);
    return found!;
  }

  for (final pageShape in [false, true]) {
    testWidgets(
      'native drag preserves source protection (pageShape=$pageShape)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await pumpView(
          tester,
          pageShape: pageShape,
          size: const Size(700, 3000),
          protection: const BookProtection(level: 1),
        );
        tester
            .state<SelectableRegionState>(find.byType(SelectableRegion).first)
            .selectAll();
        await tester.pump();
        final original = tester
            .widget<SelectedTextDragRegion>(
              find.byType(SelectedTextDragRegion).first,
            )
            .selectedText()!;
        final paragraph = paragraphFor(tester, 2);
        final box = paragraph
            .getBoxesForSelection(
              const TextSelection(baseOffset: 6, extentOffset: 7),
            )
            .first
            .toRect();
        final point = paragraph.localToGlobal(box.center);
        final gesture = await tester.startGesture(
          point,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(milliseconds: 200));
        await gesture.moveBy(const Offset(-12, 0));
        await tester.pump();
        final live = tester
            .widget<SelectedTextDragRegion>(
              find.byType(SelectedTextDragRegion).first,
            )
            .selectedText();
        await gesture.moveBy(const Offset(-20, 0));
        await tester.pump();
        await gesture.up();
        await tester.pump();
        debugDefaultTargetPlatformOverride = null;
        expect(original.split('\n').length, greaterThan(40));
        expect(
          live,
          isNot(original),
          reason:
              'Flutter changed its live selection before the drag threshold',
        );
        expect(
          messages,
          isEmpty,
          reason: 'publisher forbids exporting more than 40 source segments',
        );
      },
    );
    testWidgets(
      'drag snapshot retains original HTML and source (pageShape=$pageShape)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await pumpView(
          tester,
          pageShape: pageShape,
          size: const Size(700, 3000),
        );
        final paragraph = paragraphFor(tester, 2);
        final box = paragraph
            .getBoxesForSelection(
              const TextSelection(baseOffset: 4, extentOffset: 11),
            )
            .single
            .toRect();
        final select = await tester.startGesture(
          paragraph.localToGlobal(Offset(box.right - 0.1, box.center.dy)),
          kind: PointerDeviceKind.mouse,
        );
        await select.moveTo(
          paragraph.localToGlobal(Offset(box.left + 0.1, box.center.dy)),
        );
        await tester.pump();
        await select.up();
        await tester.pump(const Duration(milliseconds: 600));
        final region = tester.widget<SelectedTextDragRegion>(
          find.byType(SelectedTextDragRegion).first,
        );
        final original = region.selectedText()!;
        final prepare = region.captureContent(original)!;
        tester
            .state<SelectableRegionState>(find.byType(SelectableRegion).first)
            .selectAll();
        await tester.pump();
        expect(region.selectedText(), isNot(original));
        final result = await prepare();
        debugDefaultTargetPlatformOverride = null;
        expect(result, isNotNull);
        expect(result!.plainText, contains(original));
        expect(result.htmlText, contains('<b>'));
        expect(result.plainText, isNot(contains('(49)')));
      },
    );
  }
}
