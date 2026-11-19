// בדיקות להסתרת כותרת המקור המיותרת בלשונית הפרשנים (issue #896):
// הכותרת מוסתרת רק כשכל מקטעי הקבוצה מאותה שורת מקור והיעד הוא המקום
// הנקרא כעת; מקטע ממקום אחר, קבוצה רב-שורתית ואות-עוגן נשמרים.
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/commentary_title_visibility.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/text_display/models/text_display_layer.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/text_display/models/text_display_slot.dart';
import '../../test_helpers/fake_commentary_library_provider.dart';
import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/stub_text_book_bloc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('groupSharesSingleSource', () {
    Link link(int index1, {int index2 = 1}) => Link(
      heRef: 'מפרש בדיקה, ג ב',
      index1: index1,
      path2: 'מפרש בדיקה.txt',
      index2: index2,
      connectionType: 'commentary',
    );

    test('רשימה ריקה — false', () {
      expect(groupSharesSingleSource(const []), isFalse);
    });

    test('כל הקישורים מאותה שורת מקור — true', () {
      expect(
        groupSharesSingleSource([link(3), link(3, index2: 2)]),
        isTrue,
      );
    });

    test('שורות מקור שונות (כל הפרק / בחירה מרובה) — false', () {
      expect(groupSharesSingleSource([link(3), link(4)]), isFalse);
    });
  });

  group('commentaryTitleMatchesReadingLocation', () {
    test('יעד באותו מקום כמו שורת המקור — תואם', () {
      expect(
        commentaryTitleMatchesReadingLocation(
          displayTitle: 'רש"י על בכורות, ג ב',
          targetBookTitle: 'רש"י על בכורות',
          sourceBookTitle: 'בכורות',
          sourceRef: 'ג ב',
        ),
        isTrue,
      );
    });

    test('כתובת מקור שכוללת את שם הספר — תואם', () {
      expect(
        commentaryTitleMatchesReadingLocation(
          displayTitle: 'רש"י על בכורות, ג ב',
          targetBookTitle: 'רש"י על בכורות',
          sourceBookTitle: 'בכורות',
          sourceRef: 'בכורות, ג ב',
        ),
        isTrue,
      );
    });

    test('יעד במקום אחר (כמו הפניה לסימן אחר) — לא תואם', () {
      expect(
        commentaryTitleMatchesReadingLocation(
          displayTitle: 'מגן אברהם, סימן ב',
          targetBookTitle: 'מגן אברהם',
          sourceBookTitle: 'שולחן ערוך אורח חיים',
          sourceRef: 'סימן א',
        ),
        isFalse,
      );
    });

    test('קישור-טווח (סיומת "–") — לא תואם', () {
      expect(
        commentaryTitleMatchesReadingLocation(
          displayTitle: 'רש"י על בכורות, ג ב–ג',
          targetBookTitle: 'רש"י על בכורות',
          sourceBookTitle: 'בכורות',
          sourceRef: 'ג ב',
        ),
        isFalse,
      );
    });

    test('כותרת שאינה מתחילה בשם ספר היעד — לא תואם (הצג, בטוח)', () {
      expect(
        commentaryTitleMatchesReadingLocation(
          displayTitle: 'תוספות בכורות, ג ב',
          targetBookTitle: 'רש"י על בכורות',
          sourceBookTitle: 'בכורות',
          sourceRef: 'ג ב',
        ),
        isFalse,
      );
    });

    test('כותרת ללא כתובת (שם הספר בלבד) — לא תואם', () {
      expect(
        commentaryTitleMatchesReadingLocation(
          displayTitle: 'רש"י על בכורות',
          targetBookTitle: 'רש"י על בכורות',
          sourceBookTitle: 'בכורות',
          sourceRef: 'ג ב',
        ),
        isFalse,
      );
    });

    test('הבדלי גרשיים וניקוד אינם מפרים התאמה', () {
      expect(
        commentaryTitleMatchesReadingLocation(
          displayTitle: 'רש״י על בכורות, ג ב',
          targetBookTitle: 'רש"י על בכורות',
          sourceBookTitle: 'בכורות',
          sourceRef: 'ג ב',
        ),
        isTrue,
      );
    });
  });

  group('referenceTokens', () {
    // המימוש הקודם (שרשרת RegExp-ים), שהמעבר היחיד חייב להחזיר את הפלט שלו.
    List<String> regexTokens(String reference) => reference
        .replaceAll(RegExp(r'\p{Mn}', unicode: true), '')
        .replaceAll(RegExp('''['"״׳’”“`]'''), '')
        .replaceAll(RegExp(r'[-–־,.():]'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();

    test('זהה ל-RegExp-ים בכל תו, בניקוד, בגרשיים, ברווחים וב-surrogate', () {
      final alphabet = [
        ...'אבגשת az09'.codeUnits,
        0x0591, 0x05B0, 0x05B4, 0x05BC, 0x05BD, 0x05C7, 0x0301, // סימני Mn
        0x05BE, 0x05C3, 0x05F3, 0x05F4, 0x22, 0x27, 0x60, 0x2019, 0x201C,
        0x201D, 0x2D, 0x2013, 0x2C, 0x2E, 0x28, 0x29, 0x3A, 0x3B,
        0x09, 0x0A, 0xA0, 0x2009, 0x200B, 0x202F, 0x3000, 0xFEFF,
        0xD834, 0xDD67, 0xD83D, 0xDE00, // U+1D167 (Mn) ו-U+1F600 בחלקים
      ];
      final random = Random(896);
      final inputs = [
        for (var c = 0; c <= 0xFFFF; c++) 'א${String.fromCharCode(c)}ב',
        for (final c in [0x1D167, 0x1E8D0, 0x1F600, 0x10000])
          'א${String.fromCharCode(c)}ב',
        for (var n = 0; n < 20000; n++)
          String.fromCharCodes([
            for (var i = random.nextInt(24); i > 0; i--)
              alphabet[random.nextInt(alphabet.length)],
          ]),
      ];
      final mismatches = [
        for (final input in inputs)
          if (!listEquals(referenceTokens(input), regexTokens(input)))
            input.codeUnits,
      ];
      expect(mismatches, isEmpty);
    });
  });

  group('CommentaryListBase - הסתרת כותרת מקטע', () {
    setUpAll(() async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
    });

    late _TestSettingsBloc settingsBloc;

    setUp(() {
      LibraryProviderManager.instance.resetForTesting();
      LibraryProviderManager.instance.seedMappingsForTesting(
        mapping: {
          BookCompositeKey.create(
            title: 'מפרש בדיקה',
            categoryId: 1,
            fileType: 'txt',
          ): FakeCommentaryLibraryProvider(),
        },
        providers: [FakeCommentaryLibraryProvider()],
      );
      settingsBloc = _TestSettingsBloc(SettingsState.initial());
    });

    tearDown(() async {
      await settingsBloc.close();
      LibraryProviderManager.instance.resetForTesting();
    });

    testWidgets('יעד במקום הנקרא — הכותרת מוסתרת והתוכן מוצג', (tester) async {
      final link = _link(heRef: 'מפרש בדיקה, ג ב', index1: 1, index2: 1);
      final bloc = StubTextBookBloc(_loadedState(links: [link]));
      addTearDown(() async => bloc.close());

      await _pump(tester, textBookBloc: bloc, settingsBloc: settingsBloc);

      expect(find.text(_kFakeContent), findsOneWidget);
      expect(find.text('מפרש בדיקה, ג ב'), findsNothing);
    });

    testWidgets('יעד במקום אחר — הכותרת מוצגת', (tester) async {
      final link = _link(heRef: 'מפרש בדיקה, סימן ב', index1: 1, index2: 2);
      final bloc = StubTextBookBloc(_loadedState(links: [link]));
      addTearDown(() async => bloc.close());

      await _pump(tester, textBookBloc: bloc, settingsBloc: settingsBloc);

      expect(find.text('מפרש בדיקה, סימן ב'), findsOneWidget);
    });

    testWidgets('קבוצה מכמה שורות מקור — הכותרות מוצגות', (tester) async {
      final links = [
        _link(heRef: 'מפרש בדיקה, ג ב', index1: 1, index2: 3),
        _link(heRef: 'מפרש בדיקה, ד א', index1: 2, index2: 4),
      ];
      final bloc = StubTextBookBloc(
        _loadedState(
          links: links,
          content: const ['שורה א', 'שורה ב'],
          visibleIndices: const [0, 1],
        ),
      );
      addTearDown(() async => bloc.close());

      await _pump(tester, textBookBloc: bloc, settingsBloc: settingsBloc);

      expect(find.text('מפרש בדיקה, ג ב'), findsOneWidget);
      expect(find.text('מפרש בדיקה, ד א'), findsOneWidget);
    });

    testWidgets('עוגן-מילה עם כותרת מוסתרת — אות הסימון נשארת', (tester) async {
      final link = _link(
        heRef: 'מפרש בדיקה, ג ב',
        index1: 1,
        index2: 5,
        anchorStart: 0,
        anchorLabel: 'א',
      );
      final bloc = StubTextBookBloc(_loadedState(links: [link]));
      addTearDown(() async => bloc.close());

      await _pump(tester, textBookBloc: bloc, settingsBloc: settingsBloc);

      // הסוגריים משתנים לפי וריאנט המפרש; הציפייה היא האות בכל אחד מהם בלבד.
      final marker = RegExp(r'^[(\[{]א[)\]}]$');
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && marker.hasMatch(w.data ?? ''),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('מפרש בדיקה, ג ב'), findsNothing);
    });

    testWidgets(
      'ציוני מפרשים כבויים בגוף — אות הסימון אינה נשארת לבד (issue #3599)',
      (tester) async {
        final link = _link(
          heRef: 'מפרש בדיקה, ג ב',
          index1: 1,
          index2: 5,
          anchorStart: 0,
          anchorLabel: 'א',
        );
        final state = _withBodyMarkersHidden(_loadedState(links: [link]));
        final bloc = StubTextBookBloc(state);
        addTearDown(() async => bloc.close());

        await _pump(tester, textBookBloc: bloc, settingsBloc: settingsBloc);

        expect(find.text(_kFakeContent), findsOneWidget);
        expect(_markerText(), findsNothing);
        expect(find.textContaining('מפרש בדיקה, ג ב'), findsNothing);
      },
    );

    testWidgets(
      'ציוני מפרשים כבויים בגוף — הכותרת מוצגת בלי אות הסימון (issue #3599)',
      (tester) async {
        final link = _link(
          heRef: 'מפרש בדיקה, סימן ב',
          index1: 1,
          index2: 2,
          anchorStart: 0,
          anchorLabel: 'א',
        );
        final state = _withBodyMarkersHidden(_loadedState(links: [link]));
        final bloc = StubTextBookBloc(state);
        addTearDown(() async => bloc.close());

        await _pump(tester, textBookBloc: bloc, settingsBloc: settingsBloc);

        expect(find.text('מפרש בדיקה, סימן ב'), findsOneWidget);
        expect(_markerText(), findsNothing);
      },
    );

    testWidgets('כיבוי ציוני המפרשים בגוף מסיר את אות הסימון מהחלונית הפתוחה '
        '(issue #3599)', (tester) async {
      final link = _link(
        heRef: 'מפרש בדיקה, סימן ב',
        index1: 1,
        index2: 2,
        anchorStart: 0,
        anchorLabel: 'א',
      );
      final shown = _loadedState(links: [link]);
      final bloc = EmittingStubTextBookBloc(shown);
      addTearDown(() async => bloc.close());

      await _pump(tester, textBookBloc: bloc, settingsBloc: settingsBloc);
      expect(_markerText(), findsOneWidget);

      bloc.emitState(_withBodyMarkersHidden(shown));
      await tester.pumpAndSettle();

      expect(_markerText(), findsNothing);
      expect(find.text('מפרש בדיקה, סימן ב'), findsOneWidget);

      bloc.emitState(shown);
      await tester.pumpAndSettle();

      expect(_markerText(), findsOneWidget);
    });
  });

  group('CommentaryListBase - כותרת שחוזרת על הקודמת (#4616)', () {
    setUpAll(() async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
    });

    late _TestSettingsBloc settingsBloc;

    setUp(() {
      LibraryProviderManager.instance.resetForTesting();
      LibraryProviderManager.instance.seedMappingsForTesting(
        mapping: {
          BookCompositeKey.create(
            title: 'מפרש בדיקה',
            categoryId: 1,
            fileType: 'txt',
          ): FakeCommentaryLibraryProvider(),
        },
        providers: [FakeCommentaryLibraryProvider()],
      );
      settingsBloc = _TestSettingsBloc(SettingsState.initial());
    });

    tearDown(() async {
      await settingsBloc.close();
      LibraryProviderManager.instance.resetForTesting();
    });

    Future<void> pumpLinks(WidgetTester tester, List<Link> links) async {
      final bloc = StubTextBookBloc(_loadedState(links: links));
      addTearDown(() async => bloc.close());
      await _pump(tester, textBookBloc: bloc, settingsBloc: settingsBloc);
    }

    testWidgets('כותרת זהה לקודמת — מוצגת פעם אחת', (tester) async {
      await pumpLinks(tester, [
        _link(heRef: 'מפרש בדיקה, סימן ב', index1: 1, index2: 1),
        _link(heRef: 'מפרש בדיקה, סימן ב', index1: 1, index2: 2),
      ]);

      expect(find.text(_kFakeContent), findsNWidgets(2));
      expect(find.text('מפרש בדיקה, סימן ב'), findsOneWidget);
    });

    testWidgets('כותרות שונות — שתיהן מוצגות', (tester) async {
      await pumpLinks(tester, [
        _link(heRef: 'מפרש בדיקה, סימן ב', index1: 1, index2: 1),
        _link(heRef: 'מפרש בדיקה, סימן ג', index1: 1, index2: 2),
      ]);

      expect(find.text('מפרש בדיקה, סימן ב'), findsOneWidget);
      expect(find.text('מפרש בדיקה, סימן ג'), findsOneWidget);
    });

    testWidgets('כותרת חוזרת עם עוגן-מילה — אות הסימון נשארת', (tester) async {
      await pumpLinks(tester, [
        _link(heRef: 'מפרש בדיקה, סימן ב', index1: 1, index2: 1),
        _link(
          heRef: 'מפרש בדיקה, סימן ב',
          index1: 1,
          index2: 2,
          anchorStart: 0,
          anchorLabel: 'א',
        ),
      ]);

      final marker = RegExp(r'^[(\[{]א[)\]}]$');
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && marker.hasMatch(w.data ?? ''),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('מפרש בדיקה, סימן ב'), findsOneWidget);
    });
  });

  group('CommentaryListBase - רווח בין מקטעים (#4963)', () {
    setUpAll(() async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
    });

    late _TestSettingsBloc settingsBloc;

    setUp(() {
      LibraryProviderManager.instance.resetForTesting();
      LibraryProviderManager.instance.seedMappingsForTesting(
        mapping: {
          BookCompositeKey.create(
            title: 'מפרש בדיקה',
            categoryId: 1,
            fileType: 'txt',
          ): FakeCommentaryLibraryProvider(),
        },
        providers: [FakeCommentaryLibraryProvider()],
      );
      settingsBloc = _TestSettingsBloc(SettingsState.initial());
    });

    tearDown(() async {
      await settingsBloc.close();
      LibraryProviderManager.instance.resetForTesting();
    });

    /// המרחק האנכי בין סוף תוכן המקטע הראשון לתחילת תוכן השני.
    Future<double> contentGap(WidgetTester tester, List<Link> links) async {
      final bloc = StubTextBookBloc(_loadedState(links: links));
      addTearDown(() async => bloc.close());
      await _pump(tester, textBookBloc: bloc, settingsBloc: settingsBloc);
      final contents = find.text(_kFakeContent);
      expect(contents, findsNWidgets(2));
      return tester.getTopLeft(contents.at(1)).dy -
          tester.getBottomLeft(contents.at(0)).dy;
    }

    testWidgets('כותרת מוסתרת — 8 פיקסלים בין המקטעים', (tester) async {
      // שני המקטעים מצביעים על המקום הנקרא, ולכן כותרותיהם מוסתרות (#896).
      final gap = await contentGap(tester, [
        _link(heRef: 'מפרש בדיקה, ג ב', index1: 1, index2: 1),
        _link(heRef: 'מפרש בדיקה, ג ב', index1: 1, index2: 2),
      ]);

      expect(gap, 8.0);
    });

    testWidgets('כותרת מוצגת — הרווח הקודם סביב הכותרת נשמר', (tester) async {
      final gap = await contentGap(tester, [
        _link(heRef: 'מפרש בדיקה, סימן ב', index1: 1, index2: 1),
        _link(heRef: 'מפרש בדיקה, סימן ג', index1: 1, index2: 2),
      ]);
      final title = find.text('מפרש בדיקה, סימן ג');

      expect(gap, greaterThan(8.0));
      expect(
        tester.getTopLeft(title).dy -
            tester.getBottomLeft(find.text(_kFakeContent).first).dy,
        8.0 + 8.0,
      );
      expect(
        tester.getTopLeft(find.text(_kFakeContent).at(1)).dy -
            tester.getBottomLeft(title).dy,
        4.0,
      );
    });
  });
}

const _kFakeContent = 'זהו פירוש לבדיקה עם טקסט שניתן לבחור';

Link _link({
  required String heRef,
  required int index1,
  required int index2,
  int? anchorStart,
  String? anchorLabel,
}) {
  return Link(
    heRef: heRef,
    index1: index1,
    path2: 'מפרש בדיקה.txt',
    index2: index2,
    connectionType: 'commentary',
    targetCategoryId: 1,
    targetFileType: 'txt',
    anchorStart: anchorStart,
    anchorLabel: anchorLabel,
  );
}

/// ציוני המפרשים כבויים בגוף הספר (כמו בכפתור התצוגה של הכרטיסייה).
TextBookLoaded _withBodyMarkersHidden(TextBookLoaded state) {
  final hidden = state.copyWith(
    displayOverrides: TextDisplayLayer({
      TextDisplaySlot.root: const TextDisplayPatch(
        anchorMarkers: MarkVisibility.hide,
      ),
    }),
  );
  expect(hidden.bodyDisplayProfile.showAnchorMarkers, isFalse);
  return hidden;
}

/// אות הסימון א בכל אחד מסוגרי הווריאנטים, לבד או לפני כותרת.
Finder _markerText() => find.byWidgetPredicate(
  (w) => w is Text && RegExp(r'[(\[{]א[)\]}]').hasMatch(w.data ?? ''),
);

TextBookLoaded _loadedState({
  required List<Link> links,
  List<String> content = const ['שורה א'],
  List<int> visibleIndices = const [0],
}) {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: content,
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const ['מפרש בדיקה'],
    commentatorGroups: const [],
    availableCommentators: const ['מפרש בדיקה'],
    links: links,
    visibleLinks: const [],
    linksByLine: {
      for (final index1 in links.map((link) => link.index1).toSet())
        index1: [
          for (final link in links)
            if (link.index1 == index1) link,
        ],
    },
    // הכתובות של שורות המקור: שורה 1 = "ג ב", שורה 2 = "ד א".
    tableOfContents: [
      TocEntry(text: 'ג ב', index: 0),
      TocEntry(text: 'ד א', index: 1),
    ],
    removeNikud: false,
    visibleIndices: visibleIndices,
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required TextBookBloc textBookBloc,
  required SettingsBloc settingsBloc,
}) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  });

  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: textBookBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
        ],
        child: Scaffold(
          body: CommentaryListBase(
            openBookCallback: (_) {},
            fontSize: 18,
            showSearch: true,
            shrinkWrap: false,
          ),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
