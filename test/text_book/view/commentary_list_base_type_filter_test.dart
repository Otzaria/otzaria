// סינון פאנל המפרשים לפי סוג הקישור (תרגום/מדרש/דיבור המתחיל/פרשנות/ביאור).
// COMMENTARY ו-SUPER_COMMENTARY אינם מקבלים צ׳יפ בכוונה — הם רוב מוחלט של
// הקישורים, וצ׳יפ שכולל כמעט הכל אינו מסנן כלום.
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/widgets/lists/commentators_selection_panel.dart';
import 'package:otzaria/widgets/misc/commentators_filter_button.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    LibraryProviderManager.instance.resetForTesting();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        BookCompositeKey.create(
          title: 'אונקלוס',
          categoryId: 1,
          fileType: 'txt',
        ): _FakeLibraryProvider(),
      },
      providers: [_FakeLibraryProvider()],
    );
  });

  tearDown(() {
    LibraryProviderManager.instance.resetForTesting();
  });

  group('buildCommentaryTypeChipKeys - הצ׳יפים נבנים רק מסוגים קיימים', () {
    test('סוג שאין לו קישורים אינו מקבל צ׳יפ', () {
      final keys = buildCommentaryTypeChipKeys([
        _link(path2: 'אונקלוס.txt', type: LinkTypes.targum),
        _link(path2: 'רש"י.txt', type: LinkTypes.commentary),
      ]);

      expect(keys, [LinkTypes.targum]);
    });

    test('הסדר קבוע לפי commentaryFilterTypes ולא לפי סדר הקישורים', () {
      final keys = buildCommentaryTypeChipKeys([
        _link(path2: 'א.txt', type: LinkTypes.diburHamatchil),
        _link(path2: 'ב.txt', type: LinkTypes.midrash),
        _link(path2: 'ג.txt', type: LinkTypes.targum),
      ]);

      expect(keys, [
        LinkTypes.targum,
        LinkTypes.midrash,
        LinkTypes.diburHamatchil,
      ]);
    });

    test('COMMENTARY אינו מקבל צ׳יפ', () {
      final keys = buildCommentaryTypeChipKeys([
        _link(path2: 'רש"י.txt', type: LinkTypes.commentary),
        _link(path2: 'אונקלוס.txt', type: LinkTypes.targum),
      ]);

      expect(keys, isNot(contains(LinkTypes.commentary)));
    });

    // הוראה מפורשת של מתחזק הפרויקט: אין לגעת ב"סופר מפרש" בשלב זה.
    test('SUPER_COMMENTARY אינו מקבל צ׳יפ', () {
      final keys = buildCommentaryTypeChipKeys([
        _link(path2: 'שפתי חכמים.txt', type: LinkTypes.superCommentary),
        _link(path2: 'אונקלוס.txt', type: LinkTypes.targum),
      ]);

      expect(keys, isNot(contains(LinkTypes.superCommentary)));
      expect(keys, [LinkTypes.targum]);
    });

    test('EXPLICATION ו-ELUCIDATION ממוזגים לצ׳יפ "ביאור" אחד', () {
      final keys = buildCommentaryTypeChipKeys([
        _link(path2: 'א.txt', type: LinkTypes.explication),
        _link(path2: 'ב.txt', type: LinkTypes.elucidation),
      ]);

      expect(keys, [LinkTypes.elucidation]);
      expect(keys.map(LinkTypes.hebrewLabel), ['ביאור']);
    });

    test('התוויות העבריות הנכונות לכל הסוגים', () {
      final keys = buildCommentaryTypeChipKeys([
        _link(path2: 'א.txt', type: LinkTypes.targum),
        _link(path2: 'ב.txt', type: LinkTypes.midrash),
        _link(path2: 'ג.txt', type: LinkTypes.parshanut),
        _link(path2: 'ד.txt', type: LinkTypes.diburHamatchil),
      ]);

      expect(keys.map(LinkTypes.hebrewLabel).toList(), [
        'תרגום',
        'מדרש',
        'פרשנות',
        'דיבור המתחיל',
      ]);
    });

    test('ערך באותיות קטנות מזוהה ואינו מייצר צ׳יפ כפול', () {
      final keys = buildCommentaryTypeChipKeys([
        _link(path2: 'א.txt', type: 'targum'),
        _link(path2: 'ב.txt', type: 'TARGUM'),
      ]);

      expect(keys, [LinkTypes.targum]);
    });
  });

  group('effectiveCommentaryTypes - ריק = הצג הכל', () {
    test('בחירה ריקה נשארת ריקה', () {
      expect(
        effectiveCommentaryTypes(
          selectedTypes: const {},
          availableKeys: const [LinkTypes.targum],
        ),
        isEmpty,
      );
    });

    test('בחירה שאין לה צ׳יפ קיים נחשבת ריקה ואינה מסתירה הכל', () {
      expect(
        effectiveCommentaryTypes(
          selectedTypes: const {LinkTypes.midrash},
          availableKeys: const [LinkTypes.targum],
        ),
        isEmpty,
      );
    });

    test('נשמרים רק המפתחות שקיימים בצ׳יפים', () {
      expect(
        effectiveCommentaryTypes(
          selectedTypes: const {LinkTypes.midrash, LinkTypes.targum},
          availableKeys: const [LinkTypes.targum],
        ),
        {LinkTypes.targum},
      );
    });
  });

  group('getLinksforIndexs - סינון לפי סוג', () {
    final links = [
      _link(path2: 'אונקלוס.txt', type: LinkTypes.targum),
      _link(path2: 'רש"י.txt', type: LinkTypes.commentary),
      _link(path2: 'מדרש רבה.txt', type: LinkTypes.midrash),
    ];
    const commentators = ['אונקלוס', 'רש"י', 'מדרש רבה'];

    test('ריק = כל הסוגים מוצגים', () async {
      final result = await getLinksforIndexs(
        indexes: const [0],
        links: links,
        commentatorsToShow: commentators,
      );

      expect(result.length, 3);
    });

    test('סינון לפי תרגום מציג רק תרגומים', () async {
      final result = await getLinksforIndexs(
        indexes: const [0],
        links: links,
        commentatorsToShow: commentators,
        typesToShow: const {LinkTypes.targum},
      );

      expect(result.map((l) => l.path2), ['אונקלוס.txt']);
    });

    test('בחירת כמה סוגים = איחוד', () async {
      final result = await getLinksforIndexs(
        indexes: const [0],
        links: links,
        commentatorsToShow: commentators,
        typesToShow: const {LinkTypes.targum, LinkTypes.midrash},
      );

      expect(result.map((l) => l.path2).toSet(), {
        'אונקלוס.txt',
        'מדרש רבה.txt',
      });
    });

    test('הסינון לפי סוג פועל יחד עם הסינון לפי שם מפרש', () async {
      final result = await getLinksforIndexs(
        indexes: const [0],
        links: [
          ...links,
          _link(path2: 'יונתן.txt', type: LinkTypes.targum),
        ],
        // "יונתן" מסונן החוצה לפי שם, אף שסוגו נבחר
        commentatorsToShow: const ['אונקלוס', 'רש"י'],
        typesToShow: const {LinkTypes.targum},
      );

      expect(result.map((l) => l.path2), ['אונקלוס.txt']);
    });

    test('EXPLICATION נתפס ע"י בחירת ELUCIDATION (מיזוג קנוני)', () async {
      final result = await getLinksforIndexs(
        indexes: const [0],
        links: [_link(path2: 'ביאור.txt', type: LinkTypes.explication)],
        commentatorsToShow: const ['ביאור'],
        typesToShow: const {LinkTypes.elucidation},
      );

      expect(result.length, 1);
    });
  });

  group('CommentaryListBase - הצגת שורת הצ׳יפים', () {
    testWidgets('אין צ׳יפי סוג בלשונית המפרשים עצמה', (tester) async {
      await _pump(tester, _stateWithTypes(const ['TARGUM', 'MIDRASH']));

      expect(find.byKey(commentatorTypeChipsGroupKey), findsNothing);
      expect(find.widgetWithText(Chip, 'תרגום'), findsNothing);
    });

    testWidgets('שני סוגים ומעלה - הקבוצה מוצגת עם התוויות הנכונות', (
      tester,
    ) async {
      await _pump(tester, _stateWithTypes(const ['TARGUM', 'MIDRASH']));
      await _openFilter(tester);

      expect(find.byKey(commentatorTypeChipsGroupKey), findsOneWidget);
      expect(find.widgetWithText(Chip, 'תרגום'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'מדרש'), findsOneWidget);
    });

    testWidgets('קבוצת הדורות מימין וקבוצת הסוגים משמאל', (tester) async {
      await _pump(tester, _stateWithTypes(const ['TARGUM', 'MIDRASH']));
      await _openFilter(tester);

      final eras = tester.getRect(find.byKey(commentatorEraChipsGroupKey));
      final types = tester.getRect(find.byKey(commentatorTypeChipsGroupKey));
      expect(types.right, lessThanOrEqualTo(eras.left));
      expect(eras.top, types.top);
    });

    testWidgets('קו מפריד בין שתי הקבוצות', (tester) async {
      await _pump(tester, _stateWithTypes(const ['TARGUM', 'MIDRASH']));
      await _openFilter(tester);

      final divider = tester.getRect(
        find.byKey(commentatorChipAxesDividerKey),
      );
      final eras = tester.getRect(find.byKey(commentatorEraChipsGroupKey));
      final types = tester.getRect(find.byKey(commentatorTypeChipsGroupKey));
      expect(divider.left, greaterThanOrEqualTo(types.right));
      expect(divider.right, lessThanOrEqualTo(eras.left));
    });

    testWidgets('סוג יחיד - אין קבוצת סוגים', (tester) async {
      await _pump(tester, _stateWithTypes(const ['TARGUM']));
      await _openFilter(tester);

      expect(find.byKey(commentatorTypeChipsGroupKey), findsNothing);
      expect(find.byKey(commentatorEraChipsGroupKey), findsOneWidget);
    });

    testWidgets('רק COMMENTARY - אין קבוצת סוגים כלל', (tester) async {
      await _pump(
        tester,
        _stateWithTypes(const ['COMMENTARY', 'COMMENTARY']),
      );
      await _openFilter(tester);

      expect(find.byKey(commentatorTypeChipsGroupKey), findsNothing);
    });

    testWidgets('COMMENTARY ו-SUPER_COMMENTARY אינם מקבלים צ׳יפ בתצוגה', (
      tester,
    ) async {
      await _pump(
        tester,
        _stateWithTypes(const [
          'TARGUM',
          'MIDRASH',
          'COMMENTARY',
          'SUPER_COMMENTARY',
        ]),
      );
      await _openFilter(tester);

      expect(find.byKey(commentatorTypeChipsGroupKey), findsOneWidget);
      expect(find.widgetWithText(Chip, 'פירוש'), findsNothing);
      expect(find.widgetWithText(Chip, 'פירוש על פירוש'), findsNothing);
      expect(find.widgetWithText(Chip, 'תרגום'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'מדרש'), findsOneWidget);
    });

    testWidgets('צ׳יפ של מפרש שאינו נבחר אינו מוצג', (tester) async {
      // הקישור מסוג מדרש קיים, אך ספרו אינו ברשימת המפרשים הנבחרים.
      final state = _stateWithTypes(
        const ['TARGUM', 'MIDRASH'],
        activeCommentators: const ['ספר 0'],
      );
      await _pump(tester, state);
      await _openFilter(tester);

      expect(find.byKey(commentatorTypeChipsGroupKey), findsNothing);
    });

    testWidgets('לחיצה על "תרגום" מציגה רק את המפרש מסוג תרגום', (
      tester,
    ) async {
      await _pump(
        tester,
        _stateWithTypes(const ['TARGUM', 'MIDRASH', 'COMMENTARY']),
      );
      await tester.pumpAndSettle();

      // לפני הסינון שלושת המפרשים מוצגים
      expect(find.text('ספר 0'), findsOneWidget);
      expect(find.text('ספר 1'), findsOneWidget);
      expect(find.text('ספר 2'), findsOneWidget);

      await _openFilter(tester);
      await tester.tap(find.widgetWithText(Chip, 'תרגום'));
      await tester.pumpAndSettle();
      await _closeFilter(tester);

      expect(find.text('ספר 0'), findsOneWidget);
      expect(find.text('ספר 1'), findsNothing);
      expect(find.text('ספר 2'), findsNothing);
    });

    testWidgets('בחירת שני צ׳יפים = איחוד, וביטול הבחירה מחזיר הכל', (
      tester,
    ) async {
      await _pump(
        tester,
        _stateWithTypes(const ['TARGUM', 'MIDRASH', 'COMMENTARY']),
      );
      await tester.pumpAndSettle();

      await _openFilter(tester);
      await tester.tap(find.widgetWithText(Chip, 'תרגום'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Chip, 'מדרש'));
      await tester.pumpAndSettle();
      await _closeFilter(tester);

      expect(find.text('ספר 0'), findsOneWidget);
      expect(find.text('ספר 1'), findsOneWidget);
      expect(find.text('ספר 2'), findsNothing);

      // ביטול שתי הבחירות — ריק = הצג הכל
      await _openFilter(tester);
      await tester.tap(find.widgetWithText(Chip, 'תרגום'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Chip, 'מדרש'));
      await tester.pumpAndSettle();
      await _closeFilter(tester);

      expect(find.text('ספר 2'), findsOneWidget);
    });
  });

  group('CommentaryListBase - צ׳יפ יחיד נבחר אינו מסנן בשקט', () {
    testWidgets(
      'מעבר לקטע שבו נותר צ׳יפ אחד נבחר - השורה מוצגת והצ׳יפ מסומן',
      (tester) async {
        // קטע א׳: תרגום + מדרש. המשתמש בוחר "תרגום".
        final bloc = await _pump(
          tester,
          _stateWithTypes(const ['TARGUM', 'MIDRASH']),
        );
        await tester.pumpAndSettle();
        await _openFilter(tester);
        await tester.tap(find.widgetWithText(Chip, 'תרגום'));
        await tester.pumpAndSettle();

        // קטע ב׳: תרגום + פירוש. לפירוש אין צ׳יפ, ולכן נותר צ׳יפ יחיד — הנבחר.
        bloc.emitState(_stateWithTypes(const ['TARGUM', 'COMMENTARY']));
        await tester.pumpAndSettle();

        // הצ׳יפ חייב להישאר מוצג, אחרת אין דרך לבטל את הסינון.
        expect(find.byKey(commentatorTypeChipsGroupKey), findsOneWidget);
        final chip = tester.widget<Chip>(find.widgetWithText(Chip, 'תרגום'));
        expect(
          chip.backgroundColor,
          isNotNull,
          reason: 'הצ׳יפ הנבחר חייב להיראות מסומן',
        );
        // הסינון אכן פעיל — מפרש ה-COMMENTARY מוסתר.
        await _closeFilter(tester);
        expect(find.text('ספר 1'), findsNothing);
      },
    );

    testWidgets('לחיצה על הצ׳יפ היחיד מבטלת את הסינון ומחזירה את כל המפרשים', (
      tester,
    ) async {
      final bloc = await _pump(
        tester,
        _stateWithTypes(const ['TARGUM', 'MIDRASH']),
      );
      await tester.pumpAndSettle();
      await _openFilter(tester);
      await tester.tap(find.widgetWithText(Chip, 'תרגום'));
      await tester.pumpAndSettle();

      bloc.emitState(_stateWithTypes(const ['TARGUM', 'COMMENTARY']));
      await tester.pumpAndSettle();
      await _closeFilter(tester);
      expect(find.text('ספר 1'), findsNothing);

      await _openFilter(tester);
      await tester.tap(find.widgetWithText(Chip, 'תרגום'));
      await tester.pumpAndSettle();
      // בלי בחירה וצ׳יפ יחיד — הקבוצה חוזרת להסתתר.
      expect(find.byKey(commentatorTypeChipsGroupKey), findsNothing);
      await _closeFilter(tester);

      expect(find.text('ספר 0'), findsOneWidget);
      expect(find.text('ספר 1'), findsOneWidget);
    });

    testWidgets('אין בחירה וצ׳יפ יחיד - הקבוצה נשארת מוסתרת', (tester) async {
      await _pump(tester, _stateWithTypes(const ['TARGUM', 'COMMENTARY']));
      await tester.pumpAndSettle();
      await _openFilter(tester);

      expect(find.byKey(commentatorTypeChipsGroupKey), findsNothing);
      await _closeFilter(tester);
      expect(find.text('ספר 0'), findsOneWidget);
      expect(find.text('ספר 1'), findsOneWidget);
    });

    testWidgets('סינון סוג שמרוקן את הרשימה - מוצגת הודעת ריק', (tester) async {
      // אותו ספר מקושר פעמיים: תרגום ומדרש. בוחרים "מדרש".
      final bloc = await _pump(
        tester,
        _stateWithTypes(const ['TARGUM', 'MIDRASH']),
      );
      await tester.pumpAndSettle();
      await _openFilter(tester);
      await tester.tap(find.widgetWithText(Chip, 'מדרש'));
      await tester.pumpAndSettle();
      await _closeFilter(tester);

      // המדרש נותר בקישורי החלון (ולכן הצ׳יפ קיים והבחירה בתוקף), אך בקטע
      // הנוכחי יש תרגום בלבד — הסינון מרוקן את הרשימה.
      final targumOnly = _link(path2: 'ספר 0.txt', type: 'TARGUM');
      final midrashOther = _link(
        path2: 'ספר 1.txt',
        type: 'MIDRASH',
        index1: 2,
      );
      bloc.emitState(
        _stateForLinks(
          links: [targumOnly, midrashOther],
          linksByLine: {
            1: [targumOnly],
            2: [midrashOther],
          },
          commentators: const ['ספר 0', 'ספר 1'],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('לא נמצאו מפרשים מהסוגים שנבחרו'), findsOneWidget);
    });
  });

  group('CommentaryListBase - הצ׳יפים יציבים בדפדוף', () {
    testWidgets('צ׳יפ נשאר בקטע שאין בו קישור מסוגו', (tester) async {
      final targum = _link(path2: 'ספר 0.txt', type: 'TARGUM');
      final midrash = _link(path2: 'ספר 1.txt', type: 'MIDRASH');
      final bloc = await _pump(
        tester,
        _stateForLinks(
          links: [targum, midrash],
          linksByLine: {
            1: [targum, midrash],
          },
          commentators: const ['ספר 0', 'ספר 1'],
        ),
      );
      await tester.pumpAndSettle();
      await _openFilter(tester);
      expect(find.widgetWithText(Chip, 'מדרש'), findsOneWidget);

      // מעבר לקטע שיש בו תרגום בלבד — המדרש עדיין בחלון הקריאה.
      bloc.emitState(_windowState(targum, midrash));
      await tester.pumpAndSettle();

      expect(find.byKey(commentatorTypeChipsGroupKey), findsOneWidget);
      expect(find.widgetWithText(Chip, 'מדרש'), findsOneWidget);
    });

    testWidgets('הבחירה נשמרת בקטע שאין בו קישור מהסוג הנבחר', (tester) async {
      final targum = _link(path2: 'ספר 0.txt', type: 'TARGUM');
      final midrash = _link(path2: 'ספר 1.txt', type: 'MIDRASH');
      final bloc = await _pump(
        tester,
        _stateForLinks(
          links: [targum, midrash],
          linksByLine: {
            1: [targum, midrash],
          },
          commentators: const ['ספר 0', 'ספר 1'],
        ),
      );
      await tester.pumpAndSettle();
      await _openFilter(tester);
      await tester.tap(find.widgetWithText(Chip, 'מדרש'));
      await tester.pumpAndSettle();
      await _closeFilter(tester);
      expect(find.text('ספר 0'), findsNothing);

      bloc.emitState(_windowState(targum, midrash));
      await tester.pumpAndSettle();

      // הסינון נותר פעיל: התרגום אינו מוצג והודעת הריק מסבירה למה.
      expect(find.text('ספר 0'), findsNothing);
      expect(find.text('לא נמצאו מפרשים מהסוגים שנבחרו'), findsOneWidget);
    });

    testWidgets('מפרש שאינו נבחר אינו מקבל צ׳יפ גם מחוץ לקטע', (tester) async {
      final targum = _link(path2: 'ספר 0.txt', type: 'TARGUM');
      final midrash = _link(path2: 'ספר 1.txt', type: 'MIDRASH', index1: 2);
      await _pump(
        tester,
        _stateForLinks(
          links: [targum, midrash],
          linksByLine: {
            1: [targum],
            2: [midrash],
          },
          commentators: const ['ספר 0'],
          availableCommentators: const ['ספר 0', 'ספר 1'],
        ),
      );
      await tester.pumpAndSettle();
      await _openFilter(tester);

      expect(find.widgetWithText(Chip, 'מדרש'), findsNothing);
    });
  });
}

/// מצב שבו [inSection] בקטע המוצג ו-[outOfSection] רק בחלון הקריאה (שורה אחרת).
TextBookLoaded _windowState(Link inSection, Link outOfSection) {
  final other = _link(
    path2: outOfSection.path2,
    type: outOfSection.connectionType,
    index1: 2,
  );
  return _stateForLinks(
    links: [inSection, other],
    linksByLine: {
      1: [inSection],
      2: [other],
    },
    commentators: const ['ספר 0', 'ספר 1'],
  );
}

Future<_TestTextBookBloc> _pump(
  WidgetTester tester,
  TextBookLoaded state,
) async {
  final bloc = _TestTextBookBloc(state);
  addTearDown(() async => bloc.close());
  final settingsBloc = _TestSettingsBloc(SettingsState.initial());
  addTearDown(() async => settingsBloc.close());

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  });

  await tester.pumpWidget(
    MaterialApp(
      // האפליקציה כולה RTL (locale he_IL); בלי זה בדיקות מיקום נמדדות הפוך.
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: bloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: CommentaryListBase(
              openBookCallback: _noopOpenBook,
              fontSize: 18,
              showSearch: true,
              shrinkWrap: false,
              onSelectedCommentatorsOverrideChanged: (_) {},
            ),
          ),
        ),
      ),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return bloc;
}

void _noopOpenBook(_) {}

/// צ׳יפי הסוגים חיים בפאנל "בחירת מפרשים", ולכן כל בדיקה שנוגעת בהם פותחת
/// אותו תחילה.
Future<void> _openFilter(WidgetTester tester) async {
  await tester.tap(find.byType(CommentatorsFilterButton));
  await tester.pumpAndSettle();
}

Future<void> _closeFilter(WidgetTester tester) async {
  await tester.tap(
    find.widgetWithIcon(IconButton, FluentIcons.arrow_left_24_regular),
  );
  await tester.pumpAndSettle();
}

Link _link({required String path2, required String type, int index1 = 1}) =>
    Link(
      heRef: 'בראשית א',
      index1: index1,
      path2: path2,
      index2: 1,
      connectionType: type,
      targetCategoryId: 1,
      targetFileType: 'txt',
    );

/// מצב עם קישור אחד לכל סוג ב-[types], כל אחד מספר נפרד ("ספר 0", "ספר 1"...).
TextBookLoaded _stateWithTypes(
  List<String> types, {
  List<String>? activeCommentators,
}) {
  final links = [
    for (var i = 0; i < types.length; i++)
      _link(path2: 'ספר $i.txt', type: types[i]),
  ];
  final titles = [for (var i = 0; i < types.length; i++) 'ספר $i'];

  return _stateForLinks(
    links: links,
    linksByLine: {1: links},
    commentators: activeCommentators ?? titles,
    availableCommentators: titles,
  );
}

/// מצב עם שליטה מלאה על [links] מול [linksByLine], כדי לדמות מצב שבו קישור
/// עובר את סינון המפרשים אך נחסם בסינון הסוג.
TextBookLoaded _stateForLinks({
  required List<Link> links,
  required Map<int, List<Link>> linksByLine,
  required List<String> commentators,
  List<String>? availableCommentators,
}) {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: commentators,
    commentatorGroups: [
      CommentatorGroup(
        title: 'ראשונים',
        commentators: availableCommentators ?? commentators,
      ),
    ],
    availableCommentators: availableCommentators ?? commentators,
    links: links,
    visibleLinks: const [],
    linksByLine: linksByLine,
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  /// דוחף מצב חדש לווידג'ט, כדי לדמות מעבר לקטע אחר.
  void emitState(TextBookState state) => emit(state);

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

class _FakeLibraryProvider implements LibraryProvider {
  @override
  String get displayName => 'Fake';

  @override
  bool get isInitialized => true;

  @override
  int get priority => 0;

  @override
  String get providerId => 'fake';

  @override
  String get sourceIndicator => 'T';

  @override
  Future<Library> buildLibraryCatalog(
    Map<String, Map<String, dynamic>> metadata,
    String rootPath,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<List<Link>> getAllLinksForBook(
    String title,
    int categoryId,
    String fileType,
  ) async {
    return const [];
  }

  @override
  Future<Set<String>> getAvailableBookTitles() async => {'אונקלוס|1|txt'};

  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    bool preferUserBooks = false,
  }) async {
    return null;
  }

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    bool preferUserBooks = false,
  }) async {
    return const [];
  }

  @override
  Future<String> getLinkContent(Link link) async => 'תוכן לבדיקה';

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async =>
      true;

  @override
  Future<void> initialize() async {}

  @override
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  ) async {
    return const {};
  }
}
