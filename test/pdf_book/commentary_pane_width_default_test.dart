import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:pdfrx/pdfrx.dart';

import '../helpers/memory_settings_cache.dart';

// רוחב חלונית המפרשים נשמר במפתח אחד לספר טקסט ולספר PDF (סעיף 14, ההחלטה
// א). כשאין ערך שמור, שני הקוראים חייבים להתחיל מאותו רוחב, ולא 400 מול 300.
const _sharedDefault = 350.0;

class _FakeDocumentRef extends Fake implements PdfDocumentRef {}

PdfBookBloc _makeBloc() {
  final book = PdfBook(title: 'ספר בדיקה', path: '/nonexistent/test.pdf');
  final tab = PdfBookTab(book: book, pageNumber: 1);
  return PdfBookBloc(
    tab: tab,
    initialState: PdfBookInitial(book: book, initialPageNumber: 1),
    pdfrxInit: () async {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  test('ספר טקסט: בלי ערך שמור רוחב המפרשים הוא ברירת המחדל המשותפת', () {
    expect(SettingsState.initial().commentaryPaneWidth, _sharedDefault);
    expect(
      SettingsRepository().readSettings()['commentaryPaneWidth'],
      _sharedDefault,
    );
  });

  blocTest<PdfBookBloc, PdfBookState>(
    'ספר PDF: בלי ערך שמור רוחב המפרשים הוא ברירת המחדל המשותפת',
    build: _makeBloc,
    seed: () => PdfBookLoading(
      book: PdfBook(title: 'ספר בדיקה', path: '/nonexistent/test.pdf'),
    ),
    act: (b) =>
        b.add(DocumentReady(documentRef: _FakeDocumentRef(), totalPages: 5)),
    verify: (b) =>
        expect((b.state as PdfBookLoaded).rightPaneWidth, _sharedDefault),
  );

  test('הפעלה ראשונה כותבת את ברירת המחדל המשותפת להגדרות השמורות', () async {
    await SettingsRepository().loadSettings();
    expect(
      Settings.getValue<double>(SettingsRepository.keyCommentaryPaneWidth),
      _sharedDefault,
    );
  });
}
