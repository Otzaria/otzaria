import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/tabs/text_display_settings_section.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' show HolyNameStyle;
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _PolicySettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _PolicySettingsBloc(TextDisplayPolicy policy)
    : super(SettingsState.initial().copyWith(textDisplayPolicy: policy)) {
    on<UpdateTextDisplayPolicy>(
      (event, emit) =>
          emit(state.copyWith(textDisplayPolicy: event.textDisplayPolicy)),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _pageShapeCommentaryCopy = TextDisplaySlot(
  target: TextTarget.commentary,
  view: TextView.pageShape,
  channel: TextChannel.copy,
);

Finder _caseSection(String bookClass, TextDisplaySlot slot) =>
    find.byKey(ValueKey('text-display-case-$bookClass:${slot.key}'));

Finder _inSection(Finder section, String text) =>
    find.descendant(of: section, matching: find.text(text));

void main() {
  setUpAll(() => Settings.init(cacheProvider: MemoryCacheProvider()));

  Future<_PolicySettingsBloc> pumpCard(
    WidgetTester tester,
    TextDisplayPolicy policy,
  ) async {
    final bloc = _PolicySettingsBloc(policy);
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1400, 900)),
          child: Scaffold(
            body: BlocProvider<SettingsBloc>.value(
              value: bloc,
              child: const SingleChildScrollView(
                child: TextDisplaySettingsCard(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('התאמות נוספות'));
    await tester.pumpAndSettle();
    return bloc;
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('מציג את חמשת המצבים, כולם יורשים מהתצוגה', (tester) async {
    await pumpCard(tester, TextDisplayPolicy.empty);

    for (final title in [
      'במפרשים',
      'בהעתקה',
      'בייצוא ובהדפסה',
      'בצורת הדף',
      'בתנ"ך',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('כמו בתצוגה'), findsNWidgets(5));
    expect(find.text('התאמות מתקדמות שהוגדרו'), findsNothing);
    expect(find.text('הגדרות נפרדות'), findsNothing);
  });

  testWidgets(
    'שינוי ניקוד "במפרשים" כותב את השדה הזה בלבד, וחזרה לברירת המחדל מסירה אותו',
    (tester) async {
      final bloc = await pumpCard(tester, TextDisplayPolicy.empty);
      final section = _caseSection(
        'general',
        TextDisplaySlot.commentaryDisplay,
      );

      await tapVisible(tester, _inSection(section, 'במפרשים'));
      // שורת הציונים מוצגת גם בעורך המפרשים (#2372).
      expect(_inSection(section, 'ציוני המפרשים'), findsOneWidget);

      // "הסתר" הראשון בעורך שייך לשורת הניקוד.
      await tapVisible(tester, _inSection(section, 'הסתר').first);

      expect(
        bloc.state.textDisplayPolicy.general.patchFor(
          TextDisplaySlot.commentaryDisplay,
        ),
        const TextDisplayPatch(nikud: MarkVisibility.hide),
      );
      expect(_inSection(section, 'ניקוד: הסתר'), findsOneWidget);

      await tapVisible(tester, _inSection(section, 'חזור לברירת המחדל'));

      expect(
        bloc.state.textDisplayPolicy.general.patchFor(
          TextDisplaySlot.commentaryDisplay,
        ),
        TextDisplayPatch.empty,
      );
      expect(_inSection(section, 'כמו בתצוגה'), findsOneWidget);
    },
  );

  testWidgets('צירוף מתקדם קיים מופיע ברשימה ונמחק', (tester) async {
    final bloc = await pumpCard(
      tester,
      TextDisplayPolicy(
        general: TextDisplayLayer({
          _pageShapeCommentaryCopy: const TextDisplayPatch(
            punctuation: MarkVisibility.hide,
            holyName: HolyNameDisplay.asIs,
          ),
        }),
        tanach: TextDisplayLayer.empty,
      ),
    );
    final section = _caseSection('general', _pageShapeCommentaryCopy);

    expect(find.text('התאמות מתקדמות שהוגדרו'), findsOneWidget);
    expect(_inSection(section, 'מפרשים · צורת הדף · העתקה'), findsOneWidget);
    expect(
      _inSection(section, 'סימני פיסוק: הסתר · שם הוי"ה: ככתבו'),
      findsOneWidget,
    );

    await tapVisible(
      tester,
      find.descendant(of: section, matching: find.byTooltip('מחק התאמה')),
    );

    expect(bloc.state.textDisplayPolicy, TextDisplayPolicy.empty);
    expect(find.text('התאמות מתקדמות שהוגדרו'), findsNothing);
  });

  testWidgets('הבורר המתקדם מראה ממי הצירוף יורש בפועל', (tester) async {
    await pumpCard(
      tester,
      TextDisplayPolicy(
        general: TextDisplayLayer({
          TextDisplaySlot.commentaryDisplay: const TextDisplayPatch(
            nikud: MarkVisibility.hide,
          ),
        }),
        tanach: TextDisplayLayer.empty,
      ),
    );

    await tapVisible(tester, find.text('התאמה מתקדמת...'));
    await tapVisible(tester, find.text('מפרשים').last);
    await tapVisible(tester, find.text('העתקה').last);

    expect(find.text('כמו במפרשים'), findsOneWidget);
  });

  testWidgets('עריכה במצב בעל שם ממזגת לטלאי הקיים ולא דורסת שדות', (
    tester,
  ) async {
    final bloc = await pumpCard(
      tester,
      TextDisplayPolicy(
        general: TextDisplayLayer({
          TextDisplaySlot.commentaryDisplay: const TextDisplayPatch(
            punctuation: MarkVisibility.hide,
          ),
        }),
        tanach: TextDisplayLayer.empty,
      ),
    );
    final section = _caseSection('general', TextDisplaySlot.commentaryDisplay);

    await tapVisible(tester, _inSection(section, 'במפרשים'));
    await tapVisible(tester, _inSection(section, 'הסתר').first);

    expect(
      bloc.state.textDisplayPolicy.general.patchFor(
        TextDisplaySlot.commentaryDisplay,
      ),
      const TextDisplayPatch(
        nikud: MarkVisibility.hide,
        punctuation: MarkVisibility.hide,
      ),
    );
  });

  testWidgets('מדיניות ממפתחות ישנים: החרגות התנ"ך מוצגות ונשמרות באיפוס', (
    tester,
  ) async {
    final legacy = TextDisplayPolicy.fromLegacy(
      defaultRemoveNikud: true,
      removeNikudFromTanach: false,
      defaultRemovePunctuation: true,
      showTeamim: true,
      replaceHolyNames: false,
      holyNameStyle: HolyNameStyle.kufKuf,
    );
    final bloc = await pumpCard(tester, legacy);

    expect(
      _inSection(
        _caseSection('tanach', TextDisplaySlot.root),
        'ניקוד: הצג · סימני פיסוק: הצג',
      ),
      findsOneWidget,
    );
    final tanachCommentary = _caseSection(
      'tanach',
      TextDisplaySlot.commentaryDisplay,
    );
    expect(_inSection(tanachCommentary, 'תנ"ך · מפרשים'), findsOneWidget);
    expect(
      _inSection(tanachCommentary, 'ניקוד: הסתר · סימני פיסוק: הסתר'),
      findsOneWidget,
    );

    await tapVisible(tester, find.text('איפוס כל ההתאמות הנוספות'));

    expect(bloc.state.textDisplayPolicy.tanach.isEmpty, isTrue);
    expect(
      bloc.state.textDisplayPolicy.general.patches.keys,
      [TextDisplaySlot.root],
    );
    expect(
      bloc.state.textDisplayPolicy.resolve(TextDisplaySlot.root),
      legacy.resolve(TextDisplaySlot.root),
    );
  });

  testWidgets('הסיכום כולל טעמים "כמו הניקוד" ושם הוי"ה', (tester) async {
    await pumpCard(
      tester,
      TextDisplayPolicy(
        general: TextDisplayLayer({
          TextDisplaySlot.commentaryDisplay: const TextDisplayPatch(
            teamim: TeamimVisibility.followNikud,
            holyName: HolyNameDisplay.hehApostrophe,
          ),
        }),
        tanach: TextDisplayLayer.empty,
      ),
    );

    expect(
      _inSection(
        _caseSection('general', TextDisplaySlot.commentaryDisplay),
        'טעמי המקרא: כמו הניקוד · שם הוי"ה: ה\'',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'מפרשי תנ"ך יורשים קודם מ"במפרשים" הכללי ולא מ"בתנ"ך", והעריכה נכתבת לשכבת התנ"ך',
    (tester) async {
      final bloc = await pumpCard(
        tester,
        TextDisplayPolicy(
          general: TextDisplayLayer({
            TextDisplaySlot.commentaryDisplay: const TextDisplayPatch(
              nikud: MarkVisibility.hide,
            ),
          }),
          tanach: TextDisplayLayer({
            TextDisplaySlot.root: const TextDisplayPatch(
              nikud: MarkVisibility.show,
            ),
          }),
        ),
      );

      await tapVisible(tester, find.text('התאמה מתקדמת...'));
      await tapVisible(tester, find.text('תנ"ך').last);
      await tapVisible(tester, find.text('מפרשים').last);

      expect(find.text('כמו במפרשים'), findsOneWidget);

      // הפרופיל הפתור לחריץ הוא "הסתר" (מהמפרשים הכלליים); "הצג" נכתב כסטייה.
      final picker = find.ancestor(
        of: find.text('התאמה מתקדמת...'),
        matching: find.byType(ExpandableSection),
      );
      await tapVisible(
        tester,
        find.descendant(of: picker, matching: find.text('הצג')).first,
      );

      final policy = bloc.state.textDisplayPolicy;
      expect(
        policy.tanach.patchFor(TextDisplaySlot.commentaryDisplay),
        const TextDisplayPatch(nikud: MarkVisibility.show),
      );
      expect(
        policy.general.patchFor(TextDisplaySlot.commentaryDisplay),
        const TextDisplayPatch(nikud: MarkVisibility.hide),
      );
    },
  );

  testWidgets('עורך "בתנ"ך" מציג את הערך הפתור לתנ"ך ומשנה אותו', (
    tester,
  ) async {
    final bloc = await pumpCard(
      tester,
      TextDisplayPolicy(
        general: TextDisplayLayer({
          TextDisplaySlot.root: const TextDisplayPatch(
            nikud: MarkVisibility.hide,
          ),
        }),
        tanach: TextDisplayLayer({
          TextDisplaySlot.root: const TextDisplayPatch(
            nikud: MarkVisibility.show,
            holyName: HolyNameDisplay.kufKuf,
          ),
        }),
      ),
    );
    final section = _caseSection('tanach', TextDisplaySlot.root);

    await tapVisible(tester, _inSection(section, 'בתנ"ך'));
    await tapVisible(tester, _inSection(section, 'הסתר').first);

    expect(
      bloc.state.textDisplayPolicy.tanach.patchFor(TextDisplaySlot.root),
      const TextDisplayPatch(
        nikud: MarkVisibility.hide,
        holyName: HolyNameDisplay.kufKuf,
      ),
    );
  });
}
