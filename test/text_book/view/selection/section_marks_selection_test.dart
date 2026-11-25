// ignore: depend_on_referenced_packages
import 'package:irondash_message_channel/irondash_message_channel.dart';
// ignore: depend_on_referenced_packages
import 'package:super_native_extensions/src/native/context.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/text_book/view/selection/selected_text_copy.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut.dart';
import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut_dispatcher.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/migration/database/journal_mode.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_settings_bloc.dart';

const _content = [
  '(ח) ונח מצא חן בעיני ה׳',
  '(ט) אלה תולדת נח נח איש צדיק',
  '(י) ויולד נח שלשה בנים',
];

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {
      if (event is UpdateSelectedTextForNote) selected.add(event);
    });
  }

  final selected = <UpdateSelectedTextForNote>[];
  @override
  final TextBookRepository repository = _Repository();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository implements TextBookRepository {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final combined in [false, true]) {
    group(
      combined ? 'CombinedView' : 'SimpleTextViewer',
      () => _tests(combined),
    );
  }
}

void _tests(bool combined) {
  late Directory temporary;
  late StubSettingsBloc settings;
  late _TestNotesBloc notes;
  late _TestTextBookBloc bloc;
  final tabs = <TextBookTab>[];

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    temporary = await Directory.systemTemp.createTemp('section_selection');
    AppPaths.debugOverrideDataRootPath(temporary.path);
    final dbPath = '${temporary.path}/seforim.db';
    final database = MyDatabase.withPath(dbPath);
    final raw = await database.database;
    raw.execute(
      "INSERT INTO category (id, title, level) VALUES (7, 'כללי', 0)",
    );
    raw.execute("INSERT INTO source (id, name) VALUES (1, 'אוצריא')");
    raw.execute(
      "INSERT INTO book (id, categoryId, sourceId, title, totalLines) VALUES (1, 7, 1, 'ספר', 3)",
    );
    for (var i = 0; i < _content.length; i++) {
      raw.execute(
        'INSERT INTO line (id, bookId, lineIndex, content) VALUES (?, 1, ?, ?)',
        [i + 1, i, _content[i]],
      );
    }
    raw.execute(
      "INSERT INTO tocText (id, text) VALUES (1, 'כותרת מהמסד'), (2, 'סעיף בדיקה'), (3, 'כותרת נוספת')",
    );
    raw.execute(
      "INSERT INTO alt_toc_structure (id, bookId, key) VALUES (1, 1, 'Topic'), (2, 1, 'Seifim')",
    );
    raw.execute(
      'INSERT INTO alt_toc_entry (id, structureId, textId, level, lineId, hasChildren) VALUES (1, 1, 1, 1, 2, 0), (2, 2, 2, 1, 2, 0), (3, 1, 3, 2, 2, 0)',
    );
    database.close();
    await normalizeJournalModeForReadOnly(dbPath);
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      dbPath,
    );
    await SqliteDataProvider.instance.dispose();
    await SqliteDataProvider.instance.initialize();
    DatabaseLibraryProvider.instance.clearCache();
    await LibraryProviderManager.instance.resolveProviderForBook(
      'ספר',
      categoryId: 7,
      fileType: 'txt',
    );
    settings = StubSettingsBloc(
      SettingsState.initial().copyWith(
        copyWithHeaders: 'book_and_path',
        copyHeaderFormat: 'separate_line_before',
      ),
    );
    notes = _TestNotesBloc();
    bloc = _TestTextBookBloc(
      TextBookLoaded(
        book: _FixtureBook(),
        content: _content,
        fontSize: 18,
        showLeftPane: false,
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
        selectedIndex: 0,
        selectedIndices: const {0},
        searchText: '',
      ),
    );
  });

  tearDown(() async {
    UiSnack.hide();
    DbReadWorker.maxPendingWorkerReads = 64;
    DbReadWorker.workerSetUpForTesting = null;
    DbReadWorker.stallTimeout = const Duration(seconds: 10);
    DbReadWorker.admissionTimeout = const Duration(seconds: 10);
    DbReadWorker.disposeForTesting();
    await SqliteDataProvider.instance.dispose();
    await UserBooksDatabaseHolder.instance.close();
    DatabaseLibraryProvider.instance.clearCache();
    LibraryProviderManager.instance.resetForTesting();
    for (final tab in tabs) {
      tab.dispose();
    }
    tabs.clear();
    await bloc.close();
    await settings.close();
    await notes.close();
    AppPaths.debugOverrideDataRootPath(null);
    await temporary.delete(recursive: true);
  });

  TextBookTab tab({
    String? versionTitle,
    BookSource source = BookSource.official,
  }) {
    final value = TextBookTab(
      book: TextBook(
        id: 1,
        title: 'ספר',
        categoryId: 7,
        source: source,
        versionTitle: versionTitle,
      ),
      index: 0,
    );
    tabs.add(value);
    return value;
  }

  Future<void> mount(WidgetTester tester, TextBookTab value) async {
    final nav = _TestNavigationBloc();
    final tabsBloc = _TestTabsBloc(value);
    addTearDown(nav.close);
    addTearDown(tabsBloc.close);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: AppWindowKeys.current.navigator,
        locale: const Locale('he', 'IL'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('he', 'IL')],
        home: MultiBlocProvider(
          providers: [
            BlocProvider<NavigationBloc>.value(value: nav),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<TextBookBloc>.value(value: bloc),
            BlocProvider<PersonalNotesBloc>.value(value: notes),
            BlocProvider<SettingsBloc>.value(value: settings),
          ],
          child: Scaffold(
            body: combined
                ? CombinedView(
                    data: _content,
                    tab: value,
                    openBookCallback: (_) {},
                    openLeftPaneTab: (_, {searchText}) {},
                    textSize: 18,
                    showCommentaryAsExpansionTiles: false,
                    isPersonalNotesTabActive: () => true,
                    onSelectedTextChanged: (text, index, column) =>
                        bloc.selected.add(
                          UpdateSelectedTextForNote(
                            text: text,
                            sectionIndex: index,
                            start: column,
                            end: column == null || text == null
                                ? null
                                : column + text.length,
                          ),
                        ),
                  )
                : SimpleTextViewer(
                    isMainText: true,
                    isPersonalNotesTabActive: true,
                    content: _content,
                    tab: value,
                    openBookCallback: (_) {},
                    fontSize: 18,
                  ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> finishRead(WidgetTester tester) async {
    final deadline = Stopwatch()..start();
    do {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    } while (DbReadWorker.hasPendingReads &&
        deadline.elapsed < const Duration(seconds: 3));
    expect(DbReadWorker.hasPendingReads, isFalse);
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    UiSnack.hide();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('גרירה מתוך סמן סעיף ממפה מקור להעתקת פסקה ולהערה', (
    tester,
  ) async {
    final value = tab();
    await mount(tester, value);
    await finishRead(tester);
    final paragraph = tester.allRenderObjects
        .whereType<RenderParagraph>()
        .singleWhere((p) => p.text.toPlainText().contains('[סעיף בדיקה]'));
    final plain = paragraph.text.toPlainText();
    Rect wordRect(String word) {
      final i = plain.indexOf(word);
      final box = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: i, extentOffset: i + word.length),
          )
          .first
          .toRect();
      return Rect.fromPoints(
        paragraph.localToGlobal(box.topLeft),
        paragraph.localToGlobal(box.bottomRight),
      );
    }

    final from = wordRect('סעיף');
    final to = wordRect('צדיק');
    final gesture = await tester.startGesture(
      Offset(from.right - 1, from.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(Offset(to.left + 1, to.center.dy));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    final event = bloc.selected.lastWhere(
      (e) => e.text?.contains('אלה') ?? false,
    );
    expect(event.sectionIndex, 1);
    expect(event.text, _content[1]);
    expect(event.start, 0);
    expect(event.end, _content[1].length);
    final copied = <String>[];
    debugSelectedTextCopyHandler = (content) => copied.add(content.plainText);
    addTearDown(() => debugSelectedTextCopyHandler = null);
    value.dynamicCopyRequestNotifier.value = const DynamicCopyRequest(
      kind: DynamicShortcutKind.copySelectionWith,
      target: TextTarget.body,
      profile: TextDisplayProfile(anchorMarkers: MarkVisibility.hide),
    );
    await tester.pumpAndSettle();
    expect(copied.single, startsWith('ספר, מקום שני\n'));
    expect(copied.single, contains('סעיף בדיקה]'));
    expect(copied.single, endsWith(_content[1]));

    final native = superNativeExtensionsContext as MockMessageChannelContext;
    final providers = <dynamic>[];
    var writes = 0;
    native.registerMockMethodCallHandler('DataProviderManager', (call) async {
      if (call.method == 'registerDataProvider') {
        providers.add(call.arguments['representations']);
        return providers.length;
      }
      return null;
    });
    native.registerMockMethodCallHandler('ClipboardWriter', (call) async {
      if (call.method == 'writeToClipboard') writes++;
      return null;
    });
    value.dynamicCopyRequestNotifier.value = const DynamicCopyRequest(
      kind: DynamicShortcutKind.copyParagraphWith,
      target: TextTarget.body,
      profile: TextDisplayProfile(),
      plainTextOnly: true,
    );
    await tester.pumpAndSettle();
    expect(writes, 1);
    final expected = await Formats.plainText('ספר, מקום שני\n${_content[1]}');
    expect(
      providers.single,
      expected.representations.map((r) => r.serialize()),
    );

    final links = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            links.add(call.arguments['text'] as String);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final linkClick = await tester.startGesture(
      to.center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await linkClick.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('קישור'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('העתק קישור עם הדגשת הטקסט'));
    await tester.pumpAndSettle();
    final link = Uri.parse(links.single);
    expect(link.queryParameters['index'], '1');
    expect(link.queryParameters['m'], _content[1]);

    final rightClick = await tester.startGesture(
      to.center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await rightClick.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('הערה'));
    await tester.pumpAndSettle();
    final note = notes.events.whereType<StartCreatingPersonalNote>().single;
    expect(note.lineNumber, 2);
    expect(note.selectionColumn, 0);
    expect(note.sourceSelectionOffset, 0);
    expect(note.sourceSelectedText, _content[1]);
    await unmount(tester);
  });
  testWidgets('כותרת וגוף שומרים שיוך למקור והכותרת נשמרת בהעתקה', (
    tester,
  ) async {
    final value = tab();
    await mount(tester, value);
    await finishRead(tester);
    RenderParagraph paragraph(String text) => tester.allRenderObjects
        .whereType<RenderParagraph>()
        .singleWhere((p) => p.text.toPlainText().contains(text));
    final heading = paragraph('כותרת מהמסד');
    final body = paragraph('[סעיף בדיקה]');
    final headingBox = heading
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 1),
        )
        .first
        .toRect();
    final bodyText = body.text.toPlainText();
    final bodyBox = body
        .getBoxesForSelection(
          TextSelection(
            baseOffset: bodyText.length - 1,
            extentOffset: bodyText.length,
          ),
        )
        .last
        .toRect();
    final gesture = await tester.startGesture(
      heading.localToGlobal(Offset(headingBox.right - 1, headingBox.center.dy)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(
      body.localToGlobal(Offset(bodyBox.left + 1, bodyBox.center.dy)),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    final selected = bloc.selected.lastWhere(
      (e) => e.text?.contains('אלה') ?? false,
    );
    expect(selected.sectionIndex, 1);
    expect(selected.text, _content[1]);
    expect(selected.start, 0);
    expect(selected.end, _content[1].length);
    final copied = <String>[];
    debugSelectedTextCopyHandler = (content) => copied.add(content.plainText);
    addTearDown(() => debugSelectedTextCopyHandler = null);
    value.dynamicCopyRequestNotifier.value = const DynamicCopyRequest(
      kind: DynamicShortcutKind.copySelectionWith,
      target: TextTarget.body,
      profile: TextDisplayProfile(anchorMarkers: MarkVisibility.hide),
    );
    await tester.pumpAndSettle();
    expect(copied.single, startsWith('ספר, מקום שני\nכותרת מהמסד'));
    expect(copied.single, endsWith(_content[1]));
    final expected = copied.single;
    for (final point in [
      heading.localToGlobal(headingBox.center),
      body.localToGlobal(bodyBox.center),
    ]) {
      final click = await tester.startGesture(
        point,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await click.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('העתקה'));
      await tester.pumpAndSettle();
      expect(copied.last, expected);
    }
    await unmount(tester);
  });

  testWidgets('לחיצה ימנית על כותרת פותחת את תפריט השורה', (tester) async {
    await mount(tester, tab());
    await finishRead(tester);
    final heading = tester.allRenderObjects
        .whereType<RenderParagraph>()
        .singleWhere((p) => p.text.toPlainText().contains('כותרת מהמסד'));
    final rect = heading
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 5),
        )
        .first
        .toRect();
    final click = await tester.startGesture(
      heading.localToGlobal(rect.center),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await click.up();
    await tester.pumpAndSettle();
    expect(find.text('העתק את כל הפסקה'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await unmount(tester);
  });
  testWidgets(
    'גוף חוזר בשורה עם כותרת מקבל אופסט מקור; כותרת מחוץ לבחירה מבטלת אותה',
    (tester) async {
      final value = tab();
      await mount(tester, value);
      await finishRead(tester);
      Future<void> selectLastNoach() async {
        final paragraph = tester.allRenderObjects
            .whereType<RenderParagraph>()
            .singleWhere((p) => p.text.toPlainText().contains('נח נח'));
        final text = paragraph.text.toPlainText();
        final start = text.lastIndexOf('נח');
        final rect = paragraph
            .getBoxesForSelection(
              TextSelection(baseOffset: start, extentOffset: start + 2),
            )
            .first
            .toRect();
        final gesture = await tester.startGesture(
          paragraph.localToGlobal(Offset(rect.right - 1, rect.center.dy)),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.moveTo(
          paragraph.localToGlobal(Offset(rect.left + 1, rect.center.dy)),
        );
        await gesture.up();
        await tester.pumpAndSettle();
        final selection = bloc.selected.lastWhere((e) => e.text == 'נח');
        expect(selection.sectionIndex, 1);
        expect(selection.start, _content[1].lastIndexOf('נח'));
        expect(selection.end, _content[1].lastIndexOf('נח') + 2);
      }

      await selectLastNoach();
      final heading = tester.allRenderObjects
          .whereType<RenderParagraph>()
          .singleWhere((p) => p.text.toPlainText().contains('כותרת נוספת'));
      final rect = heading
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 5),
          )
          .first
          .toRect();
      final click = await tester.startGesture(
        heading.localToGlobal(rect.center),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await click.up();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      final copied = <String>[];
      debugSelectedTextCopyHandler = (content) => copied.add(content.plainText);
      addTearDown(() => debugSelectedTextCopyHandler = null);
      value.dynamicCopyRequestNotifier.value = const DynamicCopyRequest(
        kind: DynamicShortcutKind.copySelectionWith,
        target: TextTarget.body,
        profile: TextDisplayProfile(),
      );
      await tester.pumpAndSettle();
      expect(copied, isEmpty);
      await mount(tester, tab(versionTitle: 'אחרת'));
      await finishRead(tester);
      expect(
        tester.allRenderObjects.whereType<RenderParagraph>().any(
          (p) => p.text.toPlainText().contains('כותרת נוספת'),
        ),
        isFalse,
      );
      expect(
        tester.allRenderObjects.whereType<RenderParagraph>().any(
          (p) => p.text.toPlainText().contains('[סעיף בדיקה]'),
        ),
        isFalse,
      );
      await selectLastNoach();
      await unmount(tester);
    },
  );

  for (final part in ['כותרת', 'סעיף']) {
    testWidgets('$part בלבד נשאר ניתן להעתקה בלי טווח הערה ריק', (
      tester,
    ) async {
      final value = tab();
      await mount(tester, value);
      await finishRead(tester);
      final heading = tester.allRenderObjects
          .whereType<RenderParagraph>()
          .singleWhere(
            (p) => p.text.toPlainText().contains(
              part == 'כותרת' ? 'כותרת נוספת' : '[סעיף בדיקה]',
            ),
          );
      final start = heading.text.toPlainText().indexOf(part);
      final rect = heading
          .getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: start + part.length),
          )
          .first
          .toRect();
      final gesture = await tester.startGesture(
        heading.localToGlobal(Offset(rect.right - 1, rect.center.dy)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(
        heading.localToGlobal(Offset(rect.left + 1, rect.center.dy)),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      final selected = bloc.selected.lastWhere((e) => e.text == '');
      expect(selected.sectionIndex, 1);
      expect(selected.start, 0);
      expect(selected.end, 0);
      final copied = <String>[];
      debugSelectedTextCopyHandler = (content) => copied.add(content.plainText);
      addTearDown(() => debugSelectedTextCopyHandler = null);
      value.dynamicCopyRequestNotifier.value = const DynamicCopyRequest(
        kind: DynamicShortcutKind.copySelectionWith,
        target: TextTarget.body,
        profile: TextDisplayProfile(anchorMarkers: MarkVisibility.hide),
      );
      await tester.pumpAndSettle();
      expect(copied.single, 'ספר, מקום שני\n$part');
      final click = await tester.startGesture(
        heading.localToGlobal(rect.center),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await click.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('העתקה'));
      await tester.pumpAndSettle();
      expect(copied.last, 'ספר, מקום שני\n$part');
      final links = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              links.add(call.arguments['text'] as String);
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final linkClick = await tester.startGesture(
        heading.localToGlobal(rect.center),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await linkClick.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('קישור'));
      await tester.pumpAndSettle();
      expect(find.text('העתק קישור עם הדגשת הטקסט'), findsNothing);
      await tester.tap(find.text('העתק קישור למקטע זה'));
      await tester.pumpAndSettle();
      final link = Uri.parse(links.single);
      expect(link.queryParameters['index'], '1');
      expect(link.queryParameters.containsKey('m'), isFalse);
      final noteClick = await tester.startGesture(
        heading.localToGlobal(rect.center),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await noteClick.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('הערה'));
      await tester.pumpAndSettle();
      final note = notes.events.whereType<StartCreatingPersonalNote>().single;
      expect(note.lineNumber, 2);
      expect(note.sourceSelectedText, isNull);
      expect(note.sourceSelectionOffset, isNull);
      expect(note.referenceText, startsWith('(ט) אלה תולדת נח'));
      await unmount(tester);
    });
  }

  testWidgets(
    'כמה כותרות ושתי שורות מקור נשמרות בלחיצה ימנית על כל חלק מסומן',
    (tester) async {
      final value = tab();
      await mount(tester, value);
      await finishRead(tester);
      RenderParagraph paragraph(String text) => tester.allRenderObjects
          .whereType<RenderParagraph>()
          .singleWhere((p) => p.text.toPlainText().contains(text));
      Rect rect(RenderParagraph p, int start, int end) => p
          .getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: end),
          )
          .first
          .toRect();
      final heading = paragraph('כותרת מהמסד');
      final secondHeading = paragraph('כותרת נוספת');
      final firstBody = paragraph('נח נח');
      final lastBody = paragraph('שלשה בנים');
      final from = rect(heading, 0, 1);
      final length = lastBody.text.toPlainText().length;
      final to = rect(lastBody, length - 1, length);
      final gesture = await tester.startGesture(
        heading.localToGlobal(Offset(from.right - 1, from.center.dy)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(
        lastBody.localToGlobal(Offset(to.left + 1, to.center.dy)),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      final selected = bloc.selected.lastWhere(
        (e) => e.text?.contains('אלה') ?? false,
      );
      expect(selected.sectionIndex, 1);
      expect(selected.text, '${_content[1]}\n${_content[2]}');
      final copied = <String>[];
      debugSelectedTextCopyHandler = (content) => copied.add(content.plainText);
      addTearDown(() => debugSelectedTextCopyHandler = null);
      for (final p in [heading, secondHeading, firstBody, lastBody]) {
        final point = p.localToGlobal(rect(p, 0, 1).center);
        final click = await tester.startGesture(
          point,
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await click.up();
        await tester.pumpAndSettle();
        await tester.tap(find.text('העתקה'));
        await tester.pumpAndSettle();
        expect(copied.last, contains('כותרת מהמסד\nכותרת נוספת\n'));
        expect(copied.last, contains('${_content[1]}\n${_content[2]}'));
      }
      await unmount(tester);
    },
  );
}

class _TestNavigationBloc extends Bloc<NavigationEvent, NavigationState>
    implements NavigationBloc {
  _TestNavigationBloc()
    : super(const NavigationState(currentScreen: Screen.reading));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _TestTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _TestTabsBloc(TextBookTab tab)
    : super(TabsState(tabs: [tab], currentTabIndex: 0));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FixtureBook extends TextBook {
  _FixtureBook() : super(id: 1, title: 'ספר', categoryId: 7);
  @override
  Future<List<TocEntry>> get tableOfContents async => [
    TocEntry(text: 'מקום ראשון', index: 0, level: 2),
    TocEntry(text: 'מקום שני', index: 1, level: 2),
  ];
}

class _TestNotesBloc extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _TestNotesBloc() : super(const PersonalNotesState.initial()) {
    on<PersonalNotesEvent>((event, emit) => events.add(event));
  }
  final events = <PersonalNotesEvent>[];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
