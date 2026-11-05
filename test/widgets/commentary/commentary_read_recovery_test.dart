import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/repository/book_notes_repository.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/widgets/commentary/commentary_content.dart';
import 'package:otzaria/widgets/commentary/links_list_view.dart';
import 'package:otzaria/widgets/commentary/panel_anchor_links.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';

import '../../helpers/memory_settings_cache.dart';

const _profile = TextDisplayProfile(anchorMarkers: MarkVisibility.hide);

class _SettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _SettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Each explicit read stays unresolved until the test releases it. This tests
/// widget recovery without opening SQLite or starting worker isolates.
class _ControlledLink extends Link {
  _ControlledLink(String title)
    : super(
        heRef: '$title, א',
        index1: 1,
        path2: title,
        index2: 1,
        connectionType: LinkTypes.mesoratHashas,
      );

  final reads = <Completer<String>>[];

  @override
  Future<String> get content {
    final read = Completer<String>();
    reads.add(read);
    return read.future;
  }

  @override
  Future<String> get displayReference => Future.value(fallbackDisplayReference);
}

class _ImmediatelyBusyLink extends _ControlledLink {
  _ImmediatelyBusyLink(super.title);

  @override
  Future<String> get content {
    final pending = super.content;
    if (reads.length == 1) {
      reads.single.completeError(StateError('storage busy immediately'));
    }
    return pending;
  }
}

Widget _host(_SettingsBloc settings, Widget child) => MaterialApp(
  home: BlocProvider<SettingsBloc>.value(
    value: settings,
    child: Scaffold(body: child),
  ),
);

Widget _commentary(_ControlledLink link) => SingleChildScrollView(
  child: CommentaryContent(
    key: const ValueKey('read-recovery-commentary'),
    link: link,
    fontSize: 18,
    openBookCallback: (_) {},
    displayProfile: _profile,
  ),
);

Widget _links(_ControlledLink link) => LinksListView(
  key: const ValueKey('read-recovery-links'),
  displayProfile: _profile,
  links: [link],
  chipSourceLinks: [link],
  openBookTitle: 'ספר מקור',
  selectedLinkTypes: const {},
  onSelectedLinkTypesChanged: (_) {},
  openBookCallback: (_) {},
  fontSize: 16,
);

bool _rendersCommentary(WidgetTester tester, String text) => tester
    .widgetList<SmartTextWidget>(find.byType(SmartTextWidget))
    .any((widget) => widget.text.contains(text));

bool _rendersLink(WidgetTester tester, String text) => tester
    .widgetList<PanelAnchoredText>(find.byType(PanelAnchoredText))
    .any((widget) => widget.html.contains(text));

void main() {
  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() {
    Link.clearContentCache();
    BookNotesRepository.instance
      ..clear()
      ..debugIsDatabaseBook = (title, {categoryId, fileType}) async => false;
  });

  tearDown(() {
    BookNotesRepository.instance
      ..debugIsDatabaseBook = null
      ..clear();
    CommentaryService.clearEraCache();
    Link.clearContentCache();
  });

  for (final errorAsData in [false, true]) {
    final failureKind = errorAsData ? 'error text' : 'failed future';

    testWidgets('commentary retries $failureKind on the next parent update', (
      tester,
    ) async {
      final settings = _SettingsBloc();
      addTearDown(settings.close);
      final link = _ControlledLink('מפרש מתאושש');
      await tester.pumpWidget(_host(settings, _commentary(link)));
      final state = tester.state(find.byType(CommentaryContent));
      expect(link.reads, hasLength(1));

      if (errorAsData) {
        link.reads.single.complete('שגיאה בטעינת תוכן המפרש');
      } else {
        link.reads.single.completeError(StateError('storage busy'));
      }
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(link.reads, hasLength(1), reason: 'No autonomous retry loop');

      await tester.pumpWidget(_host(settings, _commentary(link)));
      expect(tester.state(find.byType(CommentaryContent)), same(state));
      expect(link.reads, hasLength(2));
      link.reads.last.complete('התוכן התאושש');
      await tester.pumpAndSettle();
      expect(_rendersCommentary(tester, 'התוכן התאושש'), isTrue);

      await tester.pumpWidget(_host(settings, _commentary(link)));
      await tester.pump();
      expect(
        link.reads,
        hasLength(2),
        reason: 'Successful content stays cached',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'link expansion retries $failureKind after closing and opening',
      (
        tester,
      ) async {
        final settings = _SettingsBloc();
        addTearDown(settings.close);
        final link = _ControlledLink('קישור מתאושש');
        CommentaryService.seedEraCache({link.path2: CommentaryEra.other});
        await tester.pumpWidget(_host(settings, _links(link)));
        await tester.pumpAndSettle();
        final state = tester.state(find.byType(LinksListView));
        expect(link.reads, isEmpty);

        final header = find.descendant(
          of: find.byType(ExpansionTile),
          matching: find.text(link.path2),
        );
        await tester.tap(header);
        await tester.pump();
        expect(link.reads, hasLength(1));
        if (errorAsData) {
          link.reads.single.complete('שגיאה בטעינת תוכן המפרש');
        } else {
          link.reads.single.completeError(StateError('storage busy'));
        }
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 3));
        expect(link.reads, hasLength(1), reason: 'No autonomous retry loop');

        await tester.tap(header);
        await tester.pumpAndSettle();
        await tester.tap(header);
        await tester.pump();
        expect(tester.state(find.byType(LinksListView)), same(state));
        expect(link.reads, hasLength(2));
        link.reads.last.complete('הקישור התאושש');
        await tester.pumpAndSettle();
        expect(_rendersLink(tester, 'הקישור התאושש'), isTrue);

        await tester.tap(header);
        await tester.pumpAndSettle();
        await tester.tap(header);
        await tester.pumpAndSettle();
        expect(
          link.reads,
          hasLength(2),
          reason: 'Successful content stays cached',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('immediate rejection stays visible until the next expansion', (
    tester,
  ) async {
    final settings = _SettingsBloc();
    addTearDown(settings.close);
    final link = _ImmediatelyBusyLink('קישור עמוס');
    CommentaryService.seedEraCache({link.path2: CommentaryEra.other});
    await tester.pumpWidget(_host(settings, _links(link)));
    await tester.pumpAndSettle();
    final header = find.descendant(
      of: find.byType(ExpansionTile),
      matching: find.text(link.path2),
    );

    // Admission may reject before the deferred expansion setState runs.
    await tester.tap(header);
    await tester.pump();
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 2),
    );
    expect(link.reads, hasLength(1));
    expect(find.textContaining('storage busy immediately'), findsOneWidget);

    await tester.tap(header);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pump();
    expect(link.reads, hasLength(2));
    link.reads.last.complete('הקישור זמין שוב');
    await tester.pumpAndSettle();
    expect(_rendersLink(tester, 'הקישור זמין שוב'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'late failure from the old link cannot invalidate its replacement',
    (
      tester,
    ) async {
      final settings = _SettingsBloc();
      addTearDown(settings.close);
      final oldLink = _ControlledLink('מפרש קודם');
      final currentLink = _ControlledLink('מפרש חדש');

      await tester.pumpWidget(_host(settings, _commentary(oldLink)));
      final state = tester.state(find.byType(CommentaryContent));
      expect(oldLink.reads, hasLength(1));
      await tester.pumpWidget(_host(settings, _commentary(currentLink)));
      expect(tester.state(find.byType(CommentaryContent)), same(state));
      expect(currentLink.reads, hasLength(1));

      currentLink.reads.single.complete('התוכן החדש');
      await tester.pumpAndSettle();
      oldLink.reads.single.completeError(
        StateError('old storage request failed'),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(_host(settings, _commentary(currentLink)));
      await tester.pump();

      expect(currentLink.reads, hasLength(1));
      expect(_rendersCommentary(tester, 'התוכן החדש'), isTrue);
      expect(_rendersCommentary(tester, 'מפרש קודם'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
