import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _FakeBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _FakeBloc()
    : super(TextBookInitial(TextBook(title: 'ספר'), 0, false, const [])) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = PluginCorrectionSessionService.instance;
  final events = <(String, Map<String, dynamic>)>[];

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(events.clear);
  tearDown(() => service.removeOwner('owner'));

  TextBookTab newTab() => TextBookTab(
    book: TextBook(id: 1, title: 'ספר'),
    index: 0,
    blocOverride: _FakeBloc(),
  );

  void begin(TextBookTab tab) => service.begin(
    owner: 'owner',
    tabId: PluginCorrectionSessionService.tabIdFor(tab),
    bookId: 'ספר',
    bookUid: 'id:1',
    libraryVersion: '1',
    loadSource: (_) async => 'מקור',
    onEvent: (topic, payload) => events.add((topic, payload)),
  );

  test('סגירת הלשונית מסיימת את הסשן שלה עם tab_closed', () {
    final tab = newTab();
    begin(tab);
    final id = PluginCorrectionSessionService.tabIdFor(tab);
    expect(service.hasSessionForTab(id), isTrue);

    tab.dispose();

    expect(service.hasSessionForTab(id), isFalse);
    expect(events.single.$1, 'reader.correctionSessionEnded');
    expect(events.single.$2['reason'], 'tab_closed');
  });

  test('סגירת לשונית אחת אינה מסיימת סשן של לשונית אחרת', () {
    final closing = newTab();
    final staying = newTab();
    begin(closing);
    begin(staying);

    closing.dispose();

    expect(
      service.hasSessionForTab(
        PluginCorrectionSessionService.tabIdFor(staying),
      ),
      isTrue,
    );
    staying.dispose();
  });

  test('לשונית שמעולם לא קיבלה מזהה נסגרת בלי לגעת בסשנים', () {
    final other = newTab();
    begin(other);
    final tab = newTab();

    tab.dispose();

    expect(PluginCorrectionSessionService.knownTabIdFor(tab), isNull);
    expect(
      service.hasSessionForTab(PluginCorrectionSessionService.tabIdFor(other)),
      isTrue,
    );
    other.dispose();
  });
}
