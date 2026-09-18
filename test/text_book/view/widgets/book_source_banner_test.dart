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
  group('wikiJewishBooksPageUrl', () {
    test('replaces spaces with underscores and url-encodes the title', () {
      expect(
        wikiJewishBooksPageUrl('עץ הדר'),
        equals(
          'https://wiki.jewishbooks.org.il/mediawiki/wiki/%D7%A2%D7%A5_%D7%94%D7%93%D7%A8',
        ),
      );
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
    testWidgets('shows the national library credit text', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const BookSourceBanner(
            kind: BookSourceBannerKind.nationalLibrary,
            bookTitle: 'ספר',
          ),
        ),
      );

      expect(find.text(kNationalLibraryBannerText), findsOneWidget);
      expect(find.text('כאן'), findsNothing);
    });

    testWidgets('shows the wiki jewish books link when online', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const BookSourceBanner(
            kind: BookSourceBannerKind.wikiJewishBooks,
            bookTitle: 'עץ הדר',
          ),
          isOfflineMode: false,
        ),
      );

      expect(find.textContaining(kWikiJewishBooksBannerText), findsOneWidget);
      expect(find.textContaining('אפשר ללחוץ'), findsOneWidget);
      expect(find.textContaining('כאן'), findsOneWidget);
    });

    testWidgets('hides the wiki jewish books link when offline', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const BookSourceBanner(
            kind: BookSourceBannerKind.wikiJewishBooks,
            bookTitle: 'עץ הדר',
          ),
          isOfflineMode: true,
        ),
      );

      expect(find.text(kWikiJewishBooksBannerText), findsOneWidget);
      expect(find.textContaining('אפשר ללחוץ'), findsNothing);
    });
  });
}
