// ignore: depend_on_referenced_packages
import 'package:irondash_message_channel/irondash_message_channel.dart';
// ignore: depend_on_referenced_packages
import 'package:super_native_extensions/src/native/context.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/text_book/view/selection/selected_text_copy.dart';
import 'package:otzaria/shortcuts/keyboard_shortcuts.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut.dart';
import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut_registry.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/book_protection/repository/book_protection_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_personal_notes_bloc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';
import '../../../test_helpers/stub_text_book_bloc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => ShortcutHelper.isMacForTesting = false);
  tearDown(() => ShortcutHelper.isMacForTesting = null);
  setUp(
    () =>
        BookProtectionRepository.instance.debugRepositoryFor = (_) async =>
            null,
  );
  tearDown(BookProtectionRepository.instance.debugReset);

  final paragraphProviders = <dynamic>[];
  var paragraphWrites = 0;
  setUp(() {
    paragraphProviders.clear();
    paragraphWrites = 0;
  });
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    final native = superNativeExtensionsContext as MockMessageChannelContext;
    native.registerMockMethodCallHandler('DataProviderManager', (call) async {
      if (call.method == 'registerDataProvider') {
        paragraphProviders.add(call.arguments['representations']);
        return paragraphProviders.length;
      }
      return null;
    });
    native.registerMockMethodCallHandler('ClipboardWriter', (call) async {
      if (call.method == 'writeToClipboard') paragraphWrites++;
      return null;
    });
  });

  tearDown(UiSnack.hide);

  for (final syncMode in ['shared', 'separate', 'none']) {
    for (final target in <TextTarget?>[null, TextTarget.commentary]) {
      if (syncMode != 'shared' && target == null) continue;
      testWidgets('Ctrl+C ממפרש: $target, $syncMode', (
        tester,
      ) async {
        final textBookBloc = StubTextBookBloc(_loadedState());
        final personalNotesBloc = StubPersonalNotesBloc(
          const PersonalNotesState(
            isLoading: false,
            bookId: 'ספר בדיקה',
            locatedNotes: [],
            missingNotes: [],
            errorMessage: null,
            filteredLocatedNotes: [],
            filteredMissingNotes: [],
          ),
        );
        final settingsBloc = StubSettingsBloc(SettingsState.initial());
        final sync = syncMode == 'none' ? null : SelectionSyncController();
        final mainSync = syncMode == 'separate'
            ? SelectionSyncController()
            : sync;
        final copied = <String>[];
        debugSelectedTextCopyHandler = (content) =>
            copied.add(content.plainText);
        addTearDown(() => debugSelectedTextCopyHandler = null);
        final tab = TextBookTab(
          book: TextBook(title: 'ספר בדיקה'),
          index: 0,
          blocOverride: textBookBloc,
        );
        final tabs = _AuditTabsBloc(TabsState(tabs: [tab], currentTabIndex: 0));
        final navigation = _AuditNavigationBloc(
          const NavigationState(currentScreen: Screen.reading),
        );
        final registry = DynamicShortcutRegistry.instance;
        if (target != null) {
          registry.put(
            DynamicShortcut(
              target: target,
              id: 'audit',
              key: 'ctrl+c',
              kind: DynamicShortcutKind.copySelectionWith,
              change: DynamicDisplayChange(nikud: DynamicMarkChange.hide),
              plainTextOnly: true,
            ),
          );
        }
        addTearDown(() => registry.remove('audit'));
        addTearDown(() async {
          await tabs.close();
          await navigation.close();
          await personalNotesBloc.close();
          await settingsBloc.close();
          tab.dispose();
          sync?.dispose();
          if (!identical(mainSync, sync)) mainSync?.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigatorKey,
            home: MultiBlocProvider(
              providers: [
                BlocProvider<TabsBloc>.value(value: tabs),
                BlocProvider<NavigationBloc>.value(value: navigation),
                BlocProvider<TextBookBloc>.value(value: textBookBloc),
                BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
                BlocProvider<SettingsBloc>.value(value: settingsBloc),
              ],
              child: Scaffold(
                body: KeyboardShortcuts(
                  onFindRefRequested: () {},
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Expanded(
                        child: SimpleTextViewer(
                          content: const ['גוף הספר'],
                          fontSize: 18,
                          openBookCallback: (_) {},
                          isMainText: true,
                          tab: tab,
                          selectionSyncController: mainSync,
                        ),
                      ),
                      Expanded(
                        child: SimpleTextViewer(
                          content: const ['מפרש אחר'],
                          fontSize: 18,
                          openBookCallback: (_) {},
                          isMainText: false,
                          bookTitle: 'מפרש אחר',
                          selectionSyncController: sync,
                          notesRepository: _FakeNotesRepository(),
                        ),
                      ),
                      Expanded(
                        child: SimpleTextViewer(
                          content: const [
                            'פֵּירוּשׁ',
                          ],
                          fontSize: 18,
                          openBookCallback: (_) {},
                          isMainText: false,
                          bookTitle: 'מפרש בדיקה',
                          selectionSyncController: sync,
                          notesRepository: _FakeNotesRepository(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        Future<void> selectText(String text) async {
          final rect = tester.getRect(find.textContaining(text).first);
          final gesture = await tester.startGesture(
            Offset(rect.right - 5, rect.center.dy),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump();
          await gesture.moveTo(Offset(rect.left + 5, rect.center.dy));
          await tester.pump();
          await gesture.up();
          await tester.pumpAndSettle();
        }

        Future<void> pressCtrlC() async {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
          if (target != null) {
            await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyC);
          }
          await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          UiSnack.hide();
          await tester.pump();
          // המתנה לאיפוס דגל _commentaryCopyHandled (100ms) בין לחיצות.
          await tester.pump(const Duration(milliseconds: 200));
        }

        Future<bool> pressCtrlCAndCopyReached() async {
          final before = copied.length;
          await pressCtrlC();
          if (target != null) {
            expect(
              copied.length,
              before + 1,
              reason: 'כל לחיצה מעתיקה פעם אחת בלבד',
            );
          } else {
            expect(copied.length, greaterThan(before));
          }
          if (target != null) expect(copied.last, 'פירוש');
          return copied.length > before;
        }

        await selectText('פֵּירוּשׁ');
        if (syncMode != 'shared') {
          await pressCtrlC();
          expect(
            copied,
            isEmpty,
            reason: 'אין להעתיק ממסך אחר או ללא בקר משותף',
          );
          expect(tab.dynamicCopyRequestNotifier.value, isNotNull);
          return;
        }
        expect(
          await pressCtrlCAndCopyReached(),
          isTrue,
          reason: 'העתקה ראשונה אחרי בחירה אמורה לעבוד',
        );

        // לחיצה ימנית על אמצע הבחירה — פותחת תפריט הקשר ומשמרת את הבחירה.
        final rect = tester.getRect(
          find.textContaining('פֵּירוּשׁ').first,
        );
        final rightClick = await tester.startGesture(
          rect.center,
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pump();
        await rightClick.up();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(
          await pressCtrlCAndCopyReached(),
          isTrue,
          reason: 'Ctrl+C אחרי לחיצה ימנית משמרת-בחירה חייב להמשיך לעבוד',
        );

        // גם בחירה טרייה של אותו טקסט (שאינה פולטת אירוע שינוי) ממשיכה לעבוד.
        await selectText('פֵּירוּשׁ');
        expect(
          await pressCtrlCAndCopyReached(),
          isTrue,
          reason: 'בחירה מחדש אחרי לחיצה ימנית חייבת לאפשר העתקה',
        );
        if (target == null) return;
        void register(
          TextTarget target, [
          DynamicShortcutKind kind = DynamicShortcutKind.copySelectionWith,
        ]) {
          registry.put(
            DynamicShortcut(
              target: target,
              id: 'audit',
              key: 'ctrl+c',
              kind: kind,
              change: const DynamicDisplayChange(nikud: DynamicMarkChange.hide),
              plainTextOnly: true,
            ),
          );
        }

        var before = copied.length;
        register(TextTarget.body);
        await pressCtrlC();
        expect(copied.length, before, reason: 'יעד גוף אינו מעתיק בחירה ממפרש');

        await selectText('גוף הספר');
        await pressCtrlC();
        expect(copied.length, before + 1);
        expect(copied.last, contains('גוף הספר'));
        before = copied.length;
        register(TextTarget.commentary);
        await pressCtrlC();
        expect(
          copied.length,
          before,
          reason: 'בחירה בגוף מבטלת את המפרש הפעיל',
        );

        await selectText('מפרש אחר');
        await pressCtrlC();
        expect(copied.length, before + 1);
        expect(copied.last, contains('מפרש אחר'));
        expect(tab.dynamicCopyRequestNotifier.value, isNull);

        register(TextTarget.commentary, DynamicShortcutKind.copyParagraphWith);
        await pressCtrlC();
        expect(
          tab.dynamicCopyRequestNotifier.value,
          isNull,
          reason: 'גם בקשת פסקה מגיעה למפרש הפעיל',
        );
        expect(paragraphWrites, 1);
        final expectedParagraph = await Formats.plainText('מפרש אחר');
        expect(
          paragraphProviders.single,
          expectedParagraph.representations.map(
            (representation) => representation.serialize(),
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}

class _FakeNotesRepository implements PersonalNotesRepository {
  @override
  Future<List<PersonalNote>> loadNotes(String bookId, {int? categoryId}) async {
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TextBookLoaded _loadedState() {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['גוף הספר'],
    fontSize: 18,
    showSplitView: false,
    showPageShapeView: true,
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
    pinLeftPane: false,
    searchText: '',
  );
}

class _AuditTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _AuditTabsBloc(super.initialState);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AuditNavigationBloc extends Cubit<NavigationState>
    implements NavigationBloc {
  _AuditNavigationBloc(super.initialState);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
