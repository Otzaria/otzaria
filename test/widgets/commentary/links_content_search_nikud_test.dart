import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/widgets/commentary/links_list_view.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../support/search_engine_test_init.dart';

/// תוכן הקישורים הוא הטקסט המנוקד ביותר בספרייה (פסוקים, משניות, ציטוטים).
/// הסינון חייב להתעלם מניקוד כמו כל שאר משטחי החיפוש באפליקציה.
class _ContentLink extends Link {
  _ContentLink({
    required super.heRef,
    required super.index1,
    required super.path2,
    required super.index2,
    required super.connectionType,
    required this._content,
  });

  final String _content;

  @override
  Future<String> get content => Future.value(_content);

  @override
  Future<String> get displayReference => Future.value(fallbackDisplayReference);
}

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _pump(WidgetTester tester, List<Link> links) async {
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<SettingsBloc>.value(
        value: _FakeSettingsBloc(),
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

/// מקליד שאילתה ומסמן את "חפש גם בתוכן הקישורים".
Future<void> _searchInContent(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(RtlTextField), query);
  await tester.pumpAndSettle();
  await tester.tap(find.byType(Checkbox));
  await tester.pumpAndSettle();
}

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();
  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  group('חיפוש בתוכן הקישורים — ניקוד (issue #1114)', () {
    testWidgets('שאילתה ללא ניקוד מוצאת תוכן מנוקד', (tester) async {
      final links = [
        _ContentLink(
          heRef: 'הפניה לפסוק',
          index1: 5,
          path2: 'בראשית',
          index2: 1,
          connectionType: LinkTypes.quotation,
          content: 'בְּרֵאשִׁית בָּרָא אֱלֹהִים אֵת הַשָּׁמַיִם וְאֵת הָאָרֶץ',
        ),
      ];

      await _pump(tester, links);
      await _searchInContent(tester, 'אלהים');

      expect(
        find.text('לא נמצאו קישורים התואמים לחיפוש'),
        findsNothing,
        reason: 'המילה קיימת בתוכן, רק מנוקדת',
      );
    });

    testWidgets('שאילתה מוצאת תוכן ללא ניקוד (בקרה)', (tester) async {
      final links = [
        _ContentLink(
          heRef: 'הפניה לפסוק',
          index1: 5,
          path2: 'בראשית',
          index2: 1,
          connectionType: LinkTypes.quotation,
          content: 'בראשית ברא אלהים את השמים ואת הארץ',
        ),
      ];

      await _pump(tester, links);
      await _searchInContent(tester, 'אלהים');

      expect(find.text('לא נמצאו קישורים התואמים לחיפוש'), findsNothing);
    });
  });

  group('חיפוש בתוכן הקישורים — HTML', () {
    testWidgets('ישות HTML בין המילים אינה חוסמת ביטוי', (tester) async {
      if (!engineReady) {
        markTestSkipped(searchEngineSkipReason);
        return;
      }
      final links = [
        _ContentLink(
          heRef: 'הפניה',
          index1: 5,
          path2: 'ספר',
          index2: 1,
          connectionType: LinkTypes.quotation,
          content: 'ודר&nbsp;שאל בעניין זה',
        ),
      ];

      await _pump(tester, links);
      await _searchInContent(tester, 'ודר שאל');

      expect(find.text('לא נמצאו קישורים התואמים לחיפוש'), findsNothing);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      final renderedLink = tester.widget<SmartTextWidget>(
        find.byType(SmartTextWidget),
      );
      final highlighted = TextRendererService.processText(
        renderedLink.text,
        renderedLink.settings,
      );
      expect(highlighted, contains('<span style="color: red">ודר</span>'));
      expect(highlighted, contains('<span style="color: red">שאל</span>'));
    });

    testWidgets('תגית inline בתוך הביטוי אינה חוסמת אותו', (tester) async {
      final links = [
        _ContentLink(
          heRef: 'הפניה',
          index1: 5,
          path2: 'ספר',
          index2: 1,
          connectionType: LinkTypes.quotation,
          content: 'אמר <b>רבי</b> יוסי',
        ),
      ];

      await _pump(tester, links);
      await _searchInContent(tester, 'אמר רבי');

      expect(find.text('לא נמצאו קישורים התואמים לחיפוש'), findsNothing);
    });
  });
}
