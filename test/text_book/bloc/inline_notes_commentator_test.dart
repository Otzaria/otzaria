import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../test_helpers/memory_cache_provider.dart';

class _FakeTextBookRepository extends TextBookRepository {
  _FakeTextBookRepository() : super(fileSystem: FileSystemData.instance);
}

TextBookLoaded _seed({
  required TextBook book,
  required List<String> content,
  List<String> activeCommentators = const [],
  List<String> availableCommentators = const [],
}) {
  return TextBookLoaded(
    book: book,
    content: content,
    fontSize: 20,
    showLeftPane: true,
    showSplitView: false,
    activeCommentators: activeCommentators,
    commentatorGroups: const [],
    availableCommentators: availableCommentators,
    links: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TextBookBloc bloc;
  late TextBook book;
  late Directory tempDataRoot;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    // הפניית כתיבת ההגדרות הפר-ספריות לתיקיית temp במקום ל-AppData האמיתי,
    // כדי שהשמירה (fire-and-forget) בבחירת מפרשים לא תזהם נתוני משתמש.
    tempDataRoot = await Directory.systemTemp.createTemp('otzaria_test_');
    AppPaths.debugOverrideDataRootPath(tempDataRoot.path);
  });

  tearDownAll(() async {
    // חייב לקדום להסרת ה-override: שמירה תלויה עדיין מחזיקה את הקובץ פתוח
    // (המחיקה נכשלת ב-Windows) ותפתור את הנתיב מחדש אל AppData האמיתי.
    await PerBookSettings.settle();
    AppPaths.debugOverrideDataRootPath(null);
    if (await tempDataRoot.exists()) {
      await tempDataRoot.delete(recursive: true);
    }
  });

  setUp(() {
    book = TextBook(title: 'ספר בדיקה');
    bloc = TextBookBloc(
      repository: _FakeTextBookRepository(),
      initialState: TextBookInitial.named(book, 0, true, const []),
      scrollController: ItemScrollController(),
      positionsListener: ItemPositionsListener.create(),
    );
  });

  tearDown(() async {
    await bloc.close();
  });

  blocTest<TextBookBloc, TextBookState>(
    'ApplyFullBookContent מוסיף את "הערות" ל-availableCommentators כשיש <i class="footnote"> בתוכן המלא',
    build: () => bloc,
    seed: () => _seed(
      book: book,
      content: const ['preview ללא הערות'],
    ),
    act: (bloc) => bloc.add(
      const ApplyFullBookContent(
        bookTitle: 'ספר בדיקה',
        content: [
          'שורה רגילה',
          'שורה<sup class="footnote-marker">א</sup><i class="footnote">תוכן</i>',
        ],
      ),
    ),
    expect: () => [
      isA<TextBookLoaded>()
          .having(
            (state) => state.availableCommentators,
            'availableCommentators',
            contains(kNotesCommentatorTitle),
          )
          .having(
            (state) => state.activeCommentators,
            'activeCommentators (auto-selected)',
            const [kNotesCommentatorTitle],
          ),
    ],
  );

  blocTest<TextBookBloc, TextBookState>(
    'ApplyBookContentRange מוסיף את "הערות" כשהערה inline מופיעה רק בהמשך הספר (מחוץ לחלון הראשוני)',
    build: () => bloc,
    seed: () => _seed(
      book: book,
      // חלון ראשוני: שורות 0..2 ללא הערות
      content: const [
        'שורה ראשונה',
        'שורה שנייה',
        'שורה שלישית',
      ],
    ),
    act: (bloc) => bloc.add(
      const ApplyBookContentRange(
        bookTitle: 'ספר בדיקה',
        startLine: 100,
        totalLines: 200,
        lines: [
          'שורה רחוקה<sup class="footnote-marker">א</sup>'
              '<i class="footnote">הערה רחוקה</i>',
        ],
      ),
    ),
    expect: () => [
      isA<TextBookLoaded>()
          .having(
            (state) => state.availableCommentators,
            'availableCommentators',
            contains(kNotesCommentatorTitle),
          )
          .having(
            (state) => state.activeCommentators,
            'activeCommentators (auto-selected)',
            const [kNotesCommentatorTitle],
          ),
    ],
  );

  blocTest<TextBookBloc, TextBookState>(
    'ApplyFullBookContent ללא הערות inline לא מוסיף את "הערות"',
    build: () => bloc,
    seed: () => _seed(
      book: book,
      content: const ['preview'],
    ),
    act: (bloc) => bloc.add(
      const ApplyFullBookContent(
        bookTitle: 'ספר בדיקה',
        content: ['שורה רגילה ללא הערות', 'גם זו'],
      ),
    ),
    expect: () => [
      isA<TextBookLoaded>().having(
        (state) => state.availableCommentators,
        'availableCommentators',
        isNot(contains(kNotesCommentatorTitle)),
      ),
    ],
  );

  blocTest<TextBookBloc, TextBookState>(
    'כשיש כבר מפרש פעיל אחר, "הערות" מתווסף ל-available אך לא דורס את activeCommentators',
    build: () => bloc,
    seed: () => _seed(
      book: book,
      content: const ['preview'],
      availableCommentators: const ['רש"י'],
      activeCommentators: const ['רש"י'],
    ),
    act: (bloc) => bloc.add(
      const ApplyFullBookContent(
        bookTitle: 'ספר בדיקה',
        content: [
          'שורה<sup class="footnote-marker">א</sup><i class="footnote">תוכן</i>',
        ],
      ),
    ),
    expect: () => [
      isA<TextBookLoaded>()
          .having(
            (state) => state.availableCommentators,
            'availableCommentators כולל הערות',
            containsAll(<String>['רש"י', kNotesCommentatorTitle]),
          )
          .having(
            (state) => state.activeCommentators,
            'activeCommentators ללא שינוי',
            const ['רש"י'],
          ),
    ],
  );

  blocTest<TextBookBloc, TextBookState>(
    'הערחבה שנייה לא מכפילה את "הערות" אם כבר נוסף',
    build: () => bloc,
    seed: () => _seed(
      book: book,
      content: const [
        'שורה<sup>1</sup><i class="footnote">קיים</i>',
      ],
      availableCommentators: const [kNotesCommentatorTitle],
      activeCommentators: const [kNotesCommentatorTitle],
    ),
    act: (bloc) => bloc.add(
      const ApplyBookContentRange(
        bookTitle: 'ספר בדיקה',
        startLine: 50,
        totalLines: 100,
        lines: [
          'עוד<sup>2</sup><i class="footnote">חדש</i>',
        ],
      ),
    ),
    expect: () => [
      isA<TextBookLoaded>().having(
        (state) => state.availableCommentators
            .where((c) => c == kNotesCommentatorTitle)
            .length,
        'count of הערות in availableCommentators',
        1,
      ),
    ],
  );

  // P1 regression: אחרי שהמשתמש מרוקן את הבחירה במכוון, גלילה/הרחבת תוכן
  // לא צריכה להחזיר את 'הערות' אוטומטית — גם אם 'הערות' עוד לא ב-available.
  blocTest<TextBookBloc, TextBookState>(
    'P1: אחרי UpdateCommentators ריק (clear מפורש), הרחבת תוכן עם הערות מוסיפה ל-available אך לא לבחירה הפעילה',
    build: () => bloc,
    seed: () => _seed(
      book: book,
      content: const ['preview ללא הערות'],
      availableCommentators: const ['רש"י'],
      activeCommentators: const ['רש"י'],
    ),
    act: (bloc) async {
      // המשתמש מרוקן ידנית את הבחירה
      bloc.add(const UpdateCommentators([]));
      await Future<void>.delayed(Duration.zero);
      // עכשיו תוכן עם הערות נכנס דרך הרחבת טווח
      bloc.add(
        const ApplyBookContentRange(
          bookTitle: 'ספר בדיקה',
          startLine: 100,
          totalLines: 200,
          lines: [
            'שורה<sup class="footnote-marker">א</sup>'
                '<i class="footnote">תוכן</i>',
          ],
        ),
      );
    },
    verify: (bloc) {
      final state = bloc.state as TextBookLoaded;
      expect(
        state.availableCommentators,
        contains(kNotesCommentatorTitle),
        reason: 'הערות צריך להתווסף ל-available גם אחרי clear מפורש',
      );
      expect(
        state.activeCommentators,
        isEmpty,
        reason: 'בחירת המשתמש הריקה צריכה להישמר ולא להידרס',
      );
    },
  );

  // P2 efficiency: scanOnly נמדד עקיף — שורה עם הערה ב-state.content
  // (שהוכנסה כ-seed) לא תפעיל גילוי 'הערות' אם הרחבה הבאה היא ללא הערות.
  // שעון: אם היה סורק את כל ה-content, היה מגלה את ההערה בשורה 0.
  blocTest<TextBookBloc, TextBookState>(
    'P2: הרחבת טווח ללא הערות לא סורקת את כל ה-content הקיים (scanOnly)',
    build: () => bloc,
    seed: () => _seed(
      book: book,
      // הערה קיימת מ-seed, אבל לא נסרקה אף פעם דרך handler.
      content: const ['<sup>1</sup><i class="footnote">סוד</i>'],
    ),
    act: (bloc) => bloc.add(
      const ApplyBookContentRange(
        bookTitle: 'ספר בדיקה',
        startLine: 50,
        totalLines: 100,
        lines: ['שורה רחוקה ללא הערות'],
      ),
    ),
    expect: () => [
      isA<TextBookLoaded>().having(
        (state) => state.availableCommentators,
        'הערות לא נוסף כי השורות החדשות נקיות',
        isNot(contains(kNotesCommentatorTitle)),
      ),
    ],
  );

  // P2: ApplyFullBookContent ללא הערות → לאחר מכן הרחבות שמכניסות הערות
  // נמנעות מסריקה (full-scan flag).
  blocTest<TextBookBloc, TextBookState>(
    'P2: אחרי ApplyFullBookContent נקי, הרחבות עתידיות לא סורקות (flag)',
    build: () => bloc,
    seed: () => _seed(
      book: book,
      content: const ['preview'],
    ),
    act: (bloc) async {
      bloc.add(
        const ApplyFullBookContent(
          bookTitle: 'ספר בדיקה',
          content: ['שורה א', 'שורה ב', 'שורה ג'],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      // הערה מוכנסת בהרחבה — אבל full-scan flag חוסם.
      // (במציאות לא צפויה הרחבה כזו אחרי full content, אבל הטסט מוודא
      // את ההתנהגות של ה-flag.)
      bloc.add(
        const ApplyBookContentRange(
          bookTitle: 'ספר בדיקה',
          startLine: 10,
          totalLines: 20,
          lines: ['חדש<sup>1</sup><i class="footnote">תוכן</i>'],
        ),
      );
    },
    skip: 1, // ApplyFullBookContent emit
    expect: () => [
      isA<TextBookLoaded>().having(
        (state) => state.availableCommentators,
        'הערות לא נוסף אחרי שה-full-scan flag נדלק',
        isNot(contains(kNotesCommentatorTitle)),
      ),
    ],
  );

  // P3 (regression): דגלים פר-ספר אסור שידלפו בין ספרים. resetInlineNotesStateForNewBook
  // נקרא ב-_onLoadContent כשהמצב הוא TextBookInitial.
  blocTest<TextBookBloc, TextBookState>(
    'P3a: הדגלים נדלקים אחרי UpdateCommentators + ApplyFullBookContent',
    build: () => bloc,
    seed: () => _seed(book: book, content: const ['preview']),
    act: (bloc) async {
      bloc.add(const UpdateCommentators(['רש"י']));
      await Future<void>.delayed(Duration.zero);
      bloc.add(
        const ApplyFullBookContent(
          bookTitle: 'ספר בדיקה',
          content: ['שורה רגילה'],
        ),
      );
    },
    verify: (bloc) {
      expect(bloc.userTouchedCommentatorsForTesting, isTrue);
      expect(bloc.inlineNotesFullScanDoneForTesting, isTrue);
    },
  );

  blocTest<TextBookBloc, TextBookState>(
    'P3b: resetInlineNotesStateForNewBook מאפס את שני הדגלים (מדמה טעינת ספר חדש)',
    build: () => bloc,
    seed: () => _seed(book: book, content: const ['preview']),
    act: (bloc) async {
      // מדליקים את הדגלים בזרימה רגילה
      bloc.add(const UpdateCommentators(['רש"י']));
      await Future<void>.delayed(Duration.zero);
      bloc.add(
        const ApplyFullBookContent(
          bookTitle: 'ספר בדיקה',
          content: ['שורה רגילה'],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      // איפוס — זה מה ש-_onLoadContent קורא לו בטעינת ספר חדש
      bloc.resetInlineNotesStateForNewBook();
    },
    verify: (bloc) {
      expect(bloc.userTouchedCommentatorsForTesting, isFalse);
      expect(bloc.inlineNotesFullScanDoneForTesting, isFalse);
    },
  );

  // ── בחירה אוטומטית (ברירת מחדל) ושחזור בחירה שמורה ──────────────────────
  group('UpdateCommentators auto/restore guards', () {
    blocTest<TextBookBloc, TextBookState>(
      'בחירת ברירת מחדל (isUserAction:false) מוחלת כשאין מפרשים פעילים',
      build: () => bloc,
      seed: () => _seed(book: book, content: const ['preview']),
      act: (bloc) => bloc.add(
        const UpdateCommentators(['רש"י', 'תוספות'], isUserAction: false),
      ),
      verify: (bloc) {
        expect((bloc.state as TextBookLoaded).activeCommentators, [
          'רש"י',
          'תוספות',
        ]);
        // בחירה אוטומטית אינה מסמנת שהמשתמש נגע בבחירה.
        expect(bloc.userTouchedCommentatorsForTesting, isFalse);
      },
    );

    blocTest<TextBookBloc, TextBookState>(
      'בחירת ברירת מחדל גוברת על אוטו-בחירת הערות (ספר עם הערות)',
      build: () => bloc,
      seed: () => _seed(
        book: book,
        content: const ['preview'],
        activeCommentators: const [kNotesCommentatorTitle],
      ),
      act: (bloc) => bloc.add(
        const UpdateCommentators(['רש"י', 'רד"ק'], isUserAction: false),
      ),
      verify: (bloc) {
        expect((bloc.state as TextBookLoaded).activeCommentators, [
          'רש"י',
          'רד"ק',
        ]);
      },
    );

    blocTest<TextBookBloc, TextBookState>(
      'שחזור בחירה שמורה (isRestore) גובר על בחירה אוטומטית קיימת (כגון הערות)',
      build: () => bloc,
      seed: () => _seed(
        book: book,
        content: const ['preview'],
        activeCommentators: const [kNotesCommentatorTitle],
      ),
      act: (bloc) => bloc.add(
        const UpdateCommentators(
          ['רש"י'],
          isUserAction: false,
          isRestore: true,
        ),
      ),
      verify: (bloc) {
        expect((bloc.state as TextBookLoaded).activeCommentators, ['רש"י']);
      },
    );

    blocTest<TextBookBloc, TextBookState>(
      'שחזור בחירה ריקה מנקה גם בחירה אוטומטית קיימת',
      build: () => bloc,
      seed: () => _seed(
        book: book,
        content: const ['preview'],
        activeCommentators: const [kNotesCommentatorTitle],
      ),
      act: (bloc) => bloc.add(
        const UpdateCommentators([], isUserAction: false, isRestore: true),
      ),
      verify: (bloc) {
        expect((bloc.state as TextBookLoaded).activeCommentators, isEmpty);
      },
    );

    blocTest<TextBookBloc, TextBookState>(
      'אחרי בחירה ידנית, שחזור/אוטומט מאוחרים אינם דורסים',
      build: () => bloc,
      seed: () => _seed(book: book, content: const ['preview']),
      act: (bloc) async {
        bloc.add(const UpdateCommentators(['רש"י'])); // בחירת משתמש
        await Future<void>.delayed(Duration.zero);
        bloc.add(
          const UpdateCommentators(
            ['רמב"ן'],
            isUserAction: false,
            isRestore: true,
          ),
        );
      },
      verify: (bloc) {
        expect((bloc.state as TextBookLoaded).activeCommentators, ['רש"י']);
        expect(bloc.userTouchedCommentatorsForTesting, isTrue);
      },
    );
  });
}
