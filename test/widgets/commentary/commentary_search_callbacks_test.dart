import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/widgets/commentary/commentary_content.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../support/search_engine_test_init.dart';
import '../../test_helpers/stub_settings_bloc.dart';

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => Settings.init(cacheProvider: MemorySettingsCache()));

  testWidgets('דיווח ממתין נשאר עם השאילתה וה-callback שבנו אותו', (
    tester,
  ) async {
    final settings = StubSettingsBloc();
    addTearDown(settings.close);
    final link = _Link();
    final oldCounts = <int>[];
    final newCounts = <int>[];
    final oldSnippets = <String>[];
    final newSnippets = <String>[];
    final hiddenNikud = TextDisplayProfile.defaults.copyWith(
      nikud: MarkVisibility.hide,
    );

    CommentaryContent content({required bool updated}) => CommentaryContent(
      link: link,
      fontSize: 18,
      openBookCallback: (_) {},
      displayProfile: updated ? hiddenNikud : TextDisplayProfile.defaults,
      searchQuery: updated ? 'חדש' : 'ישן',
      onSearchResultsCountChanged: updated ? newCounts.add : oldCounts.add,
      onSearchSnippetsChanged: updated
          ? newSnippets.addAll
          : oldSnippets.addAll,
    );

    // נרשם לפני בניית התוכן, ולכן מחליף את ה-widget אחרי build ולפני דיווחיו.
    tester.binding.addPostFrameCallback((_) {
      final element = tester.element(find.byType(CommentaryContent));
      element.owner!.buildScope(
        element,
        () => element.update(content(updated: true)),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SettingsBloc>.value(
          value: settings,
          child: Scaffold(body: content(updated: false)),
        ),
      ),
    );

    expect(oldCounts, [2]);
    expect(newCounts, isNot(contains(2)));
    expect(oldSnippets.single, contains('אָמַר'));
    await tester.pumpAndSettle();
    expect(newCounts, isNotEmpty);
    expect(newCounts, everyElement(1));
    expect(newSnippets, isNotEmpty);
    expect(newSnippets, everyElement(isNot(contains('אָמַר'))));
    expect(tester.takeException(), isNull);
  }, skip: !engineReady);
}

class _Link extends Link {
  _Link()
    : super(
        heRef: 'בדיקת דיווח',
        index1: 1,
        path2: 'בדיקת דיווח',
        index2: 1,
        connectionType: 'COMMENTARY',
      );

  @override
  String get loadedContent => 'ישן ישן חדש אָמַר';

  @override
  Future<String> get content => Future.value(loadedContent);

  @override
  Future<String> get displayReference => Future.value(heRef);
}
