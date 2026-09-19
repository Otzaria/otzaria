import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/search/in_book_search_preferences.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SearchScope, WordMatchMode;
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// שורה שחורגת בוודאות מחלון הקישורים שנטען סביב תחילת הספר, ולכן מחייבת
/// שאילתה חדשה. נגזר מהקבועים כדי שכוונון החלון לא ישבור את הבדיקות.
const int _farLine =
    TextBookBloc.linkLookAheadLines + TextBookBloc.linksReloadThresholdLines;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TextBookBloc', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    group('searchWholeWord נזרע מההעדפה', () {
      tearDown(() => InBookSearchPreferences.saveWholeWord(false));

      Future<TextBookLoaded> loadState({
        required SearchMatchPolicy matchPolicy,
      }) async {
        final bloc = _createBloc(
          repository: _FakeTextBookRepository(),
          showPageShapeView: false,
          matchPolicy: matchPolicy,
        );
        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            loadCommentators: false,
          ),
        );
        await _waitFor(
          () => bloc.state is TextBookLoaded,
          description: 'TextBookLoaded',
        );
        final state = bloc.state as TextBookLoaded;
        await bloc.close();
        return state;
      }

      test('העדפה כבויה — הדגשה חלקית כבר בטעינה', () async {
        await InBookSearchPreferences.saveWholeWord(false);
        final state = await loadState(
          matchPolicy: SearchMatchPolicy.standard,
        );
        expect(state.searchWholeWord, isFalse);
      });

      test('העדפה דלוקה — מילים שלמות', () async {
        await InBookSearchPreferences.saveWholeWord(true);
        final state = await loadState(
          matchPolicy: SearchMatchPolicy.standard,
        );
        expect(state.searchWholeWord, isTrue);
      });

      test('מסלול המנוע מתעלם מההעדפה', () async {
        await InBookSearchPreferences.saveWholeWord(false);
        final state = await loadState(
          matchPolicy: const SearchMatchPolicy(
            wordMatchMode: WordMatchMode.anyWord,
          ),
        );
        expect(state.searchWholeWord, isTrue);
      });
    });

    test('במפרשים למטה טוען קישורים מיד עבור הטווח הגלוי', () async {
      final repository = _FakeTextBookRepository();
      final bloc = _createBloc(
        repository: repository,
        showPageShapeView: false,
      );

      bloc.add(
        const LoadContent(
          fontSize: 20,
          showSplitView: false,
          removeNikud: false,
          loadCommentators: false,
        ),
      );

      await _waitFor(
        () => repository.getBookLinksInRangeCalls >= 1,
        description: 'getBookLinksInRangeCalls >= 1',
      );

      expect(repository.getBookLinksInRangeCalls, 1);
      expect(repository.lastStartIndex, 0);
      expect(repository.lastEndIndex, 10 + TextBookBloc.linkLookAheadLines);
      expect(repository.lastTargetBookTitles, isEmpty);

      await bloc.close();
    });

    test('באתחול מפרשים למטה מבקש חלון קישורים עבור הטווח הנוכחי', () async {
      final repository = _FakeTextBookRepository();
      final bloc = _createBloc(
        repository: repository,
        showPageShapeView: false,
      );

      bloc.add(
        const LoadContent(
          fontSize: 20,
          showSplitView: false,
          removeNikud: false,
          loadCommentators: false,
        ),
      );

      await _waitFor(
        () => repository.getBookLinksInRangeCalls >= 1,
        description: 'getBookLinksInRangeCalls >= 1',
      );

      expect(repository.getBookLinksInRangeCalls, 1);
      expect(repository.lastStartIndex, 0);
      expect(repository.lastEndIndex, 10 + TextBookBloc.linkLookAheadLines);
      expect(repository.lastTargetBookTitles, isEmpty);

      await bloc.close();
    });

    test(
      'במפרשים למטה טעינת הקישורים הראשונית אינה מסננת קישורים רגילים',
      () async {
        final repository = _FakeTextBookRepository();
        final bloc = _createBloc(
          repository: repository,
          showPageShapeView: false,
        );

        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            loadCommentators: false,
          ),
        );

        await _waitFor(
          () => repository.getBookLinksInRangeCalls >= 1,
          description: 'getBookLinksInRangeCalls >= 1',
        );

        expect(repository.getBookLinksInRangeCalls, 1);
        expect(repository.lastTargetBookTitles, isEmpty);

        await bloc.close();
      },
    );

    test('preview נשמר עם padding כדי לשמור אינדקסים אבסולוטיים', () {
      final lines = TextBookBloc.buildPreviewLinesForTesting(
        'שורה 11\nשורה 12\nשורה 13',
        11,
      );

      expect(lines.length, 14);
      expect(lines[0], '');
      expect(lines[10], '');
      expect(lines[11], 'שורה 11');
      expect(lines[13], 'שורה 13');
    });

    test('Markdown נטען כתוכן מומר מלא בלי טווח או preview גולמי', () async {
      final repository = _FakeTextBookRepository();
      var previewCalls = 0;
      final bloc = _createBloc(
        repository: repository,
        showPageShapeView: false,
        book: TextBook(title: 'ספר Markdown', fileType: 'md'),
        quickPreviewLoader:
            (
              title,
              currentLine, {
              categoryId,
              fileType,
              preferSource = BookSource.official,
            }) async {
              previewCalls++;
              return 'מקור גולמי';
            },
      );

      bloc.add(
        const LoadContent(
          fontSize: 20,
          showSplitView: false,
          removeNikud: false,
          loadCommentators: false,
        ),
      );
      await _waitFor(() => bloc.state is TextBookLoaded);

      expect(repository.getBookContentCalls, 1);
      expect(repository.getBookContentRangeCalls, 0);
      expect(previewCalls, 0);
      expect((bloc.state as TextBookLoaded).content, hasLength(40));
      expect((bloc.state as TextBookLoaded).content.first, 'שורה 0');
      await bloc.close();
    });

    test('קובץ Markdown מזוהה לפי הנתיב גם אם fileType מיושן', () async {
      final repository = _FakeTextBookRepository();
      final bloc = _createBloc(
        repository: repository,
        showPageShapeView: false,
        book: TextBook(
          title: 'ספר Markdown ישן',
          fileType: 'txt',
          filePath: r'C:\books\legacy.md',
        ),
      );

      bloc.add(
        const LoadContent(
          fontSize: 20,
          showSplitView: false,
          removeNikud: false,
          loadCommentators: false,
        ),
      );
      await _waitFor(() => bloc.state is TextBookLoaded);

      expect(repository.getBookContentCalls, 1);
      expect(repository.getBookContentRangeCalls, 0);
      await bloc.close();
    });

    test('Markdown בונה תוכן עניינים מאותו HTML שמוצג', () async {
      final repository = _MarkdownTocRepository();
      final bloc = _createBloc(
        repository: repository,
        showPageShapeView: false,
        book: TextBook(title: 'ספר Markdown', fileType: 'md'),
      );

      bloc.add(
        const LoadContent(
          fontSize: 20,
          showSplitView: false,
          removeNikud: false,
          loadCommentators: false,
        ),
      );
      await _waitFor(() => bloc.state is TextBookLoaded);

      final toc = (bloc.state as TextBookLoaded).tableOfContents;
      expect(toc.map((entry) => entry.index), [1, 4]);
      expect(toc.map((entry) => entry.text), ['כותרת ראשונה', 'כותרת שנייה']);
      await bloc.close();
    });

    test('החלפת תוכן רקע מלא שומרת את תוכן העניינים של הספר', () async {
      final bloc = _createBloc(
        repository: _FakeTextBookRepository(),
        showPageShapeView: false,
        book: TextBook(title: 'ספר מיושן', fileType: 'txt'),
      );
      bloc.add(
        const LoadContent(
          fontSize: 20,
          showSplitView: false,
          removeNikud: false,
          loadCommentators: false,
        ),
      );
      await _waitFor(() => bloc.state is TextBookLoaded);

      final initialToc = (bloc.state as TextBookLoaded).tableOfContents;

      bloc.add(
        const ApplyFullBookContent(
          bookTitle: 'ספר מיושן',
          content: [
            '<h1 id="first">ראשון</h1>',
            '<p>תוכן</p>',
            '<h2 id="second">שני</h2>',
          ],
        ),
      );
      final toc = (bloc.state as TextBookLoaded).tableOfContents;
      expect(toc, initialToc);
      await bloc.close();
    });

    test('טווחי תוכן טעונים נשמרים כרשימת טווחים ממוזגת ללא הנחת רציפות', () {
      final merged = TextBookBloc.mergeLoadedContentRanges(
        const [
          (startLine: 0, endLine: 100),
          (startLine: 500, endLine: 700),
        ],
        startLine: 101,
        endLine: 180,
      );

      expect(merged, const [
        (startLine: 0, endLine: 180),
        (startLine: 500, endLine: 700),
      ]);
    });

    test('בדיקת sufficiency לא מחליקה על חור באמצע הטווח', () {
      const loadedRanges = [
        (startLine: 0, endLine: 180),
        (startLine: 500, endLine: 700),
      ];

      expect(
        TextBookBloc.isContentWindowSufficient(
          loadedRanges: loadedRanges,
          startLine: 300,
          endLine: 340,
          reloadThresholdLines: 60,
        ),
        isFalse,
      );

      expect(
        TextBookBloc.isContentWindowSufficient(
          loadedRanges: loadedRanges,
          startLine: 560,
          endLine: 600,
          reloadThresholdLines: 40,
        ),
        isTrue,
      );
    });

    test('warming בוחר קודם הרחבה קדימה סביב ה-viewport', () {
      expect(
        TextBookBloc.nextWarmContentStartNearViewportForTesting(
          loadedRanges: const [
            (startLine: 4920, endLine: 5180),
          ],
          totalLines: 12000,
          visibleIndices: const [5000, 5001, 5002],
          chunkLines: 640,
        ),
        5181,
      );
    });

    test('warming חוזר אחורה רק אחרי שההמשך קדימה כבר כוסה', () {
      expect(
        TextBookBloc.nextWarmContentStartNearViewportForTesting(
          loadedRanges: const [
            (startLine: 4920, endLine: 11999),
          ],
          totalLines: 12000,
          visibleIndices: const [5000, 5001, 5002],
          chunkLines: 640,
        ),
        4280,
      );
    });

    test('warming נופל חזרה לחור הראשון אם ה-viewport לא חופף לטווח טעון', () {
      expect(
        TextBookBloc.nextWarmContentStartNearViewportForTesting(
          loadedRanges: const [
            (startLine: 1000, endLine: 1200),
            (startLine: 5000, endLine: 5200),
          ],
          totalLines: 8000,
          visibleIndices: const [3000, 3001],
          chunkLines: 640,
        ),
        0,
      );
    });

    test(
      'LoadContent משתמש ב-categoryId וב-fileType במסלול quick preview',
      () async {
        final repository = _EmptyContentTextBookRepository();
        final quickPreviewCalls =
            <
              ({
                String title,
                int currentLine,
                int? categoryId,
                String? fileType,
                BookSource preferSource,
              })
            >[];

        final bloc = _createBloc(
          repository: repository,
          showPageShapeView: false,
          // ספר אישי בשם זהה לספר רשמי: בלי preferSource ה-quick preview
          // היה מאתר את הספר הרשמי לפי שם בלבד מ-seforim.db.
          book: TextBook(
            title: 'ספר כפול',
            categoryId: 42,
            fileType: 'txt',
            source: BookSource.user,
          ),
          quickPreviewLoader:
              (
                String title,
                int currentLine, {
                int? categoryId,
                String? fileType,
                BookSource preferSource = BookSource.official,
              }) async {
                quickPreviewCalls.add((
                  title: title,
                  currentLine: currentLine,
                  categoryId: categoryId,
                  fileType: fileType,
                  preferSource: preferSource,
                ));

                if (categoryId == 42 && fileType == 'txt') {
                  return 'תוכן תצוגה מקדימה נכון';
                }

                return 'תוכן שגוי';
              },
        );

        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            loadCommentators: false,
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(quickPreviewCalls, hasLength(1));
        expect(quickPreviewCalls.single.title, 'ספר כפול');
        expect(quickPreviewCalls.single.currentLine, 10);
        expect(quickPreviewCalls.single.categoryId, 42);
        expect(quickPreviewCalls.single.fileType, 'txt');
        expect(quickPreviewCalls.single.preferSource, BookSource.user);

        final state = bloc.state;
        expect(state, isA<TextBookLoaded>());
        expect(
          (state as TextBookLoaded).content.contains('תוכן תצוגה מקדימה נכון'),
          isTrue,
        );

        await bloc.close();
      },
    );

    test(
      'בצורת הדף מתעלם מעדכון visibleIndices שגוי לפני יישור הגלילה הראשוני',
      () async {
        final repository = _FakeTextBookRepository();
        final bloc = _createBloc(
          repository: repository,
          showPageShapeView: true,
        );

        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            loadCommentators: false,
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(repository.getBookLinksInRangeCalls, 1);
        expect((bloc.state as TextBookLoaded).visibleIndices, const [10]);

        bloc.add(const UpdateVisibleIndecies([0, 1, 2, 3]));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(repository.getBookLinksInRangeCalls, 1);
        expect((bloc.state as TextBookLoaded).visibleIndices, const [10]);

        bloc.add(const UpdateVisibleIndecies([10, 11, 12]));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect((bloc.state as TextBookLoaded).visibleIndices, const [
          10,
          11,
          12,
        ]);

        await bloc.close();
      },
    );

    test(
      'מסווג raw positions שגויים ככאלה שיש להתעלם מהם בזמן היישור הראשוני',
      () {
        final classification =
            TextBookBloc.classifyRawPositionsDuringInitialPageShapeVisibleSyncForTesting(
              awaitingInitialPageShapeVisibleSync: true,
              showPageShapeView: true,
              currentVisibleIndices: const [1360],
              selectedIndex: null,
              nextVisibleIndices: const [0, 1, 2, 3],
            );

        expect(classification.shouldIgnore, isTrue);
        expect(classification.shouldDispatchImmediately, isFalse);
      },
    );

    test(
      'מסווג raw positions מיושרים ככאלה שיש לשלוח מייד בזמן היישור הראשוני',
      () {
        final classification =
            TextBookBloc.classifyRawPositionsDuringInitialPageShapeVisibleSyncForTesting(
              awaitingInitialPageShapeVisibleSync: true,
              showPageShapeView: true,
              currentVisibleIndices: const [1360],
              selectedIndex: null,
              nextVisibleIndices: const [1360, 1361, 1362, 1363],
            );

        expect(classification.shouldIgnore, isFalse);
        expect(classification.shouldDispatchImmediately, isTrue);
      },
    );

    test(
      'מסווג קפיצה אמיתית מתחילת הספר כעדכון גלוי ולא כתקלה ראשונית',
      () {
        final classification =
            TextBookBloc.classifyRawPositionsDuringInitialPageShapeVisibleSyncForTesting(
              awaitingInitialPageShapeVisibleSync: true,
              showPageShapeView: true,
              currentVisibleIndices: const [0],
              selectedIndex: null,
              nextVisibleIndices: const [84, 85, 86],
            );

        expect(classification.shouldIgnore, isFalse);
        expect(classification.shouldDispatchImmediately, isTrue);
      },
    );

    test(
      'בצורת הדף מקבל דיווח גלילה אמיתי מסימן רחוק גם אם state התחיל בתחילת הספר',
      () async {
        final repository = _FakeTextBookRepository();
        final bloc = _createBloc(
          repository: repository,
          showPageShapeView: true,
          initialIndex: 0,
        );

        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            loadCommentators: false,
          ),
        );

        await _waitFor(
          () => repository.getBookLinksInRangeCalls >= 1,
          description: 'getBookLinksInRangeCalls >= 1',
        );

        expect((bloc.state as TextBookLoaded).visibleIndices, const [0]);
        expect(repository.lastStartIndex, 0);

        bloc.add(UpdateVisibleIndecies([_farLine, _farLine + 1, _farLine + 2]));

        await _waitFor(
          () => repository.getBookLinksInRangeCalls >= 2,
          description: 'getBookLinksInRangeCalls >= 2',
        );

        expect(
          (bloc.state as TextBookLoaded).visibleIndices,
          [_farLine, _farLine + 1, _farLine + 2],
        );
        expect(
          repository.lastStartIndex,
          _farLine - TextBookBloc.linkLookBehindLines,
        );
        expect(
          repository.lastEndIndex,
          _farLine + 2 + TextBookBloc.linkLookAheadLines,
        );

        await bloc.close();
      },
    );

    test(
      'בצורת הדף ApplyMarkHighlight טוען קישורים לחלון היעד גם כשה-controller לא מחובר',
      () async {
        // רגרסיה: קישור deep-link לטאב ברקע נבלע ב-position listener (הגלילה
        // מדולגת כי ה-controller לא מחובר), ואז חלוניות המפרשים נשארו על החלון
        // הקודם. הטעינה הישירה של קישורי היעד מבטיחה סנכרון נכון.
        final repository = _FakeTextBookRepository();
        final bloc = _createBloc(
          repository: repository,
          showPageShapeView: true,
          initialIndex: 10,
        );

        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            loadCommentators: false,
          ),
        );

        await _waitFor(
          () => repository.getBookLinksInRangeCalls >= 1,
          description: 'getBookLinksInRangeCalls >= 1',
        );

        bloc.add(
          const ApplyMarkHighlight(
            permanentHighlightLine: 1801,
            scrollToIndex: 1801,
          ),
        );

        await _waitFor(
          () => repository.getBookLinksInRangeCalls >= 2,
          description: 'getBookLinksInRangeCalls >= 2',
        );

        expect(
          repository.lastStartIndex,
          1801 - TextBookBloc.linkLookBehindLines,
        );
        expect(
          repository.lastEndIndex,
          1801 + TextBookBloc.linkLookAheadLines,
        );

        await bloc.close();
      },
    );

    test('בצורת הדף טוען קישורים רק למפרשים שנבחרו בחלוניות', () async {
      final repository = _FakeTextBookRepository();
      await PageShapeSettingsManager.saveConfiguration(
        'בראשית',
        {
          'left': 'אבן עזרא על בראשית',
          'right': 'תרגום אונקלוס על בראשית',
          'bottom': 'אברבנאל על תורה',
          'bottomRight': 'בעל הטורים על בראשית',
        },
        columnVisibility: const {
          'left': true,
          'right': true,
          'bottom': true,
        },
      );

      final bloc = _createBloc(
        repository: repository,
        showPageShapeView: true,
      );

      bloc.add(
        const LoadContent(
          fontSize: 20,
          showSplitView: false,
          removeNikud: false,
          loadCommentators: false,
        ),
      );

      await _waitFor(
        () => bloc.state is TextBookLoaded,
        description: 'initial load',
      );

      bloc.add(
        const UpdateAvailableCommentators(
          [
            'אבן עזרא על בראשית',
            'תרגום אונקלוס על בראשית',
            'אברבנאל על תורה',
            'בעל הטורים על בראשית',
            'כלי יקר על בראשית',
            'רש"י על בראשית',
          ],
          [],
        ),
      );

      await _waitFor(
        () => repository.lastTargetBookTitles?.isNotEmpty == true,
        description: 'page-shape links load',
      );

      expect(
        repository.lastTargetBookTitles,
        unorderedEquals(const [
          'אבן עזרא על בראשית',
          'תרגום אונקלוס על בראשית',
          'אברבנאל על תורה',
          'בעל הטורים על בראשית',
        ]),
      );

      await bloc.close();
    });

    test('בצורת הדף גלילה שומרת גם את מפרשי חלונית הצד (issue #906)', () async {
      final repository = _FakeTextBookRepository();
      await PageShapeSettingsManager.saveConfiguration(
        'בראשית',
        {
          'left': 'אבן עזרא על בראשית',
          'right': null,
          'bottom': null,
          'bottomRight': null,
        },
      );

      final bloc = _createBloc(
        repository: repository,
        showPageShapeView: true,
        commentators: const ['כלי יקר על בראשית'],
      );

      bloc.add(
        const LoadContent(
          fontSize: 20,
          showSplitView: false,
          removeNikud: false,
          loadCommentators: false,
        ),
      );

      await _waitFor(
        () => bloc.state is TextBookLoaded,
        description: 'initial load',
      );

      bloc.add(
        const UpdateAvailableCommentators(
          ['אבן עזרא על בראשית', 'כלי יקר על בראשית'],
          [],
        ),
      );

      await _waitFor(
        () => repository.lastTargetBookTitles?.isNotEmpty == true,
        description: 'page-shape links load',
      );

      bloc.add(
        const UpdateVisibleIndecies([_farLine, _farLine + 1, _farLine + 2]),
      );

      await _waitFor(
        () =>
            (bloc.state as TextBookLoaded).visibleIndices.first == _farLine &&
            repository.lastStartIndex ==
                _farLine - TextBookBloc.linkLookBehindLines,
        description: 'links reload after scroll',
      );

      expect(
        repository.lastTargetBookTitles,
        unorderedEquals(const [
          'אבן עזרא על בראשית',
          'כלי יקר על בראשית',
        ]),
      );

      await bloc.close();
    });

    test('בצורת הדף רענון קישורים מכבד הגדרות טורים לפי שולחן עבודה', () async {
      final repository = _FakeTextBookRepository();
      const pageShapeConfig = {
        'left': 'אבן עזרא על בראשית',
        'right': 'תרגום אונקלוס על בראשית',
        'bottom': 'אברבנאל על תורה',
        'bottomRight': 'בעל הטורים על בראשית',
      };
      await PageShapeSettingsManager.saveConfiguration(
        'בראשית',
        pageShapeConfig,
      );
      await PageShapeSettingsManager.saveConfiguration(
        'בראשית',
        pageShapeConfig,
        saveToWorkspaceId: 'workspace-1',
        columnVisibility: const {
          'left': true,
          'right': false,
          'bottom': false,
          'bottomRight': false,
        },
      );
      await PageShapeSettingsManager.saveConfiguration(
        'בראשית',
        pageShapeConfig,
        saveToWorkspaceId: 'workspace-2',
        columnVisibility: const {
          'left': false,
          'right': true,
          'bottom': false,
          'bottomRight': false,
        },
      );

      final bloc = _createBloc(
        repository: repository,
        showPageShapeView: true,
      );

      bloc.add(
        const LoadContent(
          fontSize: 20,
          showSplitView: false,
          removeNikud: false,
          loadCommentators: false,
        ),
      );

      await _waitFor(
        () => bloc.state is TextBookLoaded,
        description: 'initial load',
      );

      bloc.add(
        const UpdateAvailableCommentators(
          [
            'אבן עזרא על בראשית',
            'תרגום אונקלוס על בראשית',
            'אברבנאל על תורה',
            'בעל הטורים על בראשית',
          ],
          [],
        ),
      );

      await _waitFor(
        () => repository.lastTargetBookTitles?.isNotEmpty == true,
        description: 'initial links load',
      );

      bloc.add(
        const RefreshLinksForCurrentWindow(
          reason: 'workspace-1',
          workspaceId: 'workspace-1',
        ),
      );
      await _waitFor(
        () => repository.lastTargetBookTitles?.length == 1,
        description: 'workspace-1 links reload',
      );
      expect(repository.lastTargetBookTitles, ['אבן עזרא על בראשית']);

      bloc.add(
        const RefreshLinksForCurrentWindow(
          reason: 'workspace-2',
          workspaceId: 'workspace-2',
        ),
      );
      await _waitFor(
        () =>
            repository.lastTargetBookTitles?.length == 1 &&
            repository.lastTargetBookTitles?.first == 'תרגום אונקלוס על בראשית',
        description: 'workspace-2 links reload',
      );
      expect(repository.lastTargetBookTitles, ['תרגום אונקלוס על בראשית']);

      await bloc.close();
    });

    test('במצב מפוצל טוען קישורים רק למפרשים הפעילים', () async {
      final repository = _FakeTextBookRepository();
      final bloc = _createBloc(
        repository: repository,
        showPageShapeView: false,
        commentators: const [
          'רש"י על בראשית',
          'אבן עזרא על בראשית',
        ],
      );

      bloc.add(
        const LoadContent(
          fontSize: 20,
          showSplitView: true,
          removeNikud: false,
          loadCommentators: false,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        repository.lastTargetBookTitles,
        [
          'אבן עזרא על בראשית',
          'רש"י על בראשית',
        ],
      );

      await bloc.close();
    });

    test('במפרשים למטה גלילה טוענת מחדש קישורים גם כשהחלונית סגורה', () async {
      final repository = _FakeTextBookRepository();
      final bloc = _createBloc(
        repository: repository,
        showPageShapeView: false,
        commentators: const ['רש"י על בראשית'],
      );

      bloc.add(
        const LoadContent(
          fontSize: 20,
          showSplitView: false,
          removeNikud: false,
          loadCommentators: false,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(repository.getBookLinksInRangeCalls, 1);

      // חורג מחלון הקישורים שכבר נטען, אחרת הגלילה נענית ממנו בלי שאילתה.
      bloc.add(UpdateVisibleIndecies([_farLine, _farLine + 1, _farLine + 2]));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(repository.getBookLinksInRangeCalls, 2);

      await bloc.close();
    });

    test(
      'במפרשים למטה בחירה חוזרת של אותה שורה לא טוענת מחדש כשהחלון כבר מכוסה',
      () async {
        final repository = _FakeTextBookRepository();
        final bloc = _createBloc(
          repository: repository,
          showPageShapeView: false,
          commentators: const ['רש"י על בראשית'],
        );

        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            loadCommentators: false,
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(repository.getBookLinksInRangeCalls, 1);

        bloc.add(const UpdateSelectedIndex(12));
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(repository.getBookLinksInRangeCalls, 1);

        bloc.add(const UpdateSelectedIndex(12));
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(repository.getBookLinksInRangeCalls, 1);

        await bloc.close();
      },
    );

    test(
      'Ctrl+בחירה (additive) צובר ומסיר קטעים מ-selectedIndices',
      () async {
        final repository = _FakeTextBookRepository();
        final bloc = _createBloc(
          repository: repository,
          showPageShapeView: false,
          commentators: const ['רש"י על בראשית'],
        );

        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            loadCommentators: false,
          ),
        );
        await _waitFor(
          () => bloc.state is TextBookLoaded,
          description: 'initial load',
        );
        TextBookLoaded loaded() => bloc.state as TextBookLoaded;

        bloc.add(const UpdateSelectedIndex(12));
        await _waitFor(
          () => bloc.state is TextBookLoaded && loaded().selectedIndex == 12,
          description: 'select 12',
        );
        expect(loaded().selectedIndices, {12});

        // הוספת קטע שני בלחיצת Ctrl
        bloc.add(const UpdateSelectedIndex(20, additive: true));
        await _waitFor(
          () => loaded().selectedIndices.contains(20),
          description: 'add 20',
        );
        expect(loaded().selectedIndices, {12, 20});
        expect(loaded().selectedIndex, 20);

        // Ctrl על קטע שכבר נבחר → מסיר אותו, העוגן עובר לקטע שנותר
        bloc.add(const UpdateSelectedIndex(20, additive: true));
        await _waitFor(
          () => !loaded().selectedIndices.contains(20),
          description: 'remove 20',
        );
        expect(loaded().selectedIndices, {12});
        expect(loaded().selectedIndex, 12);

        // לחיצה רגילה (לא additive) מאפסת לקטע יחיד
        bloc.add(const UpdateSelectedIndex(5));
        await _waitFor(
          () => loaded().selectedIndices.contains(5),
          description: 'reset to 5',
        );
        expect(loaded().selectedIndices, {5});

        await bloc.close();
      },
    );

    test(
      'במפרשים למטה שינוי מפרשים טוען את הטווח הנוכחי בלי force מיותר',
      () async {
        final repository = _FakeTextBookRepository();
        final bloc = _createBloc(
          repository: repository,
          showPageShapeView: false,
          commentators: const ['רש"י על בראשית'],
        );

        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            loadCommentators: false,
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 50));

        // גלילה בתוך החלון שכבר נטען אינה מייצרת שאילתה נוספת.
        bloc.add(const UpdateVisibleIndecies([20, 21, 22]));
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(repository.getBookLinksInRangeCalls, 1);

        bloc.add(const UpdateCommentators(['אבן עזרא על בראשית']));
        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(repository.getBookLinksInRangeCalls, 2);
        expect(repository.lastStartIndex, 0);
        expect(
          repository.lastEndIndex,
          22 + TextBookBloc.linkLookAheadLines,
        );
        expect(repository.lastTargetBookTitles, ['אבן עזרא על בראשית']);

        await bloc.close();
      },
    );

    group('חלון טעינת הקישורים', () {
      test('הכיסוי קדימה ואחורה מגיע לפחות עד נקודת הטעינה מחדש', () {
        // אילו הכיסוי היה קטן מהסף, שורות שבין קצה הכיסוי לנקודת הטעינה
        // היו מוצגות בלי מפרשים ושום טעינה לא הייתה מופעלת עבורן.
        expect(
          TextBookBloc.linkLookAheadLines,
          greaterThanOrEqualTo(TextBookBloc.linksReloadThresholdLines),
        );
        expect(
          TextBookBloc.linkLookBehindLines,
          greaterThanOrEqualTo(TextBookBloc.linksReloadThresholdLines),
        );
      });

      test('הסף גדול דיו כדי לא לטעון מחדש בכל תזוזת שורה', () {
        expect(TextBookBloc.linksReloadThresholdLines, greaterThan(20));
      });

      test('גלילה בתוך החלון הטעון אינה מייצרת שאילתה נוספת', () async {
        final repository = _FakeTextBookRepository();
        final bloc = _createBloc(
          repository: repository,
          showPageShapeView: false,
          commentators: const ['רש"י על בראשית'],
        );

        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            loadCommentators: false,
          ),
        );

        await _waitFor(
          () => repository.getBookLinksInRangeCalls >= 1,
          description: 'טעינה ראשונה',
        );
        final afterLoad = repository.getBookLinksInRangeCalls;

        for (final index in [12, 15, 18, 21, 24]) {
          bloc.add(UpdateVisibleIndecies([index, index + 1]));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }

        expect(repository.getBookLinksInRangeCalls, afterLoad);

        await bloc.close();
      });

      test('גלילה מעבר לחלון הטעון מייצרת שאילתה', () async {
        final repository = _FakeTextBookRepository();
        final bloc = _createBloc(
          repository: repository,
          showPageShapeView: false,
          commentators: const ['רש"י על בראשית'],
        );

        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            loadCommentators: false,
          ),
        );

        await _waitFor(
          () => repository.getBookLinksInRangeCalls >= 1,
          description: 'טעינה ראשונה',
        );

        bloc.add(UpdateVisibleIndecies([_farLine, _farLine + 1]));

        await _waitFor(
          () => repository.getBookLinksInRangeCalls >= 2,
          description: 'טעינה אחרי חריגה מהחלון',
        );

        expect(
          repository.lastEndIndex,
          _farLine + 1 + TextBookBloc.linkLookAheadLines,
        );

        await bloc.close();
      });

      test(
        'בצורת הדף בחירת מפרש בחלונית הצד אינה מנתקת את הקישורים',
        () async {
          // רגרסיה: UpdateCommentators דורס את הקישורים ביעדים של הסרגל.
          // אם הגלילה שאחריו לא תפתור מחדש את יעדי צורת הדף, חלוניות
          // המפרשים יישארו בלי קישורים ויפסיקו לעקוב אחרי הטקסט.
          final repository = _FakeTextBookRepository();
          final bloc = _createBloc(
            repository: repository,
            showPageShapeView: true,
            commentators: const ['רש"י על בראשית'],
          );

          bloc.add(
            const LoadContent(
              fontSize: 20,
              showSplitView: false,
              removeNikud: false,
              loadCommentators: false,
            ),
          );

          await _waitFor(
            () => repository.getBookLinksInRangeCalls >= 1,
            description: 'טעינה ראשונה',
          );

          bloc.add(const UpdateCommentators(['אבן עזרא על בראשית']));
          await Future<void>.delayed(const Duration(milliseconds: 80));
          final afterOverride = repository.getBookLinksInRangeCalls;

          bloc.add(
            const UpdateVisibleIndecies([
              _farLine,
              _farLine + 1,
              _farLine + 2,
            ]),
          );

          await _waitFor(
            () => repository.getBookLinksInRangeCalls > afterOverride,
            description: 'הגלילה פותרת מחדש את יעדי צורת הדף',
          );

          await bloc.close();
        },
      );
    });

    test('ToggleLeftPane לא פולט state חדש אם הערך לא השתנה', () async {
      final repository = _FakeTextBookRepository();
      final bloc = _createBloc(
        repository: repository,
        showPageShapeView: false,
      );

      bloc.add(
        const LoadContent(
          fontSize: 20,
          showSplitView: false,
          removeNikud: false,
          loadCommentators: false,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      var emittedStates = 0;
      final subscription = bloc.stream.listen((_) {
        emittedStates++;
      });

      bloc.add(const ToggleLeftPane(false));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(emittedStates, 0);

      await subscription.cancel();
      await bloc.close();
    });

    // ── בדיקות שמירת מצב ניקוד ונעיצה ב-preserveState reload ──

    test(
      'LoadContent(preserveRemoveNikud:true) שומר ניקוד שהמשתמש שינה ידנית',
      () async {
        final repository = _FakeTextBookRepository();
        final bloc = _createBloc(
          repository: repository,
          showPageShapeView: false,
        );

        // טעינה ראשונית עם removeNikud=false
        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            loadCommentators: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect((bloc.state as TextBookLoaded).removeNikud, isFalse);

        // המשתמש מפעיל הסרת ניקוד ידנית
        bloc.add(
          const ApplyDisplayPatch(
            target: TextTarget.body,
            patch: TextDisplayPatch(nikud: MarkVisibility.hide),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect((bloc.state as TextBookLoaded).removeNikud, isTrue);

        // רענון בגין שינוי גופן בלבד – מצפה שמצב הניקוד יישמר
        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false, // ערך Settings: false
            preserveState: true,
            preserveRemoveNikud: true, // שמור את מה שהמשתמש בחר
            loadCommentators: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          (bloc.state as TextBookLoaded).removeNikud,
          isTrue,
          reason: 'שינוי גופן לא אמור לאפס את בחירת הניקוד של המשתמש',
        );

        await bloc.close();
      },
    );

    test(
      'LoadContent(preserveState:true) שומר עקיפות תצוגה של מפרשים',
      () async {
        final repository = _FakeTextBookRepository();
        final bloc = _createBloc(
          repository: repository,
          showPageShapeView: false,
        );

        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            loadCommentators: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        bloc.add(
          const ApplyDisplayPatch(
            target: TextTarget.commentary,
            patch: TextDisplayPatch(nikud: MarkVisibility.show),
          ),
        );
        bloc.add(
          const ApplyDisplayPatch(
            target: TextTarget.commentary,
            patch: TextDisplayPatch(punctuation: MarkVisibility.show),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            preserveState: true,
            loadCommentators: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final state = bloc.state as TextBookLoaded;
        expect(state.commentaryRemoveNikudOverride, isFalse);
        expect(state.commentaryRemovePunctuationOverride, isFalse);

        await bloc.close();
      },
    );

    test(
      'LoadContent(preserveRemoveNikud:false) מחיל ניקוד חדש מה-Settings',
      () async {
        final repository = _FakeTextBookRepository();
        final bloc = _createBloc(
          repository: repository,
          showPageShapeView: false,
        );

        // טעינה ראשונית עם removeNikud=false
        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            loadCommentators: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // המשתמש מפעיל הסרת ניקוד ידנית
        bloc.add(
          const ApplyDisplayPatch(
            target: TextTarget.body,
            patch: TextDisplayPatch(nikud: MarkVisibility.hide),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect((bloc.state as TextBookLoaded).removeNikud, isTrue);

        // רענון בגין שינוי הגדרות ניקוד גלובליות – מצפה להחיל ערך חדש
        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false, // ערך Settings החדש: false
            preserveState: true,
            preserveRemoveNikud: false, // אל תשמר – החל ערך חדש
            loadCommentators: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          (bloc.state as TextBookLoaded).removeNikud,
          isFalse,
          reason: 'שינוי הגדרות ניקוד גלובלי חייב להחיל את הערך החדש',
        );

        await bloc.close();
      },
    );

    test(
      'LoadContent(preserveRemovePunctuation:true) שומר פיסוק שהמשתמש הסתיר',
      () async {
        final repository = _FakeTextBookRepository();
        final bloc = _createBloc(
          repository: repository,
          showPageShapeView: false,
        );

        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            loadCommentators: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect((bloc.state as TextBookLoaded).removePunctuation, isFalse);

        // המשתמש מסתיר פיסוק ידנית
        bloc.add(
          const ApplyDisplayPatch(
            target: TextTarget.body,
            patch: TextDisplayPatch(punctuation: MarkVisibility.hide),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect((bloc.state as TextBookLoaded).removePunctuation, isTrue);

        // רענון בגין שינוי גופן – מצפה שהסתרת הפיסוק תישמר
        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            preserveState: true,
            preserveRemoveNikud: true,
            preserveRemovePunctuation: true,
            loadCommentators: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          (bloc.state as TextBookLoaded).removePunctuation,
          isTrue,
          reason: 'שינוי גופן לא אמור להחזיר פיסוק שהמשתמש הסתיר',
        );

        await bloc.close();
      },
    );

    test(
      'LoadContent ללא preserveRemovePunctuation מאפס את הסתרת הפיסוק',
      () async {
        final repository = _FakeTextBookRepository();
        final bloc = _createBloc(
          repository: repository,
          showPageShapeView: false,
        );

        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            loadCommentators: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        bloc.add(
          const ApplyDisplayPatch(
            target: TextTarget.body,
            patch: TextDisplayPatch(punctuation: MarkVisibility.hide),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect((bloc.state as TextBookLoaded).removePunctuation, isTrue);

        // המסלול של _resetPerBookSettings – בלי הדגל, הפיסוק חוזר לברירת מחדל
        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            preserveState: true,
            loadCommentators: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          (bloc.state as TextBookLoaded).removePunctuation,
          isFalse,
          reason: 'איפוס הגדרות פר-ספר חייב להחזיר את הפיסוק לברירת המחדל',
        );

        await bloc.close();
      },
    );

    test(
      'LoadContent(preserveState:true) תמיד שומר pinLeftPane ללא קשר לשינוי הגופן',
      () async {
        final repository = _FakeTextBookRepository();
        final bloc = _createBloc(
          repository: repository,
          showPageShapeView: false,
        );

        // Settings: pin-sidebar = false
        await Settings.setValue<bool>('key-pin-sidebar', false);

        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            loadCommentators: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect((bloc.state as TextBookLoaded).pinLeftPane, isFalse);

        // המשתמש נועץ את החלונית
        bloc.add(const TogglePinLeftPane(true));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect((bloc.state as TextBookLoaded).pinLeftPane, isTrue);

        // רענון בגין שינוי גופן – מצפה שהנעיצה תישמר
        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            preserveState: true,
            preserveRemoveNikud: true,
            loadCommentators: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          (bloc.state as TextBookLoaded).pinLeftPane,
          isTrue,
          reason: 'שינוי גופן לא אמור לבטל את נעיצת חלונית המפרשים',
        );

        await bloc.close();
      },
    );

    test(
      'LoadContent(preserveState:true) שומר pinLeftPane גם ברענון הגדרות ניקוד',
      () async {
        final repository = _FakeTextBookRepository();
        final bloc = _createBloc(
          repository: repository,
          showPageShapeView: false,
        );

        await Settings.setValue<bool>('key-pin-sidebar', false);

        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            loadCommentators: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        bloc.add(const TogglePinLeftPane(true));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect((bloc.state as TextBookLoaded).pinLeftPane, isTrue);

        // רענון בגין שינוי הגדרות ניקוד – מצפה שהנעיצה תישמר גם כן
        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            preserveState: true,
            preserveRemoveNikud: false,
            loadCommentators: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          (bloc.state as TextBookLoaded).pinLeftPane,
          isTrue,
          reason: 'שינוי הגדרות ניקוד לא אמור לבטל את נעיצת חלונית המפרשים',
        );

        await bloc.close();
      },
    );
    test('LoadContent מציג preview לפני שטעינת הספר המלא הסתיימה', () async {
      final repository = _DelayedContentTextBookRepository();
      final bloc = _createBloc(
        repository: repository,
        showPageShapeView: false,
        quickPreviewLoader:
            (
              String title,
              int currentLine, {
              int? categoryId,
              String? fileType,
              BookSource preferSource = BookSource.official,
            }) async {
              return 'שורת preview 10\nשורת preview 11';
            },
      );

      bloc.add(
        const LoadContent(
          fontSize: 20,
          showSplitView: false,
          removeNikud: false,
          loadCommentators: false,
        ),
      );

      await _waitFor(
        () =>
            bloc.state is TextBookLoaded &&
            (bloc.state as TextBookLoaded).content.contains('שורת preview 10'),
        description: 'preview content loaded',
      );

      var state = bloc.state;
      expect(state, isA<TextBookLoaded>());
      expect(
        (state as TextBookLoaded).content,
        contains('שורת preview 10'),
      );
      expect(repository.getBookContentCalls, 1);

      repository.completeFullContent(
        List.generate(30, (index) => 'שורה מלאה $index').join('\n'),
      );
      await _waitFor(
        () =>
            bloc.state is TextBookLoaded &&
            (bloc.state as TextBookLoaded).content.length == 30,
        description: 'full content loaded',
      );

      state = bloc.state;
      expect((state as TextBookLoaded).content.length, 30);
      expect(state.content.first, 'שורה מלאה 0');

      await bloc.close();
    });

    test(
      'UpdateFontSize שמגיע בזמן Loading מוחל כשהמצב עובר ל-Loaded',
      () async {
        // רגרסיה: בעליית התוכנה ההגדרות נטענות מהר יותר מתוכן הספר, כך
        // ש-UpdateFontSize (מהאזנה ל-SettingsBloc) מגיע בזמן TextBookLoading.
        // לפני התיקון הוא נבלע (no-op), והתצוגה נתקעה על גודל ברירת המחדל.
        final repository = _DelayedContentTextBookRepository();
        final bloc = _createBloc(
          repository: repository,
          showPageShapeView: false,
          quickPreviewLoader:
              (
                String title,
                int currentLine, {
                int? categoryId,
                String? fileType,
                BookSource preferSource = BookSource.official,
              }) async =>
                  null, // ללא preview – הבלוק נשאר ב-Loading עד getBookContent
        );

        bloc.add(
          const LoadContent(
            fontSize: 16, // ערך ברירת מחדל "תקוע" של SettingsState.initial()
            showSplitView: false,
            removeNikud: false,
            loadCommentators: false,
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(bloc.state, isA<TextBookLoading>());

        // ההגדרות נטענו ושידרו 25 בעוד התוכן עדיין נטען
        bloc.add(const UpdateFontSize(25));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // השלמת טעינת התוכן → המעבר ל-Loaded חייב לשקף את 25, לא את 16
        repository.completeFullContent(
          List.generate(30, (index) => 'שורה $index').join('\n'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final state = bloc.state;
        expect(state, isA<TextBookLoaded>());
        expect(
          (state as TextBookLoaded).fontSize,
          25,
          reason: 'שינוי גופן שהגיע בזמן הטעינה לא אמור ללכת לאיבוד',
        );

        await bloc.close();
      },
    );

    group('הדגשה מ-deep link', () {
      test(
        'ApplyMarkHighlight מגדיר highlightText ו-permanentHighlightLine',
        () async {
          final repository = _FakeTextBookRepository();
          final bloc = _createBloc(
            repository: repository,
            showPageShapeView: false,
          );

          bloc.add(
            const LoadContent(
              fontSize: 20,
              showSplitView: false,
              removeNikud: false,
              loadCommentators: false,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 50));

          bloc.add(
            const UpdateSearchText(
              'שאלה ישנה',
              searchOptions: {},
              alternativeWords: {},
              spacingValues: {},
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 30));

          bloc.add(
            const ApplyMarkHighlight(
              highlightText: 'בראשית',
              scrollToIndex: 7,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 30));

          final state = bloc.state as TextBookLoaded;
          expect(state.highlightText, 'בראשית');
          expect(state.searchText, isEmpty);
          expect(state.searchMode, SearchMode.exact);

          await bloc.close();
        },
      );

      test(
        'ApplyMarkHighlight עם permanentHighlightLine=null מנקה הדגשה',
        () async {
          final repository = _FakeTextBookRepository();
          final bloc = _createBloc(
            repository: repository,
            showPageShapeView: false,
          );

          bloc.add(
            const LoadContent(
              fontSize: 20,
              showSplitView: false,
              removeNikud: false,
              loadCommentators: false,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 50));

          bloc.add(
            const ApplyMarkHighlight(
              highlightText: 'תורה',
              permanentHighlightLine: 3,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 30));

          bloc.add(const ApplyMarkHighlight());
          await Future<void>.delayed(const Duration(milliseconds: 30));

          final state = bloc.state as TextBookLoaded;
          expect(state.permanentHighlightLine, isNull);

          await bloc.close();
        },
      );

      test('ApplyMarkHighlight עם highlightText ריק', () async {
        final repository = _FakeTextBookRepository();
        final bloc = _createBloc(
          repository: repository,
          showPageShapeView: false,
        );

        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            loadCommentators: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        bloc.add(
          const ApplyMarkHighlight(
            highlightText: '',
            permanentHighlightLine: 5,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));

        final state = bloc.state as TextBookLoaded;
        expect(state.highlightText, '');
        expect(state.permanentHighlightLine, 5);

        await bloc.close();
      });
    });

    group('מדיניות ההתאמה של החיפוש', () {
      test('נשמרת מה-state ההתחלתי אל TextBookLoaded', () async {
        // הטאב נפתח עם הקונפיגורציה שבה נמצאה התוצאה; בלעדיה חלונית החיפוש
        // בספר הייתה שולחת למנוע חיפוש מרווח-מילים רגיל.
        final repository = _FakeTextBookRepository();
        final bloc = _createBloc(
          repository: repository,
          showPageShapeView: false,
          matchPolicy: const SearchMatchPolicy(
            proximityScope: SearchScope.sameParagraph,
            wordMatchMode: WordMatchMode.atLeast,
            wordMatchCount: 3,
          ),
        );

        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            loadCommentators: false,
          ),
        );
        await _waitFor(
          () => bloc.state is TextBookLoaded,
          description: 'טעינת תוכן',
        );

        final policy = (bloc.state as TextBookLoaded).matchPolicy;
        expect(policy.proximityScope, SearchScope.sameParagraph);
        expect(policy.wordMatchMode, WordMatchMode.atLeast);
        expect(policy.wordMatchCount, 3);

        await bloc.close();
      });

      test('שורות התוצאות נשמרות ב-state, ושאילתה חדשה מאפסת אותן', () async {
        // ההדגשה במדיניות שאינה ברירת המחדל מוגבלת לשורות האלה; שאריות
        // מחיפוש קודם היו צובעות שורות שאינן תוצאה.
        final repository = _FakeTextBookRepository();
        final bloc = _createBloc(
          repository: repository,
          showPageShapeView: false,
        );

        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            loadCommentators: false,
          ),
        );
        await _waitFor(
          () => bloc.state is TextBookLoaded,
          description: 'טעינת תוכן',
        );
        expect((bloc.state as TextBookLoaded).searchResultLines, isNull);

        bloc.add(const UpdateSearchResultLines({3, 17}));
        await _waitFor(
          () => (bloc.state as TextBookLoaded).searchResultLines != null,
          description: 'עדכון שורות התוצאות',
        );
        expect((bloc.state as TextBookLoaded).searchResultLines, {3, 17});

        bloc.add(
          const UpdateSearchText(
            'שאילתה אחרת',
            searchOptions: {},
            alternativeWords: {},
            spacingValues: {},
          ),
        );
        await _waitFor(
          () => (bloc.state as TextBookLoaded).searchText == 'שאילתה אחרת',
          description: 'עדכון השאילתה',
        );
        expect((bloc.state as TextBookLoaded).searchResultLines, isNull);

        await bloc.close();
      });

      test(
        'שורת תוצאה גלובלית נשמרת מהמצב ההתחלתי אל TextBookLoaded',
        () async {
          final bloc = _createBloc(
            repository: _FakeTextBookRepository(),
            showPageShapeView: false,
            initialSearchResultLines: {10},
          );

          bloc.add(
            const LoadContent(
              fontSize: 20,
              showSplitView: false,
              removeNikud: false,
              loadCommentators: false,
            ),
          );
          await _waitFor(
            () => bloc.state is TextBookLoaded,
            description: 'טעינת תוכן',
          );

          expect((bloc.state as TextBookLoaded).searchResultLines, {10});
          await bloc.close();
        },
      );

      test('UpdateSearchText מעדכן את מדיניות ההתאמה', () async {
        final repository = _FakeTextBookRepository();
        final bloc = _createBloc(
          repository: repository,
          showPageShapeView: false,
        );

        bloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            loadCommentators: false,
          ),
        );
        await _waitFor(
          () => bloc.state is TextBookLoaded,
          description: 'טעינת תוכן',
        );

        bloc.add(
          const UpdateSearchText(
            'תדע זרעך',
            searchOptions: {},
            alternativeWords: {},
            spacingValues: {},
            searchMode: SearchMode.advanced,
            searchDistance: 3,
            matchPolicy: SearchMatchPolicy(
              proximityScope: SearchScope.sameSection,
            ),
          ),
        );
        await _waitFor(
          () =>
              (bloc.state as TextBookLoaded).matchPolicy.proximityScope ==
              SearchScope.sameSection,
          description: 'עדכון מדיניות ההתאמה',
        );

        final state = bloc.state as TextBookLoaded;
        expect(state.searchDistance, 3);
        expect(state.searchMode, SearchMode.advanced);

        await bloc.close();
      });
    });
  });
}

/// ממתינה עד שהתנאי מתקיים, או נכשלת ב-timeout עם הודעה ברורה.
///
/// קיימים ב-bloc מספר awaits פנימיים (load content → resolve target titles
/// → repository call), כך ש-`Future.delayed` קבוע לא דטרמיניסטי תחת עומס
/// (במיוחד בטסט הראשון של הקובץ, לפני JIT warm-up). polling קצר וקצוב
/// יציב יותר מבלי להאריך את הריצה במקרה הרגיל.
Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  String description = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('$description not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

TextBookBloc _createBloc({
  required TextBookRepository repository,
  required bool showPageShapeView,
  List<String> commentators = const [],
  TextBook? book,
  int initialIndex = 10,
  SearchMatchPolicy matchPolicy = SearchMatchPolicy.standard,
  Set<int>? initialSearchResultLines,
  Future<String?> Function(
    String title,
    int currentLine, {
    int? categoryId,
    String? fileType,
    BookSource preferSource,
  })?
  quickPreviewLoader,
}) {
  return TextBookBloc(
    repository: repository,
    quickPreviewLoader: quickPreviewLoader,
    initialState: TextBookInitial.named(
      book ?? TextBook(title: 'בראשית'),
      initialIndex,
      false,
      commentators,
      searchMode: SearchMode.exact,
      matchPolicy: matchPolicy,
      initialSearchResultLines: initialSearchResultLines,
      showPageShapeView: showPageShapeView,
    ),
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

class _FakeTextBookRepository extends TextBookRepository {
  _FakeTextBookRepository() : super(fileSystem: FileSystemData.instance);

  int getBookLinksInRangeCalls = 0;
  int? lastStartIndex;
  int? lastEndIndex;
  List<String>? lastTargetBookTitles;
  int getBookContentCalls = 0;
  int getBookContentRangeCalls = 0;

  @override
  Future<String> getBookContent(TextBook book) async {
    getBookContentCalls++;
    return List.generate(40, (index) => 'שורה $index').join('\n');
  }

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
  }) async {
    getBookContentRangeCalls++;
    final contentLines = List.generate(40, (index) => 'line $index');
    final normalizedStart = startLine.clamp(0, contentLines.length - 1);
    final normalizedEnd = endLine.clamp(
      normalizedStart,
      contentLines.length - 1,
    );
    return BookContentRange(
      startLine: normalizedStart,
      endLine: normalizedEnd,
      totalLines: contentLines.length,
      lines: contentLines.sublist(normalizedStart, normalizedEnd + 1),
    );
  }

  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async {
    return const [];
  }

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async {
    getBookLinksInRangeCalls++;
    lastStartIndex = startIndex;
    lastEndIndex = endIndex;
    lastTargetBookTitles = targetBookTitles?.toList();
    return const [];
  }

  @override
  Future<List<String>> getAvailableCommentators(TextBook book) async {
    return const [];
  }
}

class _EmptyContentTextBookRepository extends _FakeTextBookRepository {
  @override
  Future<String> getBookContent(TextBook book) async {
    return '';
  }

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
  }) async {
    return null;
  }
}

class _MarkdownTocRepository extends _FakeTextBookRepository {
  @override
  Future<String> getBookContent(TextBook book) async {
    getBookContentCalls++;
    return [
      '<p>פתיחה</p>',
      '<h1 id="first">כותרת ראשונה</h1>',
      '<p>א</p>',
      '<p>ב</p>',
      '<h1 id="second">כותרת שנייה</h1>',
      '<p>סיום</p>',
    ].join('\n');
  }

  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async {
    // Simulates a stale TOC whose indexes came from raw Markdown.
    return [TocEntry(text: 'כותרת ראשונה', index: 0)];
  }
}

class _DelayedContentTextBookRepository extends _FakeTextBookRepository {
  final Completer<String> _fullContentCompleter = Completer<String>();

  @override
  Future<String> getBookContent(TextBook book) async {
    getBookContentCalls++;
    return _fullContentCompleter.future;
  }

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
  }) async {
    return null;
  }

  void completeFullContent(String content) {
    if (!_fullContentCompleter.isCompleted) {
      _fullContentCompleter.complete(content);
    }
  }
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) {
      return value;
    }
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }
}
