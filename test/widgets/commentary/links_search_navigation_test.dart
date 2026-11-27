import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/widgets/commentary/links_list_view.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/widgets/navigation/search_result_navigator.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../test_helpers/stub_settings_bloc.dart';

class _ContentLink extends Link {
  _ContentLink({
    required super.heRef,
    required super.index1,
    required super.path2,
    required super.index2,
    required this._content,
  }) : super(connectionType: LinkTypes.quotation);

  final String _content;

  @override
  Future<String> get content => Future.value(_content);

  @override
  Future<String> get displayReference => Future.value(fallbackDisplayReference);
}

class _DeferredLink extends Link {
  _DeferredLink(String title, this.pending)
    : super(
        heRef: 'הפניה',
        index1: 1,
        path2: title,
        index2: 1,
        connectionType: LinkTypes.quotation,
      );

  final Future<String> Function() pending;
  @override
  Future<String> get content => pending();
  @override
  Future<String> get displayReference => Future.value(fallbackDisplayReference);
}

List<Link> _links() => [
  for (var i = 0; i < 3; i++)
    _ContentLink(
      heRef: 'הפניה $i',
      index1: i + 1,
      path2: 'ספר$i',
      index2: 1,
      content: 'תוכן עם המילה שלום מספר $i',
    ),
];

Future<void> _pump(WidgetTester tester) async {
  await _pumpLinks(tester, _links());
  await tester.enterText(find.byType(RtlTextField), 'שלום');
  await tester.pumpAndSettle();
  await tester.tap(find.byType(Checkbox));
  await tester.pumpAndSettle();
}

Future<void> _pumpLinks(WidgetTester tester, List<Link> links) async {
  // בלי דורות במטמון, המיון לפי דורות פונה למסד שאינו קיים בבדיקה.
  CommentaryService.seedEraCache({
    for (final link in links) link.path2: CommentaryEra.acharonim,
  });
  addTearDown(CommentaryService.clearEraCache);
  final settings = StubSettingsBloc();
  addTearDown(settings.close);
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<SettingsBloc>.value(
        value: settings,
        child: Scaffold(
          body: LinksListView(
            displayProfile: TextDisplayProfile.defaults,
            links: links,
            chipSourceLinks: links,
            openBookTitle: 'שבת',
            selectedLinkTypes: const {},
            onSelectedLinkTypesChanged: (_) {},
            openBookCallback: (_) {},
            fontSize: 16,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// מספרי הקישורים הפתוחים, לפי הטקסט שהם מרנדרים.
List<int> _openLinks(WidgetTester tester) => [
  for (final widget in tester.widgetList<SmartTextWidget>(
    find.byType(SmartTextWidget),
  ))
    int.parse(RegExp(r'מספר (\d)').firstMatch(widget.text)!.group(1)!),
];

void main() {
  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  testWidgets('הקישור הראשון עם תוצאה נפתח, וההתאמה מודגשת כמו בחיפוש בספר', (
    tester,
  ) async {
    await _pump(tester);

    expect(_openLinks(tester), [0]);
    final widget = tester.widget<SmartTextWidget>(find.byType(SmartTextWidget));
    expect(
      TextRendererService.processText(widget.text, widget.settings),
      contains(
        '<span style="color: otzaria-search-hit; background-color: otzaria-search-hit-bg">שלום</span>',
      ),
    );
  });

  testWidgets('Enter עובר לקישור הבא ופותח אותו', (tester) async {
    await _pump(tester);

    await tester.tap(find.byType(RtlTextField));
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(_openLinks(tester), [0, 1]);
  });

  testWidgets('Enter בקישור האחרון נשאר בו', (tester) async {
    await _pump(tester);

    for (var i = 0; i < 5; i++) {
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
    }

    expect(_openLinks(tester), [0, 1, 2]);
  });

  testWidgets('ניווט פותח שוב תוצאה שהמשתמש סגר, גם בפעם השנייה', (
    tester,
  ) async {
    await _pump(tester);
    for (var repeat = 0; repeat < 2; repeat++) {
      await tester.tap(find.text('ספר0'));
      await tester.pumpAndSettle();
      expect(_openLinks(tester), isNot(contains(0)));
      await tester.tap(find.byTooltip('תוצאה הבאה'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('תוצאה קודמת'));
      await tester.pumpAndSettle();
      expect(_openLinks(tester), contains(0));
    }
  });

  for (final finishOldFirst in [false, true]) {
    testWidgets(
      'השלמת חיפוש ישן אינה משנה ניווט חדש (לפי הסדר: $finishOldFirst)',
      (tester) async {
        final pending = Completer<String>();
        var calls = 0;
        await _pumpLinks(tester, [
          _DeferredLink('ספר0', () {
            calls++;
            return pending.future;
          }),
          _DeferredLink('ספר1', () async => 'תוכן1'),
          _DeferredLink('ספר2', () async => 'תוכן אחר'),
        ]);
        await tester.enterText(find.byType(RtlTextField), 'ישן');
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Checkbox));
        await tester.pump();
        await tester.pump();
        expect(calls, 1);
        if (finishOldFirst) {
          pending.complete('ספר');
          await tester.pump();
          await tester.pump();
          await tester.pumpAndSettle();
        }
        await tester.enterText(find.byType(RtlTextField), 'ספר');
        await tester.pumpAndSettle();
        if (!finishOldFirst) {
          pending.complete('ספר');
          await tester.pump();
          await tester.pump();
          await tester.pumpAndSettle();
        }
        expect(find.byType(ExpansionTile), findsNWidgets(3));
        expect(find.byType(SearchResultNavigator), findsOneWidget);
        expect(
          tester
              .widget<SearchResultNavigator>(find.byType(SearchResultNavigator))
              .total,
          3,
        );
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is SmartTextWidget && widget.text.contains('תוכן1'),
          ),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('חיפוש A ישן אינו גובר על חיפוש A חדש אחרי B', (tester) async {
    final pending = Completer<String>();
    var calls = 0;
    await _pumpLinks(tester, [
      _DeferredLink(
        'ספר0',
        () => calls++ == 0 ? pending.future : Future.value('אחר'),
      ),
      _DeferredLink('ספר1 ישן', () async => 'תוכן1'),
      _DeferredLink('ספר2', () async => 'ישן'),
    ]);
    await tester.enterText(find.byType(RtlTextField), 'ישן');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.pump();
    expect(calls, 1);
    await tester.enterText(find.byType(RtlTextField), 'ספר');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(RtlTextField), 'ישן');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SearchResultNavigator>(find.byType(SearchResultNavigator))
          .total,
      2,
    );
    pending.complete('ישן');
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(ExpansionTile), findsNWidgets(2));
    expect(
      tester
          .widget<SearchResultNavigator>(find.byType(SearchResultNavigator))
          .total,
      2,
    );
  });

  testWidgets('השלמת חיפוש אחרי התרוקנות הקישורים אינה מחזירה ניווט ישן', (
    tester,
  ) async {
    final pending = Completer<String>();
    await _pumpLinks(tester, [
      _DeferredLink('ספר0', () => pending.future),
      _DeferredLink('ספר1', () async => 'ישן'),
      _DeferredLink('ספר2', () async => 'ישן'),
    ]);
    await tester.enterText(find.byType(RtlTextField), 'ישן');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.pump();
    await _pumpLinks(tester, const []);
    pending.complete('ישן');
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.byType(SearchResultNavigator), findsNothing);
  });

  testWidgets('ניווט גלוי מתאפס כשהקישורים מתרוקנים', (tester) async {
    await _pump(tester);
    expect(find.byType(SearchResultNavigator), findsOneWidget);
    await _pumpLinks(tester, const []);
    expect(find.byType(SearchResultNavigator), findsNothing);
  });
}
