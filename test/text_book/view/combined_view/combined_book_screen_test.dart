import 'package:flutter/gestures.dart';
import 'package:otzaria/book_common/utils/commentators_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
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
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/selection/enhanced_gesture_detector.dart';
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';
import 'package:otzaria/widgets/misc/link_context_menu_entry.dart';
import 'package:otzaria/widgets/misc/link_preview_overlay.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:otzaria/widgets/text/selection_copy_shortcuts.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('תיקוני תוסף מקומיים בקורא המשולב', () {
    for (final mode in [
      (false, false),
      (true, false),
      (false, true),
      (true, true),
    ]) {
      final continuous = mode.$1;
      final splitView = mode.$2;
      testWidgets(
        'תצוגה ${continuous ? 'רציפה' : 'רגילה'} עם מפרשים ${splitView ? 'בצד' : 'מתחת'} מבודדת לשוניות ושומרת מקור אחרי reset/end',
        (tester) async {
          final registry = PluginCorrectionSessionService.instance;
          addTearDown(() => registry.removeOwner('widget-correction'));
          final source = [
            '<b>שורה א</b>',
            'שורה ב',
            for (var index = 2; index < 40; index++) 'שורת מקור מספר $index',
          ];
          final book = TextBook(id: 42, title: 'ספר בדיקה');
          final state = _loadedState().copyWith(
            book: book,
            content: source,
            supportsContinuousReadingMode: true,
            continuousReadingMode: continuous,
            showSplitView: splitView,
            readingSegments: buildReadingSegments(
              source,
              continuous: continuous,
            ),
          );
          final blocs = List.generate(2, (_) => _RecordingTextBookBloc(state));
          final tabs = List.generate(
            2,
            (index) => TextBookTab(
              book: book,
              index: 0,
              blocOverride: blocs[index],
            ),
          );
          final settings = _TestSettingsBloc(SettingsState.initial());
          final notes = _TestPersonalNotesBloc(
            const PersonalNotesState.initial(),
          );
          addTearDown(settings.close);
          addTearDown(notes.close);
          for (final tab in tabs) {
            addTearDown(tab.dispose);
          }
          final keys = [GlobalKey(), GlobalKey()];
          Future<void> mount({double size = 18}) async {
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: Row(
                    children: List.generate(
                      2,
                      (index) => Expanded(
                        child: MultiBlocProvider(
                          providers: [
                            BlocProvider<TextBookBloc>.value(
                              value: blocs[index],
                            ),
                            BlocProvider<SettingsBloc>.value(value: settings),
                            BlocProvider<PersonalNotesBloc>.value(value: notes),
                          ],
                          child: CombinedView(
                            key: keys[index],
                            data: source,
                            tab: tabs[index],
                            openBookCallback: (_) {},
                            openLeftPaneTab: (_, {searchText}) {},
                            textSize: size,
                            showCommentaryAsExpansionTiles: !splitView,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
          }

          List<String> displayed(int index) {
            final fields = find.descendant(
              of: find.byKey(keys[index]),
              matching: find.byType(RtlTextField),
            );
            if (fields.evaluate().isNotEmpty) {
              return tester
                  .widgetList<RtlTextField>(fields)
                  .map((field) => field.controller!.text)
                  .toList();
            }
            final descendants = find.descendant(
              of: find.byKey(keys[index]),
              matching: find.byType(
                continuous ? ContinuousReadingParagraph : SmartTextWidget,
              ),
            );
            return continuous
                ? tester
                      .widgetList<ContinuousReadingParagraph>(descendants)
                      .expand(
                        (paragraph) => paragraph.lines.map((line) => line.text),
                      )
                      .toList()
                : tester
                      .widgetList<SmartTextWidget>(descendants)
                      .map((widget) => widget.text)
                      .toList();
          }

          await mount();
          expect(displayed(0).join(' '), contains('שורה א'));
          expect(displayed(1).join(' '), contains('שורה א'));
          final changeEvents = <Map<String, dynamic>>[];
          final session = registry.begin(
            owner: 'widget-correction',
            tabId: PluginCorrectionSessionService.tabIdFor(tabs.first),
            bookId: book.title,
            bookUid: 'id:42',
            libraryVersion: '1',
            loadSource: (index) async => source[index],
            onEvent: (topic, payload) {
              if (topic == 'reader.correctionSessionChanged') {
                changeEvents.add(payload);
              }
            },
          );
          await tester.pumpAndSettle();
          final editorFinder = find.descendant(
            of: find.byKey(keys.first),
            matching: find.byType(RtlTextField),
          );
          expect(editorFinder, findsWidgets);
          expect(
            find.descendant(
              of: find.byKey(keys[1]),
              matching: find.byType(RtlTextField),
            ),
            findsNothing,
          );
          Future<Map<String, dynamic>> apply(int revision) => registry.restore(
            owner: 'widget-correction',
            id: session['sessionId'],
            expectedRevision: revision,
            bookUid: 'id:42',
            libraryVersion: '1',
            changes: [
              {
                'sectionIndex': 0,
                'originalSourceText': source.first,
                'originalText': 'שורה א',
                'proposedText': 'נוסח מתוקן ארוך 😀',
              },
            ],
          );
          await tester.runAsync(() => apply(0));
          await tester.pumpAndSettle();
          expect(displayed(0).join(' '), contains('נוסח מתוקן ארוך 😀'));
          expect(displayed(1).join(' '), contains('שורה א'));
          final firstEditor = editorFinder.first;
          final editor = tester.widget<RtlTextField>(firstEditor);
          expect(editor.controller!.text, 'נוסח מתוקן ארוך 😀');
          await tester.tap(firstEditor, kind: PointerDeviceKind.mouse);
          await tester.pump(const Duration(milliseconds: 500));
          expect(editor.focusNode!.hasFocus, isTrue);
          expect(editor.controller!.selection.isCollapsed, isTrue);
          final editable = find.descendant(
            of: firstEditor,
            matching: find.byType(EditableText),
          );
          expect(
            tester.state<EditableTextState>(editable).renderEditable.hasFocus,
            isTrue,
          );
          await tester.enterText(firstEditor, 'עריכה ישירה אחרונה 😀');
          final latest = registry.get(
            'widget-correction',
            session['sessionId'],
          );
          expect(latest['revision'], 2);
          expect(
            (latest['changes'] as List).single['proposedText'],
            'עריכה ישירה אחרונה 😀',
          );
          expect(changeEvents.last['revision'], 2);
          expect(changeEvents.last['sectionIndex'], 0);
          expect(editor.focusNode!.hasFocus, isTrue);
          editor.controller!.selection = const TextSelection.collapsed(
            offset: 3,
          );
          await tester.pump();
          expect(
            tester.widget<RtlTextField>(firstEditor).focusNode,
            same(editor.focusNode),
          );
          expect(editor.focusNode!.hasFocus, isTrue);
          expect(editor.controller!.selection.extentOffset, 3);
          await mount(size: 22);
          expect(displayed(0).join(' '), contains('עריכה ישירה אחרונה 😀'));
          expect(
            tester.widget<RtlTextField>(firstEditor).focusNode,
            same(editor.focusNode),
          );
          expect(editor.focusNode!.hasFocus, isTrue);
          expect(editor.controller!.selection.extentOffset, 3);
          tester.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: 'עריכה ישירה אחרונה 😀ק',
              selection: TextSelection.collapsed(offset: 22),
              composing: TextRange(start: 21, end: 22),
            ),
          );
          await tester.pump();
          expect(
            editor.controller!.value.composing,
            const TextRange(start: 21, end: 22),
          );
          expect(
            (registry.get('widget-correction', session['sessionId'])['changes']
                    as List)
                .single['proposedText'],
            'עריכה ישירה אחרונה 😀ק',
          );
          await mount(size: 24);
          expect(
            editor.controller!.value.composing,
            const TextRange(start: 21, end: 22),
          );
          expect(editor.focusNode!.hasFocus, isTrue);
          tester.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: 'עריכה ישירה אחרונה 😀ק',
              selection: TextSelection.collapsed(offset: 22),
            ),
          );
          await tester.pump();
          expect(
            registry.get('widget-correction', session['sessionId'])['revision'],
            3,
          );
          for (final rejected in ['שתי\nפסקאות', '<b>תגית</b>']) {
            await tester.enterText(firstEditor, rejected);
            await tester.pump();
            expect(editor.controller!.text, 'עריכה ישירה אחרונה 😀ק');
            expect(
              registry.get(
                'widget-correction',
                session['sessionId'],
              )['revision'],
              3,
            );
          }
          editor.controller!.text = 'הדבקה ידנית\nשאינה פסקה אחת';
          editor.onChanged!(editor.controller!.text);
          await tester.pump();
          expect(editor.controller!.text, 'עריכה ישירה אחרונה 😀ק');
          expect(
            registry.get('widget-correction', session['sessionId'])['revision'],
            3,
          );
          editor.focusNode!.unfocus();
          if (!continuous) {
            tabs.first.scrollController.jumpTo(index: 30);
            await tester.pumpAndSettle();
            expect(
              displayed(0).join(' '),
              isNot(contains('עריכה ישירה אחרונה 😀ק')),
            );
            tabs.first.scrollController.jumpTo(index: 0);
            await tester.pumpAndSettle();
            expect(displayed(0).join(' '), contains('עריכה ישירה אחרונה 😀ק'));
          }
          for (final bloc in blocs) {
            expect((bloc.state as TextBookLoaded).content, source);
          }
          registry.reset('widget-correction', session['sessionId'], 0, 3);
          await tester.pumpAndSettle();
          expect(displayed(0).join(' '), contains('שורה א'));
          expect(
            registry.get('widget-correction', session['sessionId'])['changes'],
            isEmpty,
          );
          await tester.runAsync(() => apply(4));
          await tester.pumpAndSettle();
          final ended = registry.end(
            'widget-correction',
            session['sessionId'],
            5,
          );
          expect(
            (ended['changes'] as List).single['proposedText'],
            'נוסח מתוקן ארוך 😀',
          );
          await tester.pumpAndSettle();
          expect(displayed(0).join(' '), contains('שורה א'));
          expect(displayed(1).join(' '), contains('שורה א'));
          expect(find.byType(RtlTextField), findsNothing);
          for (final bloc in blocs) {
            expect((bloc.state as TextBookLoaded).content, source);
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }

    testWidgets(
      'סיום סשן מחזיר מיקוד לקורא רק מהשדה שלו ולא גונב מיקוד חיצוני',
      (
        tester,
      ) async {
        final registry = PluginCorrectionSessionService.instance;
        addTearDown(() => registry.removeOwner('focus-correction'));
        const source = ['שורה א', 'שורה ב'];
        final book = TextBook(id: 7, title: 'ספר בדיקה');
        final bloc = _RecordingTextBookBloc(
          _loadedState().copyWith(
            book: book,
            content: source,
            visibleIndices: const [0, 1],
          ),
        );
        final tab = TextBookTab(book: book, index: 0, blocOverride: bloc);
        final settings = _TestSettingsBloc(SettingsState.initial());
        final notes = _TestPersonalNotesBloc(
          const PersonalNotesState.initial(),
        );
        final external = FocusNode();
        addTearDown(settings.close);
        addTearDown(notes.close);
        addTearDown(tab.dispose);
        addTearDown(external.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  Focus(focusNode: external, child: const SizedBox(height: 1)),
                  Expanded(
                    child: MultiBlocProvider(
                      providers: [
                        BlocProvider<TextBookBloc>.value(value: bloc),
                        BlocProvider<SettingsBloc>.value(value: settings),
                        BlocProvider<PersonalNotesBloc>.value(value: notes),
                      ],
                      child: CombinedView(
                        data: source,
                        tab: tab,
                        openBookCallback: (_) {},
                        openLeftPaneTab: (_, {searchText}) {},
                        textSize: 18,
                        showCommentaryAsExpansionTiles: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<String> begin() async {
          final session = registry.begin(
            owner: 'focus-correction',
            tabId: PluginCorrectionSessionService.tabIdFor(tab),
            bookId: book.title,
            bookUid: 'id:7',
            libraryVersion: '1',
            loadSource: (index) async => source[index],
          );
          await tester.pumpAndSettle();
          return session['sessionId'] as String;
        }

        var id = await begin();
        external.requestFocus();
        await tester.pump();
        registry.end('focus-correction', id, 0);
        await tester.pumpAndSettle();
        expect(external.hasFocus, isTrue);

        id = await begin();
        await tester.tap(find.byType(RtlTextField).first);
        await tester.pump();
        registry.end('focus-correction', id, 0);
        await tester.pumpAndSettle();
        expect(external.hasFocus, isFalse);
        expect(find.byType(RtlTextField), findsNothing);
        expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<CombinedView>(),
          isNotNull,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      },
    );
  });

  group('shouldOpenPreviewLinkInBook', () {
    Link link(String type) => Link(
      heRef: 'יעד',
      index1: 1,
      path2: 'יעד.txt',
      index2: 2,
      connectionType: type,
    );

    test('משאיר קישור Linker במסלול פתיחת הספר', () {
      expect(shouldOpenPreviewLinkInBook(link('linker')), isTrue);
    });

    test('מפנה מפרש וקישור רגיל לחלוניות הצד', () {
      expect(shouldOpenPreviewLinkInBook(link('COMMENTARY')), isFalse);
      expect(shouldOpenPreviewLinkInBook(link('REFERENCE')), isFalse);
    });
  });

  group('activatePreviewCommentator', () {
    final link = Link(
      heRef: 'טורי זהב',
      index1: 1,
      path2: r'מפרשים\טורי זהב.txt',
      index2: 2,
      connectionType: 'COMMENTARY',
    );

    test('מוסיף מפרש שאינו פעיל לסוף הבחירה', () {
      expect(
        activatePreviewCommentator(
          activeCommentators: const ['שפתי כהן'],
          link: link,
        ),
        ['שפתי כהן', 'טורי זהב'],
      );
    });

    test('לחיצה על ציון אינה משנה את סדר המפרשים (issue #2015)', () {
      const active = ['שפתי כהן', 'טורי זהב', 'באר היטב'];
      expect(
        activatePreviewCommentator(activeCommentators: active, link: link),
        same(active),
      );
    });
  });

  group('shouldHandleCommentaryScrollTarget', () {
    test('רק כרטיס השורה שממנה נלחץ העוגן מגיב ליעד', () {
      expect(
        shouldHandleCommentaryScrollTarget(
          cardIndex: 4,
          targetLineIndex: 4,
        ),
        isTrue,
      );
      expect(
        shouldHandleCommentaryScrollTarget(
          cardIndex: 8,
          targetLineIndex: 4,
        ),
        isFalse,
      );
    });
  });

  group('buildCombinedViewContextMenuLinksForParagraph', () {
    test('מחזירה רק קישורים רגילים של הפסקה שנלחצה', () {
      final linksByLine = <int, List<Link>>{
        3: [
          Link(
            heRef: 'בראשית ג ב',
            index1: 3,
            path2: 'zfoo/zzz.txt',
            index2: 10,
            connectionType: 'REFERENCE',
          ),
          Link(
            heRef: 'בראשית ג',
            index1: 3,
            path2: 'foo/bar.txt',
            index2: 7,
            connectionType: 'REFERENCE',
          ),
          Link(
            heRef: 'רש"י על בראשית ג',
            index1: 3,
            path2: 'commentary/rashi.txt',
            index2: 7,
            connectionType: 'COMMENTARY',
          ),
          Link(
            heRef: 'בראשית ג inline',
            index1: 3,
            path2: 'foo/inline.txt',
            index2: 8,
            connectionType: 'REFERENCE',
            start: 1,
            end: 4,
          ),
        ],
        4: [
          Link(
            heRef: 'בראשית ד',
            index1: 4,
            path2: 'foo/other.txt',
            index2: 9,
            connectionType: 'REFERENCE',
          ),
        ],
      };

      final result = buildCombinedViewContextMenuLinksForParagraph(
        linksByLine: linksByLine,
        paragraphIndex: 2,
      );

      expect(result, hasLength(2));
      expect(result.map((link) => link.heRef), ['בראשית ג', 'בראשית ג ב']);
    });

    test('מאחדת את שאילתת הפסקה עם חלון הטעינה בלי כפילויות', () {
      Link reference(String path2) => Link(
        heRef: path2,
        index1: 3,
        path2: path2,
        index2: 7,
        connectionType: 'REFERENCE',
      );

      final result = buildCombinedViewContextMenuLinksForParagraph(
        linksByLine: {
          3: [reference('a.txt')],
        },
        paragraphIndex: 2,
        queriedLinks: [reference('a.txt'), reference('b.txt')],
      );

      expect(result.map((link) => link.path2), ['a.txt', 'b.txt']);
    });

    test('מחזירה רשימה ריקה כשאין קישורים לפסקה', () {
      final result = buildCombinedViewContextMenuLinksForParagraph(
        linksByLine: const <int, List<Link>>{},
        paragraphIndex: 10,
      );

      expect(result, isEmpty);
    });
  });

  group('shouldShowPersonalNotePreview', () {
    test('מציג תצוגה מקדימה כשטאב ההערות אינו פעיל', () {
      expect(
        shouldShowPersonalNotePreview(isPersonalNotesTabActive: false),
        isTrue,
      );
    });

    test('לא מציג תצוגה מקדימה כשטאב ההערות פעיל', () {
      expect(
        shouldShowPersonalNotePreview(isPersonalNotesTabActive: true),
        isFalse,
      );
    });
  });

  group('shouldShowOpenLinksPaneEntry', () {
    test('מחזירה true כשיש קישורים וטאב הקישורים אינו פעיל', () {
      expect(
        shouldShowOpenLinksPaneEntry(
          hasLinks: true,
          isLinksTabActive: false,
        ),
        isTrue,
      );
    });

    test('מחזירה false כשאין קישורים', () {
      expect(
        shouldShowOpenLinksPaneEntry(
          hasLinks: false,
          isLinksTabActive: false,
        ),
        isFalse,
      );
    });

    test('מחזירה false כשטאב הקישורים כבר פעיל', () {
      expect(
        shouldShowOpenLinksPaneEntry(
          hasLinks: true,
          isLinksTabActive: true,
        ),
        isFalse,
      );
    });
  });

  group('shouldClearSelectionOnExternalChange', () {
    test('מחזירה false כש-activeOwner הוא null (ניקוי בעלות)', () {
      // אחרי clear ה-controller מודיע עם activeOwner=null — אין אזור אחר
      // שתפס בעלות, ולכן אין מה לנקות.
      final selfOwner = Object();
      expect(
        shouldClearSelectionOnExternalChange(
          activeOwner: null,
          selfOwner: selfOwner,
          hasOwnSelection: true,
        ),
        isFalse,
      );
    });

    test('מחזירה false כש-activeOwner זהה ל-selfOwner', () {
      // אנחנו הבעלים — ניקוי כאן היה מוחק את הבחירה שהמשתמש בדיוק סימן.
      final selfOwner = Object();
      expect(
        shouldClearSelectionOnExternalChange(
          activeOwner: selfOwner,
          selfOwner: selfOwner,
          hasOwnSelection: true,
        ),
        isFalse,
      );
    });

    test(
      "מחזירה false כשאזור חיצוני מקבל בעלות אבל אין לנו בחירה משלנו לנקות",
      () {
        final selfOwner = Object();
        final commentaryOwner = Object();
        expect(
          shouldClearSelectionOnExternalChange(
            activeOwner: commentaryOwner,
            selfOwner: selfOwner,
            hasOwnSelection: false,
          ),
          isFalse,
        );
      },
    );

    test('מחזירה true כשאזור חיצוני מקבל בעלות ויש לנו בחירה משלנו לנקות', () {
      final selfOwner = Object();
      final externalOwner = Object();
      expect(
        shouldClearSelectionOnExternalChange(
          activeOwner: externalOwner,
          selfOwner: selfOwner,
          hasOwnSelection: true,
        ),
        isTrue,
      );
    });

    test(
      'הבעלות עוברת למפרש בזמן שיש בחירה בטקסט הראשי — מנקים, אך רק דרך '
      'clearSelection ולא בהחלפת מפתח (issue #674)',
      () {
        // התרחיש של #674: המשתמש סימן בטקסט הראשי, ואז סימן במפרש שמתחת.
        // התשובה כאן היא true (יש בחירה ישנה לנקות) — ולכן קריטי שהניקוי
        // בפועל ייעשה ב-clearSelection: החלפת מפתח הייתה הורסת את כרטיס
        // המפרשים המקונן יחד עם הבחירה החדשה שבתוכו.
        final mainTextOwner = Object();
        final commentaryOwner = Object();
        expect(
          shouldClearSelectionOnExternalChange(
            activeOwner: commentaryOwner,
            selfOwner: mainTextOwner,
            hasOwnSelection: true,
          ),
          isTrue,
        );
      },
    );
  });

  group('commentarySelectionForCopy', () {
    test('מחזירה null ללא controller', () {
      expect(
        commentarySelectionForCopy(
          controller: null,
          mainTextOwner: Object(),
        ),
        isNull,
      );
    });

    test('מחזירה null לבחירה ריקה', () {
      final controller = SelectionSyncController();
      addTearDown(controller.dispose);
      controller.activate(Object(), selectionText: '  ');

      expect(
        commentarySelectionForCopy(
          controller: controller,
          mainTextOwner: Object(),
        ),
        isNull,
      );
    });

    test('אינה נופלת לבחירה ששייכת לטקסט הראשי', () {
      final controller = SelectionSyncController();
      addTearDown(controller.dispose);
      final mainTextOwner = Object();
      controller.activate(mainTextOwner, selectionText: 'בחירת טקסט ראשי');

      expect(
        commentarySelectionForCopy(
          controller: controller,
          mainTextOwner: mainTextOwner,
        ),
        isNull,
      );
    });

    test('מחזירה בחירת מפרש ואת הקישור שלה', () {
      final controller = SelectionSyncController();
      addTearDown(controller.dispose);
      final link = Link(
        heRef: 'בראשית א א',
        index1: 1,
        path2: 'רש"י.txt',
        index2: 1,
        connectionType: 'COMMENTARY',
      );
      controller.activate(
        Object(),
        selectionText: 'בחירת מפרש',
        selectionLink: link,
      );

      final selection = commentarySelectionForCopy(
        controller: controller,
        mainTextOwner: Object(),
      );

      expect(selection?.text, 'בחירת מפרש');
      expect(selection?.link, same(link));
    });
  });

  group('אזור הבחירה של התצוגה המשולבת (issue #674)', () {
    Future<SelectionSyncController> pumpCombinedView(
      WidgetTester tester,
    ) async {
      final controller = SelectionSyncController();
      addTearDown(controller.dispose);
      final textBookBloc = _ClosedTextBookBloc(_loadedState());
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      final personalNotesBloc = _TestPersonalNotesBloc(
        PersonalNotesState(
          isLoading: false,
          bookId: 'ספר בדיקה',
          locatedNotes: const [],
          missingNotes: const [],
          errorMessage: null,
          filteredLocatedNotes: const [],
          filteredMissingNotes: const [],
        ),
      );
      final tab = TextBookTab(book: TextBook(title: 'ספר בדיקה'), index: 0);
      addTearDown(tab.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<TextBookBloc>.value(value: textBookBloc),
              BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
            ],
            child: Scaffold(
              body: CombinedView(
                data: const ['שורה א'],
                openBookCallback: (_) {},
                openLeftPaneTab: (_, {searchText}) {},
                textSize: 18,
                showCommentaryAsExpansionTiles: true,
                selectionSyncController: controller,
                tab: tab,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 20));
      });
      return controller;
    }

    testWidgets(
      'ה-SelectionArea נושא מפתח יציב ולא מפתח שנגזר ממצב הבחירה',
      (tester) async {
        // נסיגה לדפוס הישן — ValueKey('combined_selection_$revision') — גרמה
        // לכך שכל מעבר בעלות בחירה בנה מחדש את תת-העץ, כולל כרטיס המפרשים
        // המקונן, ואיתו נמחקה הבחירה שהמשתמש זה עתה סימן במפרש.
        await pumpCombinedView(tester);

        expect(_combinedSelectionAreaFinder(), findsOneWidget);
      },
    );

    testWidgets('יירוט ההעתקה ממוקם מעל ה-SelectionArea', (tester) async {
      // מתחת ל-SelectionArea מנגנון ה-override של CopySelectionTextIntent
      // אינו רואה אותו, ואז רצה העתקת ברירת המחדל של Flutter — שכותבת ללוח
      // גם בחירה מכווצת (plainText ריק), וזה הפריט הריק שדווח.
      await pumpCombinedView(tester);

      expect(
        find.ancestor(
          of: _combinedSelectionAreaFinder(),
          matching: find.byType(SelectionCopyShortcuts),
        ),
        findsOneWidget,
      );
    });

    testWidgets('מעבר בעלות לכרטיס המפרשים אינו הורס את אזור הטקסט הראשי', (
      tester,
    ) async {
      final controller = await pumpCombinedView(tester);

      SelectableRegionState region() => tester.state<SelectableRegionState>(
        find.descendant(
          of: _combinedSelectionAreaFinder(),
          matching: find.byType(SelectableRegion),
        ),
      );

      final regionBefore = region();
      region().selectAll();
      await tester.pump();
      // בלי בחירה משלנו מסלול הניקוי יוצא מוקדם, והטסט היה עובר ריק מתוכן.
      expect(
        controller.activeOwner,
        isNotNull,
        reason: 'הבחירה בטקסט הראשי חייבת להיווצר כדי שהתרחיש ייבדק',
      );

      // כרטיס המפרשים תופס בעלות בזמן שלטקסט הראשי יש בחירה — בדיוק התרחיש
      // שבו הבאג התרחש.
      controller.activate(Object());
      await tester.pump();

      expect(region(), same(regionBefore));
    });
  });

  group('shouldRestoreScrollOnContinuousModeChange', () {
    test('החלפת מצב (רגיל→רציף או להיפך) → משחזרים גלילה', () {
      // הבאג שתוקן: מיפוי שורה↔פריט מתחלף אבל הרשימה נשארת על אינדקס
      // הפריט הישן — בלי שחזור המשתמש קופץ למקום רחוק בספר.
      expect(
        shouldRestoreScrollOnContinuousModeChange(
          previousMode: false,
          currentMode: true,
        ),
        isTrue,
      );
      expect(
        shouldRestoreScrollOnContinuousModeChange(
          previousMode: true,
          currentMode: false,
        ),
        isTrue,
      );
    });

    test('אותו מצב → אין שחזור (emit-ים שוטפים לא מזיזים את הגלילה)', () {
      expect(
        shouldRestoreScrollOnContinuousModeChange(
          previousMode: true,
          currentMode: true,
        ),
        isFalse,
      );
      expect(
        shouldRestoreScrollOnContinuousModeChange(
          previousMode: false,
          currentMode: false,
        ),
        isFalse,
      );
    });

    test('ה-state הראשון שנצפה (previousMode=null) → אין שחזור', () {
      expect(
        shouldRestoreScrollOnContinuousModeChange(
          previousMode: null,
          currentMode: true,
        ),
        isFalse,
      );
    });
  });

  group('תרחישים חוצי-טאב בחלונית הצד', () {
    test('"פתח מפרשים" מוצגת כשהחלונית פתוחה על טאב הקישורים', () {
      expect(
        shouldShowOpenCommentatorsPaneEntry(
          hasSelectedCommentators: true,
          showCommentaryAsExpansionTiles: false,
          isCommentatorsTabActive: false,
        ),
        isTrue,
      );
    });

    test('"פתח קישורים" מוצגת כשהחלונית פתוחה על טאב המפרשים', () {
      expect(
        shouldShowOpenLinksPaneEntry(
          hasLinks: true,
          isLinksTabActive: false,
        ),
        isTrue,
      );
    });

    test('"פתח מפרשים" מסתתרת כשאין מפרשים נבחרים אפילו אם זמינים בספר', () {
      expect(
        shouldShowOpenCommentatorsPaneEntry(
          hasSelectedCommentators: false,
          showCommentaryAsExpansionTiles: false,
          isCommentatorsTabActive: false,
        ),
        isFalse,
      );
    });
  });

  testWidgets('disposing the view cancels its bloc subscriptions', (
    tester,
  ) async {
    final textBookBloc = _ListenerCountingTextBookBloc(_loadedState());
    addTearDown(textBookBloc.close);
    final tab = TextBookTab(book: TextBook(title: 'ספר בדיקה'), index: 0);
    addTearDown(tab.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<PersonalNotesBloc>.value(
              value: _TestPersonalNotesBloc(
                PersonalNotesState(
                  isLoading: false,
                  bookId: 'ספר בדיקה',
                  locatedNotes: const [],
                  missingNotes: const [],
                  errorMessage: null,
                  filteredLocatedNotes: const [],
                  filteredMissingNotes: const [],
                ),
              ),
            ),
            BlocProvider<SettingsBloc>.value(
              value: _TestSettingsBloc(SettingsState.initial()),
            ),
          ],
          child: Scaffold(
            body: CombinedView(
              data: const ['שורה א'],
              openBookCallback: (_) {},
              openLeftPaneTab: (_, {searchText}) {},
              textSize: 18,
              showCommentaryAsExpansionTiles: true,
              tab: tab,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(textBookBloc.activeListeners, greaterThan(0));

    // The bloc belongs to the tab and outlives the view.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
    expect(textBookBloc.activeListeners, 0);
  });

  testWidgets('לחיצה על פסקה לא שולחת event ל-bloc סגור', (tester) async {
    final textBookBloc = _ClosedTextBookBloc(_loadedState());
    final personalNotesBloc = _TestPersonalNotesBloc(
      PersonalNotesState(
        isLoading: false,
        bookId: 'ספר בדיקה',
        locatedNotes: const [],
        missingNotes: const [],
        errorMessage: null,
        filteredLocatedNotes: const [],
        filteredMissingNotes: const [],
      ),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final tab = TextBookTab(
      book: TextBook(title: 'ספר בדיקה'),
      index: 0,
    );

    addTearDown(tab.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: CombinedView(
              data: const ['שורה א'],
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
    await tester.tap(find.byType(EnhancedGestureDetector).first);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));

    expect(textBookBloc.addWasCalled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('כניסה חוזרת לעוגן הפעיל אינה בונה מחדש את הפופאפ', (
    tester,
  ) async {
    final link = Link(
      heRef: 'מפרש א, א',
      index1: 1,
      path2: 'מפרש א',
      index2: 1,
      connectionType: 'commentary',
      anchorStart: 0,
      anchorLabel: 'א',
    );
    final textBookBloc = _RecordingTextBookBloc(
      _loadedState().copyWith(
        links: [link],
        linksByLine: {
          1: [link],
        },
      ),
    );
    final personalNotesBloc = _TestPersonalNotesBloc(
      const PersonalNotesState.initial(),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final tab = TextBookTab(book: TextBook(title: 'ספר בדיקה'), index: 0);
    addTearDown(textBookBloc.close);
    addTearDown(personalNotesBloc.close);
    addTearDown(settingsBloc.close);
    addTearDown(tab.dispose);
    addTearDown(LinkPreviewOverlay.dismiss);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: textBookBloc),
          BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CombinedView(
              data: const ['שורה א'],
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
    await tester.pumpAndSettle();

    const url = 'otzaria://anchor?ref=0_0';
    var smartText = tester
        .widgetList<SmartTextWidget>(find.byType(SmartTextWidget))
        .firstWhere((widget) => widget.text.contains(url));
    smartText.onAnchorHover!(url, const Offset(100, 100));
    await tester.pump(const Duration(milliseconds: 300));
    final firstPreview = tester.element(find.byType(LinkHoverPreviewContent));

    await tester.pump();
    smartText = tester
        .widgetList<SmartTextWidget>(find.byType(SmartTextWidget))
        .firstWhere((widget) => widget.text.contains(url));
    smartText.onAnchorHoverExit!(url);
    smartText.onAnchorHover!(url, const Offset(100, 100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester.element(find.byType(LinkHoverPreviewContent)),
      same(firstPreview),
    );
  });

  testWidgets(
    'תת-תפריט "מפרשים" בתצוגה המשולבת נבנה מהבונה המשותף ומעדכן את הבחירה',
    (tester) async {
      // רגרסיה לחילוץ הבונה המשותף עם צורת הדף: הפריטים והתנהגותם בתצוגה
      // המשולבת חייבים להישאר כשהיו.
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final textBookBloc = _RecordingTextBookBloc(
        _loadedState().copyWith(
          availableCommentators: const ['רש"י', 'רמב"ן'],
          activeCommentators: const ['רש"י'],
          commentatorGroups: const [
            CommentatorGroup(
              title: 'ראשונים',
              commentators: ['רש"י', 'רמב"ן'],
            ),
          ],
          linksByLine: {
            1: [
              for (final title in const ['רש"י', 'רמב"ן'])
                Link(
                  heRef: '',
                  index1: 1,
                  path2: 'מפרשים/$title.txt',
                  index2: 1,
                  connectionType: 'commentary',
                ),
            ],
          },
        ),
      );
      addTearDown(textBookBloc.close);
      final personalNotesBloc = _TestPersonalNotesBloc(
        const PersonalNotesState.initial(),
      );
      addTearDown(personalNotesBloc.close);
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      addTearDown(settingsBloc.close);
      final tab = TextBookTab(book: TextBook(title: 'ספר בדיקה'), index: 0);
      addTearDown(tab.dispose);
      var openedPane = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<TextBookBloc>.value(value: textBookBloc),
              BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
            ],
            child: Scaffold(
              body: CombinedView(
                data: const ['שורה א'],
                openBookCallback: (_) {},
                openLeftPaneTab: (_, {searchText}) {},
                textSize: 18,
                showCommentaryAsExpansionTiles: false,
                tab: tab,
                onOpenCommentatorsPane: () => openedPane++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      final center = tester.getCenter(find.byType(AppContextMenuRegion).first);
      await gesture.moveTo(center);
      await gesture.down(center);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('מפרשים על פסקה זו'));
      await tester.pumpAndSettle();

      expect(find.text('פתח את חלונית המפרשים'), findsOneWidget);
      expect(find.text('הצג את כל המפרשים על פסקה זו'), findsOneWidget);
      expect(find.text('הצג את כל ראשונים'), findsOneWidget);

      await tester.tap(find.text('רמב"ן'));
      await tester.pumpAndSettle();

      expect(
        textBookBloc.received
            .whereType<UpdateCommentators>()
            .single
            .commentators,
        ['רש"י', 'רמב"ן'],
      );
      expect(openedPane, 1);
    },
  );

  group('applyDisplayTextPreferences', () {
    // קמץ (ניקוד) — נמצא ב-vowelsAndCantillation אך לא ב-cantillationOnly
    const niqqud = 'ָ';
    // אתנחתא (טעם) — נמצא בשתי הקבוצות
    const taam = '֑';
    const showAll = TextDisplayProfile(
      teamim: TeamimVisibility.show,
      holyName: HolyNameDisplay.asIs,
    );

    test('מסיר פיסוק כשהפיסוק מוסתר (באג "העתק את כל הפסקה")', () {
      final result = applyDisplayTextPreferences(
        text: 'שלום, עולם!',
        profile: showAll.copyWith(punctuation: MarkVisibility.hide),
      );
      expect(result.contains(','), isFalse);
      expect(result.contains('!'), isFalse);
      expect(result.contains('שלום'), isTrue);
      expect(result.contains('עולם'), isTrue);
    });

    test('שומר פיסוק כשהפיסוק מוצג', () {
      final result = applyDisplayTextPreferences(
        text: 'שלום, עולם!',
        profile: showAll,
      );
      expect(result, 'שלום, עולם!');
    });

    test('מסיר ניקוד כשהניקוד מוסתר', () {
      final result = applyDisplayTextPreferences(
        text: 'א$niqqudבג',
        profile: showAll.copyWith(nikud: MarkVisibility.hide),
      );
      expect(result, 'אבג');
    });

    test('שומר ניקוד כשהניקוד מוצג', () {
      final result = applyDisplayTextPreferences(
        text: 'א$niqqudבג',
        profile: showAll,
      );
      expect(result, 'א$niqqudבג');
    });

    test('מסיר טעמים בלבד כשהטעמים מוסתרים (הניקוד נשמר)', () {
      final result = applyDisplayTextPreferences(
        text: 'א$niqqud$taamבג',
        profile: showAll.copyWith(teamim: TeamimVisibility.hide),
      );
      expect(result.contains(taam), isFalse);
      expect(result.contains(niqqud), isTrue);
    });

    test('שומר טעמים כשהטעמים מוצגים', () {
      final result = applyDisplayTextPreferences(
        text: 'א$taamבג',
        profile: showAll,
      );
      expect(result.contains(taam), isTrue);
    });

    test('טעמים במצב followNikud מוסרים יחד עם הניקוד', () {
      final result = applyDisplayTextPreferences(
        text: 'א$niqqud$taamבג',
        profile: showAll.copyWith(
          nikud: MarkVisibility.hide,
          teamim: TeamimVisibility.followNikud,
        ),
      );
      expect(result, 'אבג');
    });

    test('מסיר גם ניקוד וגם פיסוק יחד (באג "העתק טקסט מוצג")', () {
      final result = applyDisplayTextPreferences(
        text: 'א$niqqudבג, דה!',
        profile: showAll.copyWith(
          nikud: MarkVisibility.hide,
          punctuation: MarkVisibility.hide,
        ),
      );
      expect(result.contains(niqqud), isFalse);
      expect(result.contains(','), isFalse);
      expect(result.contains('!'), isFalse);
    });

    test('מחליף את שם הוי"ה לפי הפרופיל', () {
      final result = applyDisplayTextPreferences(
        text: 'ויאמר יהוה',
        profile: showAll.copyWith(holyName: HolyNameDisplay.hehApostrophe),
      );
      expect(result, "ויאמר ה'");
    });

    test('ישות HTML (&thinsp;) שורדת הסרת פיסוק ואינה הופכת לטקסט גלוי', () {
      // ה-";" של הישות אינו פיסוק אלא תחביר; מחיקתו השאירה "&thinsp" מוצג
      // ליד כל פסק בתנ"ך.
      const text = 'אֱלֹהִ֤ים&thinsp;<small>׀</small>&thinsp;לָאוֹר֙';

      final result = applyDisplayTextPreferences(
        text: text,
        profile: showAll.copyWith(
          nikud: MarkVisibility.hide,
          punctuation: MarkVisibility.hide,
        ),
      );

      expect(result.contains('&thinsp;'), isTrue);
      expect(result.contains('&thinsp<'), isFalse);
    });

    test('לא משנה טקסט כשכל ההעדפות מאפשרות הצגה מלאה', () {
      const text = 'א$niqqudבג';
      final result = applyDisplayTextPreferences(text: text, profile: showAll);
      expect(result, text);
    });
  });

  group('hasCommentariesForLine', () {
    const noteLine =
        'שורה<sup class="footnote-marker">א</sup><i class="footnote">גוף ההערה</i>';
    const plainLine = 'שורה רגילה ללא הערות';

    test(
      'מחזירה true כש"הערות" פעיל ויש הערת inline בשורה — גם בלי קישורי מפרשים',
      () {
        // באג: בספרים שבהם ההערות הן המפרש היחיד, "מפרשים מתחת" לא הציג כלום.
        final result = hasCommentariesForLine(
          activeCommentators: const [kNotesCommentatorTitle],
          content: const [noteLine],
          linksByLine: const {},
          index: 0,
        );
        expect(result, isTrue);
      },
    );

    test(
      'מחזירה false כש"הערות" פעיל אך אין הערת inline בשורה ואין קישורים',
      () {
        final result = hasCommentariesForLine(
          activeCommentators: const [kNotesCommentatorTitle],
          content: const [plainLine],
          linksByLine: const {},
          index: 0,
        );
        expect(result, isFalse);
      },
    );

    test('מחזירה false כשאין מפרשים פעילים ואין קישורים', () {
      final result = hasCommentariesForLine(
        activeCommentators: const [],
        content: const [noteLine],
        linksByLine: const {},
        index: 0,
      );
      expect(result, isFalse);
    });

    test('מחזירה true כשיש קישור COMMENTARY למפרש פעיל', () {
      final result = hasCommentariesForLine(
        activeCommentators: const ['רש"י'],
        content: const [plainLine],
        linksByLine: {
          1: [
            Link(
              heRef: 'רש"י על בראשית א',
              index1: 1,
              path2: 'commentary/רש"י.txt',
              index2: 7,
              connectionType: 'COMMENTARY',
            ),
          ],
        },
        index: 0,
      );
      expect(result, isTrue);
    });

    test('מחזירה false כשהקישור הוא למפרש שאינו פעיל', () {
      final result = hasCommentariesForLine(
        activeCommentators: const ['רמב"ן'],
        content: const [plainLine],
        linksByLine: {
          1: [
            Link(
              heRef: 'רש"י על בראשית א',
              index1: 1,
              path2: 'commentary/רש"י.txt',
              index2: 7,
              connectionType: 'COMMENTARY',
            ),
          ],
        },
        index: 0,
      );
      expect(result, isFalse);
    });
  });
}

TextBookLoaded _loadedState() {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א'],
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
}

class _ClosedTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _ClosedTextBookBloc(super.initialState)
    : repository = _TestTextBookRepository(
        initialState is TextBookLoaded
            ? initialState.availableCommentators
            : const [],
      ) {
    on<TextBookEvent>((event, emit) {});
  }

  bool addWasCalled = false;

  @override
  final TextBookRepository repository;

  @override
  bool get isClosed => true;

  @override
  void add(TextBookEvent event) {
    addWasCalled = true;
    throw StateError('add לא אמור להיקרא כשה-bloc סגור');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _RecordingTextBookBloc(super.initialState)
    : repository = _TestTextBookRepository(
        initialState is TextBookLoaded
            ? initialState.availableCommentators
            : const [],
      ) {
    on<TextBookEvent>((event, emit) => received.add(event));
  }

  final List<TextBookEvent> received = [];

  @override
  final TextBookRepository repository;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ListenerCountingTextBookBloc extends _RecordingTextBookBloc {
  _ListenerCountingTextBookBloc(super.initialState);

  int activeListeners = 0;

  @override
  Stream<TextBookState> get stream {
    final source = super.stream;
    return Stream<TextBookState>.multi((controller) {
      activeListeners++;
      final subscription = source.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = () {
        activeListeners--;
        return subscription.cancel();
      };
    }, isBroadcast: true);
  }
}

class _TestTextBookRepository implements TextBookRepository {
  _TestTextBookRepository(this.commentators);

  final List<String> commentators;

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => [
    for (final title in commentators)
      Link(
        heRef: '',
        index1: startIndex + 1,
        path2: title,
        index2: 1,
        connectionType: 'commentary',
      ),
  ];

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

/// ה-SelectionArea של אזור הטקסט הראשי, לפי סוג המפתח שלו. חיפוש לפי סוג
/// המפתח הוא מה שמכשיל נסיגה חזרה ל-ValueKey שנגזר ממונה revision.
Finder _combinedSelectionAreaFinder() => find.byWidgetPredicate(
  (w) => w is SelectionArea && w.key is GlobalKey<SelectionAreaState>,
);
