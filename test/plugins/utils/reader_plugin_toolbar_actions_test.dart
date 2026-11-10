import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';
import 'package:otzaria/plugins/utils/reader_plugin_toolbar_actions.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';

class _SettingsBloc implements SettingsBloc {
  @override
  SettingsState get state => SettingsState.initial();
  @override
  Stream<SettingsState> get stream => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// לשונית מדומה: לשונית אמיתית קוראת הגדרות בבנאי, והבדיקה צריכה רק את הספר.
class _TextTab implements TextBookTab {
  @override
  final TextBook book;
  _TextTab(String type, {BookSource source = BookSource.user})
    : book = TextBook(title: type, fileType: type, source: source);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PdfTab implements PdfBookTab {
  @override
  final PdfBook book = PdfBook(
    title: 'pdf',
    path: 'test.pdf',
    source: BookSource.user,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// `bookTypes`/`bookSources` של פקד נבדקים מול מה ש-[readerBookTypeOf] ו-
/// [readerBookSourceOf] מחזירים לסרגל של כל לשונית. הערכים חייבים להיות בדיוק
/// `type`/`source` של זהות הספר, אחרת תוסף שמסנן לפי מה שהוא רואה באירוע
/// הלחיצה (`currentType`, `currentSource`) היה מקבל סרגל אחר.
void main() {
  test('ספר Word בקורא הטקסט מקבל את סיומת המסמך', () {
    expect(readerBookTypeOf(_TextTab('docx')), 'docx');
    expect(readerBookTypeOf(_TextTab('docm')), 'docm');
  });

  test('ספר טקסט רגיל מקבל text', () {
    expect(readerBookTypeOf(_TextTab('txt')), 'text');
  });

  test('ספר PDF מקבל pdf', () {
    expect(readerBookTypeOf(_PdfTab()), 'pdf');
  });

  test('הסוג והמקור זהים לזהות הספר, ותמיד מוכרים למפענח', () {
    for (final tab in [_TextTab('docx'), _TextTab('txt')]) {
      final identity = PluginBookIdentity.toJson(tab.book);
      expect(readerBookTypeOf(tab), identity['type']);
      expect(readerBookSourceOf(tab), identity['source']);
      expect(PluginBookIdentity.knownTypes, contains(readerBookTypeOf(tab)));
      expect(
        PluginBookIdentity.knownSources,
        contains(readerBookSourceOf(tab)),
      );
    }
  });

  test('ספר אישי מקבל user, ספר הספרייה מקבל library', () {
    expect(readerBookSourceOf(_TextTab('txt')), 'user');
    expect(
      readerBookSourceOf(_TextTab('txt', source: BookSource.official)),
      'library',
    );
  });

  testWidgets(
    'בפיצול, כל סרגל מסנן לפי הלשונית שלו — בסרגל וב-overflow, בשני הסדרים',
    (tester) async {
      final registry = PluginToolbarRegistry.instance;
      addTearDown(() => registry.removeAll('test.word.toolbar'));
      for (final placement in ['primary', 'overflow']) {
        registry.registerPayload('test.word.toolbar', {
          'id': placement,
          'title': placement,
          'icon': 'document_edit_24_regular',
          'contexts': ['reader-text'],
          'bookTypes': ['docx', 'docm'],
          'bookSources': ['user'],
          'placement': placement,
        }, instanceId: 'live');
      }
      final word = _TextTab('docx');
      final text = _TextTab('txt');
      final macro = _TextTab('docm');
      final libraryWord = _TextTab('docx', source: BookSource.official);
      final pdf = _PdfTab();
      final shown = {word, macro};
      for (final panes in <List<OpenedTab>>[
        [word, text],
        [text, word],
        [word, pdf],
        [pdf, word],
        [text, macro],
        [word, libraryWord],
        [libraryWord, word],
      ]) {
        final counts = <(int, int)>[];
        await tester.pumpWidget(
          BlocProvider<SettingsBloc>.value(
            value: _SettingsBloc(),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Builder(
                builder: (context) {
                  for (final pane in panes) {
                    final kind = pane is PdfBookTab
                        ? 'reader-pdf'
                        : 'reader-text';
                    counts.add((
                      buildReaderPluginActions(
                        context,
                        tab: pane,
                        pluginContext: kind,
                      ).length,
                      buildReaderPluginOverflowActions(
                        context,
                        tab: pane,
                        pluginContext: kind,
                      ).length,
                    ));
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        expect(counts, [
          for (final pane in panes) shown.contains(pane) ? (1, 1) : (0, 0),
        ]);
      }
    },
  );
}
