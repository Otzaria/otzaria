import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/tools/dictionary/widgets/laaz_commentary_subblock.dart';
import '../../helpers/memory_settings_cache.dart';

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Link _link({
  required String path2,
  int index2 = 15,
  String connectionType = 'COMMENTARY',
}) {
  return Link(
    heRef: 'ref',
    index1: 1,
    path2: path2,
    index2: index2,
    connectionType: connectionType,
  );
}

LaazDictionaryEntry _entry({
  required int sourceLineIndex,
  String laazHebrew = 'פילטרי"ש',
  String laazLatin = 'filtres',
  String meaning = 'לבדים',
  String sourceReference = 'בבא קמא ה,א',
  String? note,
  String? english,
}) {
  return LaazDictionaryEntry(
    entryNumber: '$sourceLineIndex',
    sourceReference: sourceReference,
    lemma: 'כרתי',
    laazHebrew: laazHebrew,
    laazLatin: laazLatin,
    meaning: meaning,
    note: note,
    english: english,
    sourceLineIndex: sourceLineIndex,
  );
}

Future<DictionaryLookupRepository> _repositoryWith({
  required List<LaazDictionaryEntry> entries,
  required List<Link> links,
}) async {
  final repository = DictionaryLookupRepository(
    loadLaazEntries: () async => entries,
    loadLaazLinks: () async => links,
  );
  await repository.ensureLaazLinksLoaded();
  return repository;
}

Widget _wrap(Widget child) => MaterialApp(
  home: BlocProvider<SettingsBloc>.value(
    value: _FakeSettingsBloc(),
    child: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

/// אוסף את כל טקסט ה-RichText/Text המרונדר, לבדיקת נוכחות/היעדר מחרוזות.
String _renderedText(WidgetTester tester) {
  final buffer = StringBuffer();
  for (final element in find.byType(RichText).evaluate()) {
    final richText = element.widget as RichText;
    buffer.write(richText.text.toPlainText());
    buffer.write('\n');
  }
  return buffer.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  testWidgets('מציג רק שם-לעז + פירוש תחת קישור רש"י', (tester) async {
    final repository = await _repositoryWith(
      entries: [
        _entry(
          sourceLineIndex: 1,
          laazHebrew: 'פילטרי"ש',
          laazLatin: 'filtres',
          meaning: 'לבדים',
          sourceReference: 'בבא קמא ה,א',
          english: 'clothing',
        ),
      ],
      links: [_link(path2: 'רש"י על בבא קמא', index2: 15)],
    );

    await tester.pumpWidget(
      _wrap(
        LaazCommentarySubBlock(
          link: _link(path2: 'רש"י על בבא קמא', index2: 15),
          repository: repository,
        ),
      ),
    );
    await tester.pump();

    final text = _renderedText(tester);
    // מוצג: שם הלעז והפירוש העברי.
    expect(text, contains('פילטרי"ש'));
    expect(text, contains('לבדים'));
    // מוסתר: לטינית, אנגלית ומיקום המקור.
    expect(text, isNot(contains('filtres')));
    expect(text, isNot(contains('clothing')));
    expect(text, isNot(contains('בבא קמא')));
    expect(text, isNot(contains('רש"י בבא')));
  });

  testWidgets('מציג עבור כותרת רש"י חשופה (בבלי), לא רק "רש"י על"', (
    tester,
  ) async {
    final repository = await _repositoryWith(
      entries: [_entry(sourceLineIndex: 1, laazHebrew: 'פילטרי"ש')],
      links: [_link(path2: 'רש"י', index2: 15)],
    );

    await tester.pumpWidget(
      _wrap(
        LaazCommentarySubBlock(
          link: _link(path2: 'רש"י', index2: 15),
          repository: repository,
        ),
      ),
    );
    await tester.pump();

    expect(_renderedText(tester), contains('פילטרי"ש'));
  });

  test('isRashiTitle מכסה חשוף ו"על", ודוחה מפרשים אחרים', () {
    expect(isRashiTitle('רש"י'), isTrue);
    expect(isRashiTitle('רש"י על שבת'), isTrue);
    expect(isRashiTitle('רש"י על בראשית'), isTrue);
    expect(isRashiTitle('תוספות'), isFalse);
    expect(isRashiTitle('רמב"ן'), isFalse);
    expect(isRashiTitle('רשב"ם על בבא בתרא'), isFalse);
  });

  testWidgets(
    'מסלול .forLine ומסלול ה-Link פותרים אותם ערכים לאותה שורת רש"י',
    (
      tester,
    ) async {
      const rashiTitle = 'רש"י על שבת';
      final repository = await _repositoryWith(
        entries: [_entry(sourceLineIndex: 1, laazHebrew: 'פילטרי"ש')],
        links: [_link(path2: rashiTitle, index2: 15)],
      );

      // מסלול ה-Link: הכותרת נגזרת מ-path2 של הקישור.
      await tester.pumpWidget(
        _wrap(
          LaazCommentarySubBlock(
            link: _link(path2: rashiTitle, index2: 15),
            repository: repository,
          ),
        ),
      );
      await tester.pump();
      expect(_renderedText(tester), contains('פילטרי"ש'));

      // מסלול הטור (.forLine): אותה כותרת בדיוק כפרמטר ישיר.
      await tester.pumpWidget(
        _wrap(
          LaazCommentarySubBlock.forLine(
            rashiBookTitle: rashiTitle,
            rashiLineIndex: 15,
            repository: repository,
          ),
        ),
      );
      await tester.pump();
      expect(_renderedText(tester), contains('פילטרי"ש'));
    },
  );

  testWidgets('נעדר עבור קישור מפרש שאינו רש"י', (tester) async {
    final repository = await _repositoryWith(
      entries: [_entry(sourceLineIndex: 1)],
      links: [_link(path2: 'רש"י על בראשית', index2: 15)],
    );

    await tester.pumpWidget(
      _wrap(
        LaazCommentarySubBlock(
          link: _link(path2: 'אבן עזרא על בראשית', index2: 15),
          repository: repository,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Container), findsNothing);
  });

  testWidgets('נעדר עבור קישור רש"י ללא לעז לשורה', (tester) async {
    final repository = await _repositoryWith(
      entries: [_entry(sourceLineIndex: 1)],
      links: [_link(path2: 'רש"י על בראשית', index2: 15)],
    );

    await tester.pumpWidget(
      _wrap(
        LaazCommentarySubBlock(
          link: _link(path2: 'רש"י על בראשית', index2: 999),
          repository: repository,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Container), findsNothing);
  });

  testWidgets('מציג רשימת ערכים מרובים, שורה לכל ערך', (tester) async {
    final repository = await _repositoryWith(
      entries: [
        _entry(sourceLineIndex: 1, laazHebrew: 'ראשון', meaning: 'פירוש-א'),
        _entry(sourceLineIndex: 2, laazHebrew: 'שני', meaning: 'פירוש-ב'),
      ],
      links: [
        _link(path2: 'רש"י על בראשית', index2: 15),
        Link(
          heRef: 'ref',
          index1: 2,
          path2: 'רש"י על בראשית',
          index2: 15,
          connectionType: 'COMMENTARY',
        ),
      ],
    );

    await tester.pumpWidget(
      _wrap(
        LaazCommentarySubBlock(
          link: _link(path2: 'רש"י על בראשית', index2: 15),
          repository: repository,
        ),
      ),
    );
    await tester.pump();

    final text = _renderedText(tester);
    expect(text, contains('ראשון'));
    expect(text, contains('פירוש-א'));
    expect(text, contains('שני'));
    expect(text, contains('פירוש-ב'));
  });

  testWidgets('פירוש ריק => שם הלעז לבד, בלי fallback להערה/אנגלית', (
    tester,
  ) async {
    final repository = await _repositoryWith(
      entries: [
        _entry(
          sourceLineIndex: 1,
          laazHebrew: 'קלוני"ש',
          meaning: '',
          note: 'הערת עורך',
          english: 'columns',
        ),
      ],
      links: [_link(path2: 'רש"י על בראשית', index2: 15)],
    );

    await tester.pumpWidget(
      _wrap(
        LaazCommentarySubBlock(
          link: _link(path2: 'רש"י על בראשית', index2: 15),
          repository: repository,
        ),
      ),
    );
    await tester.pump();

    final text = _renderedText(tester);
    expect(text, contains('קלוני"ש'));
    // אין fallback: לא הערה ולא אנגלית בתצוגה הראשית.
    expect(text, isNot(contains('הערת עורך')));
    expect(text, isNot(contains('columns')));
  });

  group('LaazCommentarySubBlock.forLine (ללא Link)', () {
    testWidgets('מציג שם-לעז + פירוש לפי כותרת רש"י ומספר שורה', (
      tester,
    ) async {
      final repository = await _repositoryWith(
        entries: [
          _entry(sourceLineIndex: 1, laazHebrew: 'פילטרי"ש', meaning: 'לבדים'),
        ],
        links: [_link(path2: 'רש"י על שבת', index2: 15)],
      );

      await tester.pumpWidget(
        _wrap(
          LaazCommentarySubBlock.forLine(
            rashiBookTitle: 'רש"י על שבת',
            rashiLineIndex: 15,
            repository: repository,
          ),
        ),
      );
      await tester.pump();

      final text = _renderedText(tester);
      expect(text, contains('פילטרי"ש'));
      expect(text, contains('לבדים'));
    });

    testWidgets('נעדר עבור כותרת שאינה רש"י', (tester) async {
      final repository = await _repositoryWith(
        entries: [_entry(sourceLineIndex: 1)],
        links: [_link(path2: 'רש"י על שבת', index2: 15)],
      );

      await tester.pumpWidget(
        _wrap(
          LaazCommentarySubBlock.forLine(
            rashiBookTitle: 'תוספות על שבת',
            rashiLineIndex: 15,
            repository: repository,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Container), findsNothing);
    });

    testWidgets('נעדר עבור שורה ללא לעז', (tester) async {
      final repository = await _repositoryWith(
        entries: [_entry(sourceLineIndex: 1)],
        links: [_link(path2: 'רש"י על שבת', index2: 15)],
      );

      await tester.pumpWidget(
        _wrap(
          LaazCommentarySubBlock.forLine(
            rashiBookTitle: 'רש"י על שבת',
            rashiLineIndex: 999,
            repository: repository,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Container), findsNothing);
    });

    testWidgets('פירוש ריק => שם הלעז לבד', (tester) async {
      final repository = await _repositoryWith(
        entries: [
          _entry(sourceLineIndex: 1, laazHebrew: 'קלוני"ש', meaning: ''),
        ],
        links: [_link(path2: 'רש"י על שבת', index2: 15)],
      );

      await tester.pumpWidget(
        _wrap(
          LaazCommentarySubBlock.forLine(
            rashiBookTitle: 'רש"י על שבת',
            rashiLineIndex: 15,
            repository: repository,
          ),
        ),
      );
      await tester.pump();

      final text = _renderedText(tester);
      expect(text, contains('קלוני"ש'));
      expect(text, isNot(contains('לבדים')));
    });
  });
}
