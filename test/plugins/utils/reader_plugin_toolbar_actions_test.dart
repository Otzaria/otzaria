import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
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

class _TextTab implements TextBookTab {
  @override
  final TextBook book;
  _TextTab(String type) : book = TextBook(title: type, fileType: type);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PdfTab implements PdfBookTab {
  @override
  final PdfBook book = PdfBook(title: 'pdf', path: 'test.pdf');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'two reader toolbars use their own tabs in primary and overflow',
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
          'placement': placement,
        }, instanceId: 'live');
      }
      final word = _TextTab('docx');
      final text = _TextTab('txt');
      final macro = _TextTab('docm');
      final pdf = _PdfTab();
      for (final panes in <List<OpenedTab>>[
        [word, text],
        [text, word],
        [word, pdf],
        [pdf, word],
        [text, macro],
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
          for (final pane in panes)
            identical(pane, word) || identical(pane, macro) ? (1, 1) : (0, 0),
        ]);
      }
    },
  );
}
