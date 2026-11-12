import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_library_books_registry.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/services/book_details_service.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _EmptyRepository implements PluginRegistryRepository {
  @override
  Future<String?> getKV(String pluginId, String namespace, String key) async =>
      null;

  @override
  Future<void> setKV(
    String pluginId,
    String namespace,
    String key,
    String valueJson,
  ) async {}

  @override
  Future<void> removeKV(String pluginId, String namespace, String key) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFileSystemData extends FileSystemData {
  @override
  Future<bool> canDeleteUserBookFromLibrary({
    required String title,
    int? categoryId,
    String fileType = 'txt',
    required BookSource source,
  }) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FileSystemData originalFileSystemData;
  late PluginLibraryBooksRegistry original;
  late PluginLibraryBooksRegistry registry;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    original = PluginLibraryBooksRegistry.instance;
    originalFileSystemData = FileSystemData.instance;
  });

  setUp(() {
    FileSystemData.instance = _FakeFileSystemData();
    registry = PluginLibraryBooksRegistry.forTesting(
      dispatch: (_, _, _, {viewId, windowKeys}) async {},
      conditions: PluginConditionEvaluator.forTesting(
        settingReader: (_) => null,
      ),
      repository: _EmptyRepository(),
    );
    PluginLibraryBooksRegistry.instance = registry;
    registry.registerPayload('p1', {
      'id': 'books',
      'provider': 'mylib',
      'title': 'הספרייה שלי',
    });
  });

  tearDown(() {
    FileSystemData.instance = originalFileSystemData;
    PluginLibraryBooksRegistry.instance = original;
    registry.dispose();
  });

  Future<Book> providerBook(
    WidgetTester tester,
    Map<String, dynamic> record,
  ) async {
    await tester.runAsync(
      () => registry.setBooks('p1', 'mylib', [
        {'id': 1, ...record},
      ]),
    );
    return registry.booksOf('mylib').single;
  }

  Future<void> pumpCard(WidgetTester tester, Book book) => tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: Center(
          child: SizedBox(
            width: 260,
            child: BookGridItem(
              book: book,
              showTopics: true,
              onBookClickCallback: () {},
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('ספר של תוסף מציג כפתור מידע, בלי תפריט אפשרויות', (
    tester,
  ) async {
    final book = await providerBook(tester, {'title': 'אבני נזר'});

    await pumpCard(tester, book);
    await tester.pumpAndSettle();

    expect(find.byIcon(FluentIcons.info_24_regular), findsOneWidget);
    expect(find.byType(BookActionsMenuButton), findsNothing);
  });

  testWidgets('החלון מציג את נתוני התוסף, כולל התיאור בפסקאות', (tester) async {
    final book = await providerBook(tester, {
      'title': 'אבני נזר',
      'author': 'רבי אברהם בורנשטיין',
      'categoryPath': 'שו"ת/אחרונים',
      'description': 'פסקה ראשונה.\n\nפסקה שנייה.',
    });

    await pumpCard(tester, book);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FluentIcons.info_24_regular));
    await tester.pumpAndSettle();

    expect(find.text('אודות הספר'), findsOneWidget);
    expect(find.text('אבני נזר'), findsWidgets);
    expect(find.text('רבי אברהם בורנשטיין'), findsWidgets);
    expect(find.text('שו"ת, אחרונים'), findsWidgets);
    expect(find.text('ספר מתוסף: הספרייה שלי'), findsOneWidget);
    expect(find.text('תיאור'), findsOneWidget);
    expect(find.text('פסקה ראשונה.\n\nפסקה שנייה.'), findsOneWidget);
    // בלי חיפוש בספריית אוצריא: אין מקור, נתיב קובץ או "לא נמצא".
    expect(find.text('לא נמצא מקור'), findsNothing);
    expect(find.text(BookDetailsService.bookNotFoundText), findsNothing);
  });

  testWidgets('בלי תיאור: החלון נפתח עם שאר השדות ובלי קטע תיאור', (
    tester,
  ) async {
    final book = await providerBook(tester, {'title': 'אבני נזר'});

    await pumpCard(tester, book);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FluentIcons.info_24_regular));
    await tester.pumpAndSettle();

    expect(find.text('אודות הספר'), findsOneWidget);
    expect(find.text('ספר מתוסף: הספרייה שלי'), findsOneWidget);
    expect(find.text('תיאור'), findsNothing);
  });

  testWidgets('שם ספק ששווה לשם מקור מוכר אינו מקבל את לוגו המקור', (
    tester,
  ) async {
    registry.removePlugin('p1');
    registry.registerPayload('p1', {
      'id': 'books',
      'provider': 'mylib',
      'title': 'tashma',
    });
    final book = await providerBook(tester, {'title': 'אבני נזר'});

    await pumpCard(tester, book);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FluentIcons.info_24_regular));
    await tester.pumpAndSettle();

    expect(find.text('ספר מתוסף: tashma'), findsOneWidget);
    expect(find.textContaining('כל הזכויות שמורות'), findsNothing);
  });

  testWidgets('ספר חיצוני של קטלוג אחר נשאר עם התפריט הקיים', (tester) async {
    final book = ExternalLibraryBook(
      title: 'ספר מאוצר החכמה',
      id: 7,
      link: 'https://tablet.otzar.org/book/7',
      externalLibraryId: 'otzar:7',
    );

    await pumpCard(tester, book);
    await tester.pumpAndSettle();

    expect(find.byIcon(FluentIcons.info_24_regular), findsOneWidget);
    expect(find.byType(BookActionsMenuButton), findsOneWidget);
  });

  test('BookInformation.pluginProvided נבנה מהספר בלבד, בלי גישה לספרייה', () {
    final book = ExternalLibraryBook(
      title: 'אבני נזר',
      id: 1,
      author: 'מחבר',
      heDesc: 'תיאור',
      link: '',
    );

    final information = BookInformation.pluginProvided(
      book,
      providerName: 'הספרייה שלי',
    );

    expect(information.databaseBook, isNull);
    expect(information.source, isNull);
    expect(information.pluginProviderName, 'הספרייה שלי');
    expect(information.fullDescription, 'תיאור');
    expect(information.authors, ['מחבר']);
    expect(
      information.fileDetails['נתיב הקובץ'],
      BookDetailsService.bookNotFoundText,
    );
  });
}
