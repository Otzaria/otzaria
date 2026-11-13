import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/services/hebrew_books_download_service.dart';
import 'package:otzaria/library/view/otzar_book_dialog.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';

import '../../helpers/memory_settings_cache.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

Widget _wrap(
  Widget child, {
  bool isOfflineMode = false,
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  final settings = _MockSettingsBloc();
  whenListen(
    settings,
    const Stream<SettingsState>.empty(),
    initialState: SettingsState.initial().copyWith(
      isOfflineMode: isOfflineMode,
    ),
  );
  return BlocProvider<SettingsBloc>.value(
    value: settings,
    child: MaterialApp(
      navigatorKey: navigatorKey,
      locale: const Locale('he', 'IL'),
      home: Scaffold(body: child),
    ),
  );
}

ExternalLibraryBook _hebrewBook() => ExternalLibraryBook(
  title: 'ספר היברובוקס',
  id: 10022,
  link: 'https://hebrewbooks.org/10022',
  externalLibraryId: 'hb:10022',
  topics: '',
);

ExternalLibraryBook _otzarBook() => ExternalLibraryBook(
  title: 'ספר אוצר החכמה',
  id: 555,
  link: 'https://tablet.otzar.org/book/book.php?book=555',
  externalLibraryId: 'oh:555',
  topics: '',
);

class _NoFiles extends Fake implements FileSystemData {}

class _EmptyHiddenStore extends HiddenLibraryStore {
  const _EmptyHiddenStore();
  @override
  HiddenLibrarySelection load() => const HiddenLibrarySelection();
}

/// קטלוג היברובוקס של ספר אחד, ממופה לפי סריקה אמיתית של [folder].
class _CatalogRepository extends DataRepository {
  _CatalogRepository(this.folder) : super(fileSystemData: _NoFiles());
  final String folder;

  @override
  Future<List<Book>> getHebrewBooks() async =>
      FileSystemData.mapHebrewBooksToLocal([
        _hebrewBook(),
      ], await FileSystemData.scanHebrewBooksPdfFilesAtPath(folder));
}

/// לוחץ "הורדת הקובץ" כש-[client] עונה, ומחזיר את הודעת הכשל שהוצגה.
Future<String?> _failedDownloadMessage(
  WidgetTester tester,
  http.Client client,
) async {
  await Settings.init(cacheProvider: MemorySettingsCache());
  final folder = Directory.systemTemp.createTempSync('hb_5002_');
  addTearDown(() => folder.deleteSync(recursive: true));
  await Settings.setValue<String>(
    SettingsRepository.keyHebrewBooksPath,
    folder.path,
  );
  final library = _MockLibraryBloc();
  whenListen(
    library,
    const Stream<LibraryState>.empty(),
    initialState: LibraryState.initial(),
  );
  await tester.pumpWidget(
    BlocProvider<LibraryBloc>.value(
      value: library,
      child: _wrap(
        OtzarBookDialog(book: _hebrewBook()),
        navigatorKey: navigatorKey,
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.runAsync(
    () => http.runWithClient(() async {
      await tester.tap(find.text('הורדת הקובץ'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await ErrorLogFile.flushPending();
    }, () => client),
  );
  await tester.pump();
  await tester.pump();

  final shown = tester.widget<Text>(find.textContaining('הורדת הספר')).data;
  expect(find.text('הורדת הקובץ'), findsOneWidget);
  UiSnack.hide();
  await tester.pump(const Duration(seconds: 5));
  return shown;
}

void main() {
  group('כתובת ההורדה', () {
    test('נבנית מתוך מזהה הספר', () {
      expect(
        HebrewBooksDownloadService.fileUrl(10022).toString(),
        'https://files.hebrewbooksoffline.dpdns.org/HebrewBooks/books/10022.pdf',
      );
    });

    test('שם הקובץ תואם לתבנית שסורק תיקיית היברובוקס מזהה', () {
      expect(HebrewBooksDownloadService.fileNameFor(10022), '10022.pdf');
    });
  });

  group('כפתור ההורדה בדיאלוג הספר', () {
    testWidgets('מוצג לספר היברובוקס לצד "פתח באתר"', (tester) async {
      await tester.pumpWidget(_wrap(OtzarBookDialog(book: _hebrewBook())));
      await tester.pumpAndSettle();

      expect(find.text('פתח באתר'), findsOneWidget);
      expect(find.text('הורדת הקובץ'), findsOneWidget);
    });

    testWidgets('אינו מוצג לספר אוצר החכמה', (tester) async {
      // בדיקת הקיום המקומי של אוצר החכמה ניגשת לדיסק — חייב runAsync.
      await tester.runAsync(() async {
        await tester.pumpWidget(_wrap(OtzarBookDialog(book: _otzarBook())));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(find.text('פתח באתר'), findsOneWidget);
      expect(find.text('הורדת הקובץ'), findsNothing);
    });

    testWidgets('אינו מוצג במצב מנותק (issue #5002)', (tester) async {
      await tester.pumpWidget(
        _wrap(OtzarBookDialog(book: _hebrewBook()), isOfflineMode: true),
      );
      await tester.pumpAndSettle();

      expect(find.text('פתח באתר'), findsOneWidget);
      expect(find.text('הורדת הקובץ'), findsNothing);
    });
  });

  group('כשל בהורדה (issue #5002)', () {
    testWidgets(
      'כשל רשת מוצג בעברית בלי טקסט החריגה, והפרטים נרשמים ביומן',
      (tester) async {
        // מחשב בלי רשת: כתובת שרת ההורדות אינה מתורגמת.
        final shown = await _failedDownloadMessage(
          tester,
          MockClient(
            (_) async => throw const SocketException(
              "Failed host lookup: 'files.hebrewbooksoffline.dpdns.org'",
              osError: OSError('No such host is known.', 11001),
            ),
          ),
        );

        expect(shown, isNot(contains('Failed host lookup')));
        expect(shown, isNot(matches(RegExp('[A-Za-z]'))));
        final log = ErrorLogFile.resolveFile();
        expect(
          log.existsSync() ? log.readAsStringSync() : '',
          contains("Failed host lookup: 'files.hebrewbooksoffline.dpdns.org'"),
        );
      },
    );

    testWidgets('סטטוס השגיאה של השרת מוצג למשתמש', (tester) async {
      final shown = await _failedDownloadMessage(
        tester,
        MockClient((_) async => http.Response('', 404)),
      );

      expect(shown, 'שגיאה בהורדת הספר: השרת החזיר 404');
    });
  });

  testWidgets(
    'ספר שירד לתיקיית היברובוקס מוצג בתוצאות כספר מקומי בלי רענון (issue #2385)',
    (tester) async {
      await Settings.init(cacheProvider: MemorySettingsCache());
      final folder = Directory.systemTemp.createTempSync('hb_2385_');
      addTearDown(() => folder.deleteSync(recursive: true));
      await Settings.setValue<String>(
        SettingsRepository.keyHebrewBooksPath,
        folder.path,
      );
      final library = Library(categories: []);
      late LibraryBloc bloc;

      // הבלוק נוצר בתוך runAsync: הסריקה והחיפוש ניגשים לדיסק.
      await tester.runAsync(
        () => http.runWithClient(() async {
          bloc = LibraryBloc(
            hiddenStore: const _EmptyHiddenStore(),
            repository: _CatalogRepository(folder.path)
              ..library = Future.value(library),
          );
          bloc.emit(
            LibraryState(
              library: library,
              currentCategory: library,
              isLoading: false,
            ),
          );
          final searched = bloc.stream.firstWhere(
            (s) => !s.isSearching && s.searchResults != null,
          );
          bloc
            ..add(const UpdateSearchQuery('היברובוקס'))
            ..add(const SearchBooks(showHebrewBooks: true));
          expect(
            (await searched).searchResults!.single,
            isA<ExternalLibraryBook>(),
          );

          await tester.pumpWidget(
            BlocProvider.value(
              value: bloc,
              child: _wrap(OtzarBookDialog(book: _hebrewBook())),
            ),
          );
          await tester.pump();
          final local = bloc.stream.firstWhere(
            (s) => s.searchResults?.any((b) => b is PdfBook) ?? false,
          );
          await tester.tap(find.text('הורדת הקובץ'));
          await local.timeout(
            const Duration(seconds: 5),
            onTimeout: () => bloc.state,
          );
        }, () => MockClient((_) async => http.Response('%PDF-1.4', 200))),
      );
      await tester.pump();

      expect(File('${folder.path}/10022.pdf').existsSync(), isTrue);
      expect(bloc.state.searchResults!.single, isA<PdfBook>());
      await tester.runAsync(bloc.close);
    },
  );
}
