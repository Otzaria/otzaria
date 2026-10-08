import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/view/widgets/book_source_banner.dart';

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc({bool isOfflineMode = false})
    : super(SettingsState.initial().copyWith(isOfflineMode: isOfflineMode)) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

TextBook _bookWith({
  required String title,
  int categoryId = 1,
  String fileType = 'txt',
  BookSource source = BookSource.official,
}) {
  return TextBook(
    title: title,
    category: null,
    order: 1,
    source: source,
    categoryId: categoryId,
    fileType: fileType,
    filePath: '',
  );
}

Widget _wrap(Widget child, {bool isOfflineMode = false}) {
  return BlocProvider<SettingsBloc>.value(
    value: _FakeSettingsBloc(isOfflineMode: isOfflineMode),
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('parseBannerText', () {
    test('only a real line break splits lines', () {
      final lines = parseBannerText(
        'א\nב'
        r'\n'
        'ג',
      );
      expect(lines.map((l) => l.single.text).toList(), ['א', r'ב\nג']);
      expect(lines.every((l) => l.single.url == null), isTrue);
    });

    test('a [label](url) link splits into text and link segments', () {
      final line = parseBannerText(
        'אפשר ללחוץ [כאן](https://wiki.example.org/wiki/%D7%A2%D7%A5%20%D7%94%D7%93%D7%A8) ולתקן',
      ).single;
      expect(line.map((s) => s.text).toList(), [
        'אפשר ללחוץ ',
        'כאן',
        ' ולתקן',
      ]);
      expect(
        line[1].url.toString(),
        'https://wiki.example.org/wiki/%D7%A2%D7%A5%20%D7%94%D7%93%D7%A8',
      );
      expect(line[0].url, isNull);
      expect(line[2].url, isNull);
    });

    test('the url runs to the first closing parenthesis', () {
      final line = parseBannerText('[x](https://e.org/a)) סוף').single;
      expect(line[0].url.toString(), 'https://e.org/a');
      expect(line[1].text, ') סוף');
    });

    test('a non-web scheme stays as raw text', () {
      final line = parseBannerText('[x](javascript:alert)').single;
      expect(line.single.url, isNull);
      expect(line.single.text, '[x](javascript:alert)');
    });
  });

  group('sameSourceIdentity', () {
    test('true when title/categoryId/fileType/source all match', () {
      final a = _bookWith(title: 'א', categoryId: 1, fileType: 'txt');
      final b = _bookWith(title: 'א', categoryId: 1, fileType: 'txt');
      expect(sameSourceIdentity(a, b), isTrue);
    });

    test('false when categoryId differs despite same title', () {
      final a = _bookWith(title: 'א', categoryId: 1);
      final b = _bookWith(title: 'א', categoryId: 2);
      expect(sameSourceIdentity(a, b), isFalse);
    });

    test('false when source differs', () {
      final a = _bookWith(title: 'א', source: BookSource.official);
      final b = _bookWith(title: 'א', source: BookSource.user);
      expect(sameSourceIdentity(a, b), isFalse);
    });
  });

  group('BookSourceBanner', () {
    const text =
        "באדיבות 'אוצר הספרים'\nאפשר ללחוץ [כאן](https://example.org) ולתקן";

    testWidgets('renders the DB text with a tappable link label', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const BookSourceBanner(text: text)));

      expect(find.textContaining("באדיבות 'אוצר הספרים'"), findsOneWidget);
      expect(find.textContaining('אפשר ללחוץ כאן ולתקן'), findsOneWidget);
      expect(find.textContaining('https://'), findsNothing);
      expect(_linkSpans(tester), hasLength(1));
    });

    testWidgets('the banner is excluded from text selection', (tester) async {
      await tester.pumpWidget(
        _wrap(SelectionArea(child: const BookSourceBanner(text: text))),
      );
      expect(
        find.descendant(
          of: find.byType(BookSourceBanner),
          matching: find.byType(SelectionContainer),
        ),
        findsOneWidget,
      );
      final container = tester.widget<SelectionContainer>(
        find.descendant(
          of: find.byType(BookSourceBanner),
          matching: find.byType(SelectionContainer),
        ),
      );
      expect(container.delegate, isNull);
    });

    testWidgets('omits lines that contain a link when offline', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const BookSourceBanner(text: text), isOfflineMode: true),
      );

      expect(find.textContaining("באדיבות 'אוצר הספרים'"), findsOneWidget);
      expect(find.textContaining('אפשר ללחוץ'), findsNothing);
      expect(_linkSpans(tester), isEmpty);
    });
  });
}

List<TextSpan> _linkSpans(WidgetTester tester) {
  final rich = tester.widget<RichText>(
    find.descendant(
      of: find.byType(BookSourceBanner),
      matching: find.byType(RichText),
    ),
  );
  final spans = <TextSpan>[];
  rich.text.visitChildren((span) {
    if (span is TextSpan && span.recognizer != null) spans.add(span);
    return true;
  });
  return spans;
}
