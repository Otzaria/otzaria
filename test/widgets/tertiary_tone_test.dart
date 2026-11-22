import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/view/plugin_correction_session_banner.dart';
import 'package:otzaria/plugins/view/plugin_settings_screen.dart';
import 'package:otzaria/search/view/layout_fix_suggestion_banner.dart';
import 'package:otzaria/search/view/search_result_source_tag.dart';
import 'package:otzaria/widgets/feedback/app_info_banner.dart';
import 'package:otzaria/widgets/layout/meta_chip.dart';

class _FakeSessions extends PluginCorrectionSessionService {
  _FakeSessions(this.status);

  final PluginCorrectionDraftStatus status;
  var retried = 0;
  String? ended;

  @override
  String? ownerNameForTab(String tabId) => 'מגיה';

  @override
  PluginCorrectionDraftStatus? draftStatusForTab(String tabId) => status;

  @override
  void retryDraftWrites() => retried++;

  @override
  void endByUser(String tabId) => ended = tabId;
}

void main() {
  Widget host(Widget child, {Brightness brightness = Brightness.light}) =>
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.brown,
            brightness: brightness,
          ),
        ),
        home: Scaffold(body: Center(child: child)),
      );

  ColorScheme schemeOf(WidgetTester tester, Finder finder) =>
      Theme.of(tester.element(finder.first)).colorScheme;

  for (final brightness in Brightness.values) {
    group('גוון משלים (${brightness.name})', () {
      testWidgets(
        'MetaChip tertiary: tertiaryContainer על onTertiaryContainer',
        (
          tester,
        ) async {
          await tester.pumpWidget(
            host(
              const MetaChip(label: 'מקור', tone: MetaChipTone.tertiary),
              brightness: brightness,
            ),
          );
          final cs = schemeOf(tester, find.byType(MetaChip));
          final box = tester.widget<DecoratedBox>(
            find.descendant(
              of: find.byType(MetaChip),
              matching: find.byType(DecoratedBox),
            ),
          );
          expect((box.decoration as BoxDecoration).color, cs.tertiaryContainer);
          expect(
            tester.widget<Text>(find.text('מקור')).style?.color,
            cs.onTertiaryContainer,
          );
        },
      );

      testWidgets(
        'AppInfoBanner tertiary: tertiaryContainer על onTertiaryContainer',
        (
          tester,
        ) async {
          await tester.pumpWidget(
            host(
              const AppInfoBanner(
                message: 'הודעה',
                tone: AppInfoBannerTone.tertiary,
              ),
              brightness: brightness,
            ),
          );
          final cs = schemeOf(tester, find.byType(AppInfoBanner));
          final colors = AppInfoBanner.colorsOf(
            tester.element(find.byType(AppInfoBanner)),
            AppInfoBannerTone.tertiary,
          );
          expect(colors.background, cs.tertiaryContainer);
          expect(colors.foreground, cs.onTertiaryContainer);
          expect(colors.icon, cs.onTertiaryContainer);
        },
      );
    });
  }

  testWidgets('תגית המקור בחיפוש היא MetaChip tertiary קטן', (tester) async {
    await tester.pumpWidget(host(const SearchResultSourceTag(label: 'אוצריא')));

    final chip = tester.widget<MetaChip>(find.byType(MetaChip));
    expect(chip.label, 'אוצריא');
    expect(chip.tone, MetaChipTone.tertiary);
    expect(chip.size, MetaChipSize.small);
  });

  testWidgets('תגית "DEV" של תוסף פיתוח היא MetaChip tertiary קטן', (
    tester,
  ) async {
    await tester.pumpWidget(host(const PluginDevBadge()));

    final chip = tester.widget<MetaChip>(find.byType(MetaChip));
    expect(chip.label, 'DEV');
    expect(chip.tone, MetaChipTone.tertiary);
    expect(chip.size, MetaChipSize.small);
  });

  testWidgets('באנר סשן התיקון הוא AppInfoBanner tertiary עם שתי פעולות', (
    tester,
  ) async {
    final sessions = _FakeSessions(PluginCorrectionDraftStatus.failed);
    await tester.pumpWidget(
      host(PluginCorrectionSessionBanner(tabId: 't', service: sessions)),
    );

    final banner = tester.widget<AppInfoBanner>(find.byType(AppInfoBanner));
    expect(banner.tone, AppInfoBannerTone.tertiary);
    expect(
      find.text(PluginCorrectionSessionBanner.modeText('מגיה')),
      findsOneWidget,
    );
    expect(find.text(PluginCorrectionSessionBanner.failedText), findsOneWidget);

    await tester.tap(find.text(PluginCorrectionSessionBanner.retryText));
    await tester.tap(find.text(PluginCorrectionSessionBanner.endText));
    expect(sessions.retried, 1);
    expect(sessions.ended, 't');
  });

  testWidgets('הצעת תיקון הפריסה היא AppInfoBanner tertiary, והלחיצה מחילה', (
    tester,
  ) async {
    String? accepted;
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 600,
          child: LayoutFixSuggestionBanner(
            query: 'akuo',
            onAccept: (value) => accepted = value,
            hint: 'Enter',
          ),
        ),
      ),
    );

    final banner = tester.widget<AppInfoBanner>(find.byType(AppInfoBanner));
    expect(banner.tone, AppInfoBannerTone.tertiary);
    expect(find.textContaining('שלום', findRichText: true), findsOneWidget);

    await tester.tap(find.byType(AppInfoBanner));
    expect(accepted, 'שלום');
  });
}
