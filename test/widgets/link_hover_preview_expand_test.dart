import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/widgets/misc/link_context_menu_entry.dart';

import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  tearDown(LibraryProviderManager.instance.resetForTesting);

  /// מרימה את תוכן החלונית לקישור עם תוכן ארוך, חתוך ל-4 שורות ברוחב צר.
  Future<void> pumpPreview(WidgetTester tester, {int index2 = 1}) async {
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: const {},
      providers: [
        _FakeContentProvider(List.filled(60, 'מילה').join(' ')),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SettingsBloc>.value(
          value: _TestSettingsBloc(SettingsState.initial()),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                child: LinkHoverPreviewContent(
                  link: Link(
                    heRef: 'מפרש א, א',
                    index1: 1,
                    path2: 'מפרש א',
                    index2: index2,
                    connectionType: 'commentary',
                  ),
                  maxContentLines: 4,
                  compact: true,
                  removeNikud: false,
                  removePunctuation: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('תוכן חתוך מציג לחצן "…" ולחיצתו פורשת אותו לתצוגה נגללת', (
    tester,
  ) async {
    await pumpPreview(tester);

    final dots = find.text('…');
    expect(dots, findsOneWidget);
    expect(find.byType(Scrollable), findsNothing);

    await tester.tap(dots);
    await tester.pumpAndSettle();

    // הלחצן נעלם והתוכן המלא נגלל בתוך החלונית.
    expect(find.text('…'), findsNothing);
    expect(find.byType(Scrollable), findsOneWidget);
  });

  testWidgets('תוכן קצר אינו מציג לחצן פרישה', (tester) async {
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: const {},
      providers: [_FakeContentProvider('שורה קצרה')],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SettingsBloc>.value(
          value: _TestSettingsBloc(SettingsState.initial()),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                child: LinkHoverPreviewContent(
                  link: Link(
                    heRef: 'מפרש ב, א',
                    index1: 1,
                    path2: 'מפרש ב',
                    index2: 1,
                    connectionType: 'commentary',
                  ),
                  maxContentLines: 4,
                  compact: true,
                  removeNikud: false,
                  removePunctuation: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('…'), findsNothing);
  });
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// ספק שמחזיר תוכן קבוע לכל קישור.
class _FakeContentProvider implements LibraryProvider {
  _FakeContentProvider(this.content);

  final String content;

  @override
  Future<String> getLinkContent(Link link) async => content;

  @override
  String get displayName => 'Fake';
  @override
  bool get isInitialized => true;
  @override
  int get priority => 0;
  @override
  String get providerId => 'fake';
  @override
  String get sourceIndicator => 'T';
  @override
  Future<void> initialize() async {}
  @override
  Future<Set<String>> getAvailableBookTitles() async => const {};
  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async =>
      false;
  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    bool preferUserBooks = false,
  }) async => null;
  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    bool preferUserBooks = false,
  }) async => const [];
  @override
  Future<Library> buildLibraryCatalog(
    Map<String, Map<String, dynamic>> metadata,
    String rootPath,
  ) => throw UnimplementedError();
  @override
  Future<List<Link>> getAllLinksForBook(
    String title,
    int categoryId,
    String fileType,
  ) async => const [];
  @override
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  ) async => const {};
}
