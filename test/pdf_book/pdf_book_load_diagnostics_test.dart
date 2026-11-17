import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/services/recent_book_opens.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';

import '../helpers/memory_settings_cache.dart';

typedef _Entry = ({String title, Object error, Map<String, String?> details});

void main() {
  late List<_Entry> written;
  late RecentBookOpens opens;
  late RecentBookOpens previous;

  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() {
    written = [];
    previous = RecentBookOpens.instance;
    opens = RecentBookOpens.instance = RecentBookOpens(
      writeLog:
          ({
            required String title,
            required Object error,
            StackTrace? stackTrace,
            Map<String, String?> details = const {},
          }) => written.add((title: title, error: error, details: details)),
    );
  });

  tearDown(() => RecentBookOpens.instance = previous);

  PdfBookBloc makeBloc() {
    final tab = PdfBookTab(
      book: PdfBook(title: 'ספר בדיקה', path: '/nonexistent/test.pdf', id: 5),
      pageNumber: 3,
    );
    final bloc = PdfBookBloc(
      tab: tab,
      initialState: PdfBookInitial(book: tab.book, initialPageNumber: 3),
      pdfrxInit: () async {},
    );
    addTearDown(bloc.close);
    return bloc;
  }

  test('קובץ חסר: נרשם כשל וניסיון פתיחה שנכשל', () async {
    final bloc = makeBloc();
    final error = bloc.stream.firstWhere((s) => s is PdfBookError);
    bloc.add(const LoadPdfDocument());
    await error;

    final entry = written.single;
    expect(entry.title, 'Book Load Error (pdf)');
    expect(entry.details, containsPair('book', 'ספר בדיקה'));
    expect(entry.details, containsPair('id', '5'));
    expect(entry.details, containsPair('message', 'הספר איננו קיים'));
    expect(entry.details, containsPair('page', '3'));
    expect(entry.details.values, isNot(contains(contains('nonexistent'))));
    expect(opens.attempts.single.kind, BookOpenKind.pdf);
    expect(opens.attempts.single.outcome, BookOpenOutcome.failed);
  });

  test('כשל של pdfrx נרשם עם השגיאה המקורית', () async {
    final bloc = makeBloc();
    bloc.emit(PdfBookLoading(book: bloc.tab.book));
    final cause = StateError('FPDF_GetLastError=3');
    final error = bloc.stream.firstWhere((s) => s is PdfBookError);
    bloc.add(
      SetLoadingState(isLoading: false, succeeded: false, error: cause),
    );
    await error;

    expect(written.single.error, same(cause));
    expect(written.single.details, containsPair('errorType', 'StateError'));
  });

  test('שגיאה עם retry אוטומטי אינה נרשמת', () async {
    final bloc = makeBloc();
    bloc.emit(PdfBookLoading(book: bloc.tab.book));
    final error = bloc.stream.firstWhere((s) => s is PdfBookError);
    bloc.add(const DocumentLoadFailed('איטי', autoRetry: true));
    await error;

    expect(written, isEmpty);
  });
}
