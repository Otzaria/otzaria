import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tools/aramaic_dictionary/aramaic_dictionary_screen.dart';
import 'package:otzaria/tools/aramaic_dictionary/widgets/aramaic_result_card.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/tools/dictionary/widgets/aramaic_dictionary_entry_view.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

class _Settings extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _Settings() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final entries = DictionaryLookupRepository.decodeAramaicIndex(
    File('assets/dictionary.json').readAsStringSync(),
  ).entries;

  Future<void> screen(WidgetTester tester) async {
    final settings = _Settings();
    addTearDown(settings.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SettingsBloc>.value(
          value: settings,
          child: Scaffold(
            body: AramaicDictionaryScreen(
              repository: DictionaryLookupRepository(
                loadAramaicEntries: () async => entries,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final pair in [
    ('מקיז', 'אומנא'),
    ('אם כן', 'א"כ'),
    ('בכחך', 'לאו כל כמינך'),
  ]) {
    testWidgets('חיפוש עברי שומר את ${pair.$2} לפי ${pair.$1}', (tester) async {
      final baselineMatches = entries.where(
        (e) =>
            e.dictionary == AramaicDictionaryEntry.peshitaDictionary &&
            removeVolwels(e.hebrew).contains(pair.$1),
      );
      expect(
        baselineMatches.any((e) => e.aramaic == pair.$2),
        isTrue,
        reason: 'נתוני המקור כוללים את הפירוש העברי',
      );
      await screen(tester);
      await tester.tap(find.text('עברית לארמית'));
      await tester.enterText(find.byType(TextField), pair.$1);
      await tester.pumpAndSettle();
      final cards = tester.widgetList<AramaicResultCard>(
        find.byType(AramaicResultCard),
      );
      expect(cards.any((c) => c.aramaic == pair.$2), isTrue);
    });
  }

  for (final pair in [('אומנא', 'מקיז דם'), ('א"כ', 'אם כן')]) {
    testWidgets('העתקת ערך ${pair.$1} שומרת את הפירוש ${pair.$2}', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final entry = entries.firstWhere((e) => e.aramaic == pair.$1);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AramaicResultCard(
              aramaic: entry.aramaic,
              hebrew: entry.hebrew,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('העתק את הערך'));
      await tester.pump();
      expect(copied, pair.$1);
      await tester.tap(find.byTooltip('העתק את הערך עם התוצאה'));
      await tester.pump();
      expect(copied, allOf(startsWith(pair.$1), contains(pair.$2)));
      await tester.tap(find.byTooltip('העתק פירוש'));
      await tester.pump();
      expect(copied, contains(pair.$2));
      UiSnack.hide();
    });
  }

  testWidgets('פירוש יחיד בסוגריים משמש גם לחיפוש הפוך', (tester) async {
    await screen(tester);
    await tester.enterText(find.byType(TextField), 'א"כ');
    await tester.pumpAndSettle();
    final card = find.byWidgetPredicate(
      (widget) => widget is AramaicResultCard && widget.aramaic == 'א"כ',
    );
    await tester.tap(
      find.descendant(of: card, matching: find.byTooltip('חפש בעברית')).first,
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'אם כן',
    );
    expect(
      tester
          .widgetList<AramaicResultCard>(find.byType(AramaicResultCard))
          .any((card) => card.aramaic == 'א"כ'),
      isTrue,
    );
  });

  testWidgets('החיפוש העברי אינו כולל ביטוי או הרחבה ארמית', (tester) async {
    await screen(tester);
    await tester.tap(find.text('עברית לארמית'));
    for (final pair in [
      ('אי בעית אימא', 'אב"א'),
      ('מן הני', 'מהני'),
      ('אומנא', 'אומנא'),
    ]) {
      await tester.enterText(find.byType(TextField), pair.$1);
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<AramaicResultCard>(find.byType(AramaicResultCard))
            .any((card) => card.aramaic == pair.$2),
        isFalse,
        reason: pair.$1,
      );
    }
  });

  test('פענוח הנכס שומר הסברים עבריים ומפריד את כל מבני ההרחבה', () {
    for (final (key, translation, expansion) in [
      ('אומנא', 'מקיז דם', 'מקיז דם'),
      ('א"כ', 'אם כן', 'אם כן'),
      ('לאו כל כמינך', 'אין בכחך', 'אין בכחך'),
      ('מיפרך קפריך', 'מקשה', 'מקשה'),
      ('תינטריה', 'ותמשיך בכך', 'ותמשיך בכך'),
      ('תניתוה', 'את הברייתא', 'את הברייתא'),
      ('אב"א', 'אם רוצה אתה', 'אי בעית אימא'),
      ('מהני', 'מאלה', 'מן הני'),
    ]) {
      final entry = entries.firstWhere((e) => e.aramaic == key);
      final parsed = AramaicDictionaryEntryPresentation.parse(entry.hebrew);
      final meaning = parsed.meanings.singleWhere(
        (meaning) => removeVolwels(meaning.expansion ?? '') == expansion,
      );
      expect(
        removeVolwels(meaning.hebrewText),
        contains(translation),
        reason: key,
      );
      expect(removeVolwels(meaning.text), contains(expansion), reason: key);
      if (translation != expansion) {
        expect(
          removeVolwels(meaning.hebrewText),
          isNot(contains(expansion)),
          reason: key,
        );
      }
    }
  });

  test('תקרה סופרת מפתחות ושומרת את כל המקורות בסדר הקלט', () async {
    const other = 'מילון שיח ישראל';
    final repository = DictionaryLookupRepository(
      loadAramaicEntries: () async => const [
        AramaicDictionaryEntry(aramaic: 'ליה', hebrew: 'לו'),
        AramaicDictionaryEntry(aramaic: 'א ב ליה', hebrew: 'ארוך'),
        AramaicDictionaryEntry(aramaic: 'בעי ליה', hebrew: 'צריך לו'),
        AramaicDictionaryEntry(aramaic: 'גמר ליה', hebrew: 'למד לו'),
        AramaicDictionaryEntry(
          aramaic: 'בָּעֵי לֵיהּ',
          hebrew: 'רוצה אותו',
          dictionary: other,
        ),
        AramaicDictionaryEntry(
          aramaic: 'ליה',
          hebrew: 'אותו',
          dictionary: other,
        ),
      ],
    );
    await repository.ensureAramaicLoaded();
    final matches = repository.findAramaicMatches(
      'ליה',
      dictionaries: {...repository.aramaicDictionaryNames},
      maxContainingMatches: 1,
    );
    expect(matches.map((e) => e.hebrew), [
      'לו',
      'אותו',
      'צריך לו',
      'רוצה אותו',
    ]);
    expect(
      repository
          .findAramaicMatches('ליה', maxContainingMatches: 1)
          .map((e) => e.hebrew),
      ['לו', 'צריך לו'],
    );
  });

  test('תקרת שמונה ערכים שומרת את כל המקורות של צירוף מוצג', () async {
    final repository = DictionaryLookupRepository(
      loadAramaicEntries: () async => entries,
    );
    await repository.ensureAramaicLoaded();
    final all = {...repository.aramaicDictionaryNames};
    final uncapped = DictionaryLookupRepository.mergeAramaicMatches(
      repository.findAramaicMatches('אימא', dictionaries: all),
    );
    final capped = DictionaryLookupRepository.mergeAramaicMatches(
      repository.findAramaicMatches(
        'אימא',
        dictionaries: all,
        maxContainingMatches: 8,
      ),
    );
    expect(uncapped.length, lessThanOrEqualTo(8));
    final expected = uncapped
        .firstWhere((e) => e.aramaic == 'אי בעית אימא')
        .hebrew;
    expect(
      capped.firstWhere((e) => e.aramaic == 'אי בעית אימא').hebrew,
      expected,
    );
  });

  group('סימוני ויקי גולמיים', () {
    ParsedAramaicMeaning single(String raw) =>
        AramaicDictionaryEntryPresentation.parse(raw).meanings.single;

    void mockClipboard(WidgetTester tester, void Function(String) onCopy) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            onCopy((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
    }

    test('שבירות שורה ורשימות נעשות שורות ונקודות', () {
      const raw =
          'מחלוקות בין אביי לרבא לבהן הלכה כאביי:<BR> * ייאוש שלא מדעת '
          '<BR>* עד זומם למפרע <br/> * לחי העומד מאליו';
      expect(
        single(raw).mainText,
        'מחלוקות בין אביי לרבא לבהן הלכה כאביי:\n'
        '• ייאוש שלא מדעת\n'
        '• עד זומם למפרע\n'
        '• לחי העומד מאליו',
      );
    });

    test('הדגשה בשני הסגנונות נשמרת בתצוגה ונמחקת בהעתקה', () {
      final meaning = single("א **ב** ג '''ד''' ה");
      expect(meaning.mainText, 'א **ב** ג **ד** ה');
      expect(meaning.text, 'א ב ג ד ה');
      expect(meaning.hebrewText, 'א ב ג ד ה');
    });

    test('מפריד הפירושים *** אינו הדגשה, וכוכביות ברווחים נשארות', () {
      final parsed = AramaicDictionaryEntryPresentation.parse(
        'א **ב** *** ג ** ד ** ה',
      );
      expect(parsed.meanings.map((m) => m.text), ['א ב', 'ג ** ד ** ה']);
    });

    test('סימוני הדגשה שבורים נשארים כמות שהם', () {
      expect(single('א ** ב').text, 'א ** ב');
      expect(single('א **ב').text, 'א **ב');
      expect(single('א * ב *ג').mainText, 'א * ב *ג');
      expect(single('****').mainText, '****');
      expect(single("א '''ב").mainText, "א '''ב");
    });

    test('הדגשה שחוצה את מפריד הפירושים אינה מזוהה', () {
      final parsed = AramaicDictionaryEntryPresentation.parse('**א *** ב**');
      expect(parsed.meanings.map((m) => m.mainText), ['**א', 'ב**']);
      expect(parsed.meanings.map((m) => m.text), ['**א', 'ב**']);
    });

    test('הדגשה אינה מונעת זיהוי פירוש חוזר', () {
      final meanings = AramaicDictionaryEntryPresentation.parse(
        '**ארץ**, קרקע *** ארץ',
      ).withoutRepeatedMeanings().meanings;
      expect(meanings.map((m) => m.mainText), ['**ארץ**, קרקע']);
    });

    testWidgets('תצוגת הערך אינה מציגה את סימוני ההדגשה', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AramaicDictionaryEntryView(definition: 'א **ב** ג'),
          ),
        ),
      );
      expect(find.text('א ב ג'), findsOneWidget);
    });

    testWidgets('כרטיס מציג הדגשה ומעתיק בלי סימונים', (tester) async {
      String? copied;
      mockClipboard(tester, (text) => copied = text);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AramaicResultCard(
              aramaic: 'מילה',
              hebrew: 'פתיחה:<BR>* **מודגש** רגיל *** פירוש שני',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final meaning = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((r) => r.text)
          .whereType<TextSpan>()
          .firstWhere((s) => s.toPlainText() == 'פתיחה:\n• מודגש רגיל');
      bool isBold(InlineSpan span) =>
          span is TextSpan &&
          ((span.style?.fontWeight == FontWeight.bold &&
                  span.toPlainText() == 'מודגש') ||
              (span.children?.any(isBold) ?? false));
      expect(isBold(meaning), isTrue);

      await tester.tap(find.byTooltip('העתק את הערך עם התוצאה'));
      await tester.pump();
      expect(copied, 'מילה\n1. פתיחה:\n• מודגש רגיל\n2. פירוש שני');
      UiSnack.hide();
    });

    testWidgets('בחיפוש עברי הכפתור המשולב נמצא בכל שורת פירוש', (
      tester,
    ) async {
      String? copied;
      mockClipboard(tester, (text) => copied = text);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AramaicResultCard(
              aramaic: 'מילה',
              hebrew: 'פירוש ראשון *** פירוש שני',
              query: 'פירוש',
              queryIsAramaic: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final buttons = find.byTooltip('העתק את הערך עם התוצאה');
      expect(buttons, findsNWidgets(2));
      await tester.tap(buttons.last);
      await tester.pump();
      expect(copied, 'מילה\nפירוש שני');
      UiSnack.hide();
    });
  });
}
