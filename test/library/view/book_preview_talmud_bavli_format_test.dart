import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/book_preview_panel.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';

import '../../helpers/memory_settings_cache.dart';

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc() : super(SettingsState.initial());
}

Category _category(String title, {Category? parent}) {
  final category = Category(
    title: title,
    description: '',
    shortDescription: '',
    order: 0,
    subCategories: [],
    books: [],
    parent: parent,
  );
  parent?.subCategories.add(category);
  return category;
}

/// ספרייה עם מסכת ברכות: מהדורת טקסט תחת סדר זרעים, ואופציונלית PDF נלווה
/// בנתיב שאינו קיים — כך שענף ה-PDF בתצוגה המקדימה מזוהה לפי 'הספר איננו קיים'.
({Library library, TextBook text}) _buildLibrary({bool withPdf = true}) {
  final bavliRoot = _category('תלמוד בבלי');
  final seder = _category('סדר זרעים', parent: bavliRoot);
  final text = TextBook(title: 'ברכות', category: seder, categoryId: 10);
  seder.books.add(text);
  if (withPdf) {
    bavliRoot.books.add(
      PdfBook(
        title: 'ברכות',
        path: r'C:\books\תלמוד בבלי\ברכות.pdf',
        category: bavliRoot,
      ),
    );
  }
  return (library: Library(categories: [bavliRoot]), text: text);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  Future<void> pumpPanel(WidgetTester tester, Book book) async {
    await tester.pumpWidget(
      BlocProvider<SettingsBloc>(
        create: (_) => _TestSettingsBloc(),
        child: MaterialApp(
          home: Scaffold(body: BookPreviewPanel(book: book)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('BookPreviewPanel — פורמט פתיחת תלמוד בבלי', () {
    testWidgets('הגדרת PDF: התצוגה המקדימה מציגה את מהדורת ה-PDF הנלווית', (
      tester,
    ) async {
      await Settings.setValue(
        SettingsRepository.keyTalmudBavliOpenFormat,
        'pdf',
      );
      final built = _buildLibrary();
      DataRepository.instance.library = Future.value(built.library);

      await pumpPanel(tester, built.text);

      expect(find.text('הספר איננו קיים'), findsOneWidget);
    });

    testWidgets('הגדרת טקסט (ברירת מחדל): נשארת תצוגת מהדורת הטקסט', (
      tester,
    ) async {
      final built = _buildLibrary();
      DataRepository.instance.library = Future.value(built.library);

      await pumpPanel(tester, built.text);

      expect(find.text('הספר איננו קיים'), findsNothing);
    });

    testWidgets('הגדרת PDF אך אין מהדורת PDF: fallback לתצוגת הטקסט', (
      tester,
    ) async {
      await Settings.setValue(
        SettingsRepository.keyTalmudBavliOpenFormat,
        'pdf',
      );
      final built = _buildLibrary(withPdf: false);
      DataRepository.instance.library = Future.value(built.library);

      await pumpPanel(tester, built.text);

      expect(find.text('הספר איננו קיים'), findsNothing);
    });

    testWidgets('הגדרת PDF: ספר אישי אינו מנותב למהדורת ה-PDF המובנית', (
      tester,
    ) async {
      await Settings.setValue(
        SettingsRepository.keyTalmudBavliOpenFormat,
        'pdf',
      );
      final built = _buildLibrary();
      DataRepository.instance.library = Future.value(built.library);
      final userBook = TextBook(
        title: 'ברכות',
        category: built.text.category,
        categoryId: 10,
        isUserBook: true,
      );

      await pumpPanel(tester, userBook);

      expect(find.text('הספר איננו קיים'), findsNothing);
    });
  });
}
