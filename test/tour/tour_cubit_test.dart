import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/models/live_tip.dart';
import 'package:otzaria/tour/models/tour_shortcuts.dart';
import 'package:otzaria/tour/models/tour_step.dart';
import 'package:otzaria/tour/models/tour_steps.dart';
import 'package:otzaria/tour/view/tour_overlay_screen.dart';

import '../helpers/memory_settings_cache.dart';

/// לוחות זמנים עם הספים האמיתיים אך השהיה קצרה — לבדיקות מהירות.
const List<DelayedTipSchedule> _fastSchedules = [
  DelayedTipSchedule(
    id: LiveTipId.customFoldersHint,
    minimumLaunchCount: 3,
    delay: Duration(milliseconds: 10),
  ),
  DelayedTipSchedule(
    id: LiveTipId.shortcutsHint,
    minimumLaunchCount: 5,
    delay: Duration(milliseconds: 10),
  ),
  DelayedTipSchedule(
    id: LiveTipId.backupHint,
    minimumLaunchCount: 10,
    delay: Duration(milliseconds: 10),
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  test('בונה סיור מלא עם 19 שלבים כאשר הספרייה טעונה', () {
    final steps = TourSteps.build(libraryLoaded: true);

    expect(steps, hasLength(19));
    expect(steps.first.id, 'welcome');
    expect(steps.last.id, 'finish');
    expect(steps.any((step) => step.id == 'empty_library'), isFalse);
  });

  test('שלבים שהועברו לטיפים חיים אינם חלק מהסיור', () {
    final steps = TourSteps.build(libraryLoaded: true);

    for (final id in [
      'side_by_side',
      'print',
      'backup',
      'shortcuts',
      'calendar',
      'gematria',
      'notes',
    ]) {
      expect(steps.any((step) => step.id == id), isFalse, reason: id);
    }
  });

  test('בונה סיור מקוצר עם שלב ספרייה ריקה כאשר הספרייה אינה טעונה', () {
    final steps = TourSteps.build(libraryLoaded: false);

    expect(steps.first.id, 'welcome');
    expect(steps[1].id, 'empty_library');
    expect(steps.any((step) => step.id == 'library'), isFalse);
    expect(steps.last.title, 'הסיור המקוצר הסתיים');
  });

  testWidgets('מציג קיצורי מקלדת לפי Settings ולא לפי ברירת מחדל קבועה', (
    tester,
  ) async {
    await Settings.setValue<String>(
      'key-shortcut-open-settings',
      'ctrl+comma',
    );
    await Settings.setValue<String>('key-shortcut-open-more', 'alt+m');

    late String navigation;
    late String tools;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          navigation = tourShortcutText(
            context,
            TourShortcutHint.mainNavigation,
          )!;
          tools = tourShortcutText(context, TourShortcutHint.tools)!;
          return const SizedBox.shrink();
        },
      ),
    );

    expect(navigation, contains('הגדרות Ctrl+,'));
    expect(navigation, contains('כלים Alt+M'));
    expect(tools, 'Alt+M');
  });

  testWidgets('תוויות הקיצורים מתורגמות לשפת ההגדרות', (tester) async {
    late String navigation;
    await tester.pumpWidget(
      SettingsTextScope(
        language: SettingsLanguage.english,
        child: Builder(
          builder: (context) {
            navigation = tourShortcutText(
              context,
              TourShortcutHint.mainNavigation,
            )!;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(navigation, contains('Settings Ctrl+,'));
    expect(navigation, isNot(contains('הגדרות')));
  });

  test('TourCubit לא מתחיל אם tour_status כבר נשמר', () async {
    await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);
    final cubit = TourCubit();

    final started = cubit.startIfNeeded(libraryLoaded: true);

    expect(started, isFalse);
    expect(cubit.state.isActive, isFalse);
    await cubit.close();
  });

  test('TourCubit שומר skipped כאשר מדלגים על הסיור', () async {
    final cubit = TourCubit()..start(libraryLoaded: true);

    await cubit.skip();

    expect(cubit.state.isActive, isFalse);
    expect(Settings.getValue<String>(TourSteps.statusKey), TourSteps.skipped);
    await cubit.close();
  });

  test(
    'TourCubit שומר skipped_without_library כאשר מדלגים בלי ספרייה',
    () async {
      final cubit = TourCubit()..start(libraryLoaded: false);

      await cubit.skip();

      expect(cubit.state.isActive, isFalse);
      expect(
        Settings.getValue<String>(TourSteps.statusKey),
        TourSteps.skippedWithoutLibrary,
      );
      await cubit.close();
    },
  );

  test(
    'TourCubit שומר completed_without_library כאשר מסיימים בלי ספרייה',
    () async {
      final cubit = TourCubit()..start(libraryLoaded: false);

      await cubit.complete();

      expect(cubit.state.isActive, isFalse);
      expect(
        Settings.getValue<String>(TourSteps.statusKey),
        TourSteps.completedWithoutLibrary,
      );
      await cubit.close();
    },
  );

  test('TourCubit מציג סיור מלא פעם אחת אחרי סיור מקוצר בלי ספרייה', () async {
    await Settings.setValue<String>(
      TourSteps.statusKey,
      TourSteps.skippedWithoutLibrary,
    );
    final cubit = TourCubit();

    final startedWithoutLibrary = cubit.startIfNeeded(libraryLoaded: false);
    expect(startedWithoutLibrary, isFalse);
    expect(cubit.state.isActive, isFalse);

    final startedWithLibrary = cubit.startIfNeeded(libraryLoaded: true);
    expect(startedWithLibrary, isTrue);
    expect(cubit.state.isActive, isTrue);
    expect(cubit.state.libraryLoaded, isTrue);

    await cubit.skip();
    expect(Settings.getValue<String>(TourSteps.statusKey), TourSteps.skipped);

    final restartedAfterSkip = cubit.startIfNeeded(libraryLoaded: true);
    expect(restartedAfterSkip, isFalse);
    expect(cubit.state.isActive, isFalse);
    await cubit.close();
  });

  test('TourCubit מציג סיור מלא אחרי סיום סיור מקוצר בלי ספרייה', () async {
    await Settings.setValue<String>(
      TourSteps.statusKey,
      TourSteps.completedWithoutLibrary,
    );
    final cubit = TourCubit();

    final started = cubit.startIfNeeded(libraryLoaded: true);

    expect(started, isTrue);
    expect(cubit.state.isActive, isTrue);
    expect(cubit.state.libraryLoaded, isTrue);
    await cubit.complete();
    expect(
      Settings.getValue<String>(TourSteps.statusKey),
      TourSteps.completed,
    );
    await cubit.close();
  });

  test('TourCubit לא מוחק סטטוס קודם בהפעלה ידנית מההגדרות', () async {
    await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);
    final cubit = TourCubit();

    await cubit.restart(libraryLoaded: true);

    expect(cubit.state.isActive, isTrue);
    expect(cubit.state.currentStep?.id, 'restart_welcome');
    expect(Settings.getValue<String>(TourSteps.statusKey), TourSteps.completed);

    await cubit.close();

    final nextSessionCubit = TourCubit();
    final startedNextSession = nextSessionCubit.startIfNeeded(
      libraryLoaded: true,
    );

    expect(startedNextSession, isFalse);
    expect(nextSessionCubit.state.isActive, isFalse);
    expect(Settings.getValue<String>(TourSteps.statusKey), TourSteps.completed);
    await nextSessionCubit.close();
  });

  test('TourCubit מכבה autoplay כאשר קופצים ידנית לשלב אחר', () async {
    final cubit = TourCubit()..start(libraryLoaded: true);

    cubit.toggleAutoPlay();
    expect(cubit.state.isAutoPlaying, isTrue);

    cubit.goToStep(1);

    expect(cubit.state.currentIndex, 1);
    expect(cubit.state.isAutoPlaying, isFalse);
    await cubit.close();
  });

  test('TourCubit מאפס autoplay כאשר מתחילים סיור מחדש', () async {
    final cubit = TourCubit()..start(libraryLoaded: true);

    cubit.toggleAutoPlay();
    expect(cubit.state.isAutoPlaying, isTrue);

    cubit.start(libraryLoaded: true);

    expect(cubit.state.currentIndex, 0);
    expect(cubit.state.isAutoPlaying, isFalse);
    await cubit.close();
  });

  test('TourCubit מציג טיפ מילון אחרי שתי בחירות טקסט', () async {
    await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);
    final cubit = TourCubit();

    await cubit.recordInteraction(
      TourInteraction(type: TourInteractionType.textSelected),
    );
    await cubit.recordInteraction(
      TourInteraction(type: TourInteractionType.textSelected),
    );

    expect(
      cubit.state.activeLiveTipId,
      LiveTipId.dictionaryContextMenuHint,
    );

    cubit.dismissLiveTip();
    await cubit.recordInteraction(
      TourInteraction(type: TourInteractionType.dictionaryUsed),
    );

    expect(
      cubit.state.resolvedTips,
      contains(LiveTipId.dictionaryContextMenuHint),
    );
    await cubit.close();
  });

  test('TourCubit לא מציג שוב טיפ מילון אחרי שהמשתמש סגר אותו', () async {
    await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);
    final cubit = TourCubit();

    await cubit.recordInteraction(
      TourInteraction(
        type: TourInteractionType.textSelected,
        primaryValue: 'בראשית',
      ),
    );
    await cubit.recordInteraction(
      TourInteraction(
        type: TourInteractionType.textSelected,
        primaryValue: 'בראשית',
      ),
    );
    expect(
      cubit.state.activeLiveTipId,
      LiveTipId.dictionaryContextMenuHint,
    );

    cubit.dismissLiveTip();
    await cubit.recordInteraction(
      TourInteraction(
        type: TourInteractionType.textSelected,
        primaryValue: 'שמות',
      ),
    );
    await cubit.recordInteraction(
      TourInteraction(
        type: TourInteractionType.textSelected,
        primaryValue: 'שמות',
      ),
    );

    expect(cubit.state.activeLiveTipId, isNull);
    await cubit.close();
  });

  test('TourCubit רושם הזדמנות למפרשים פעם אחת בלבד לכל המופע', () async {
    await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);
    final cubit = TourCubit();

    await cubit.recordInteraction(
      TourInteraction(
        type: TourInteractionType.commentaryAvailable,
        primaryValue: 'בראשית',
      ),
    );
    expect(cubit.hasRegisteredCommentaryOpportunity, isTrue);

    await cubit.recordInteraction(
      TourInteraction(
        type: TourInteractionType.textSelected,
        primaryValue: 'בראשית',
      ),
    );
    await cubit.recordInteraction(
      TourInteraction(
        type: TourInteractionType.commentaryAvailable,
        primaryValue: 'שמות',
      ),
    );
    await cubit.recordInteraction(
      TourInteraction(
        type: TourInteractionType.currentTabChanged,
        primaryValue: 'שמות',
      ),
    );

    expect(cubit.state.activeLiveTipId, isNull);

    await cubit.recordInteraction(
      TourInteraction(
        type: TourInteractionType.openedTextBook,
        primaryValue: 'בראשית',
      ),
    );
    await cubit.recordInteraction(
      TourInteraction(
        type: TourInteractionType.currentTabChanged,
        primaryValue: 'בראשית',
      ),
    );

    expect(cubit.state.activeLiveTipId, LiveTipId.commentaryHint);
    await cubit.close();
  });

  test('TourCubit מציג טיפ מפרשים גם אחרי ניווט בתוך PDF', () async {
    await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);
    final cubit = TourCubit();

    await cubit.recordInteraction(
      TourInteraction(
        type: TourInteractionType.commentaryAvailable,
        primaryValue: 'בראשית',
      ),
    );
    await cubit.recordInteraction(
      TourInteraction(
        type: TourInteractionType.readerPositionChanged,
        primaryValue: 'בראשית',
      ),
    );
    await cubit.recordInteraction(
      TourInteraction(
        type: TourInteractionType.readerPositionChanged,
        primaryValue: 'בראשית',
      ),
    );
    await cubit.recordInteraction(
      TourInteraction(
        type: TourInteractionType.readerPositionChanged,
        primaryValue: 'בראשית',
      ),
    );

    expect(cubit.state.activeLiveTipId, LiveTipId.commentaryHint);
    await cubit.close();
  });

  test('TourCubit שומר resolvedTips באתחול חוזר של הסיור באותה ריצה', () async {
    await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);
    final cubit = TourCubit();

    await cubit.recordInteraction(
      TourInteraction(type: TourInteractionType.textSelected),
    );
    await cubit.recordInteraction(
      TourInteraction(type: TourInteractionType.textSelected),
    );
    expect(
      cubit.state.activeLiveTipId,
      LiveTipId.dictionaryContextMenuHint,
    );
    cubit.dismissLiveTip();
    expect(
      cubit.state.resolvedTips,
      contains(LiveTipId.dictionaryContextMenuHint),
    );

    await cubit.restart(libraryLoaded: true);
    expect(
      cubit.state.resolvedTips,
      contains(LiveTipId.dictionaryContextMenuHint),
    );

    await cubit.complete();
    await cubit.recordInteraction(
      TourInteraction(type: TourInteractionType.textSelected),
    );
    await cubit.recordInteraction(
      TourInteraction(type: TourInteractionType.textSelected),
    );
    expect(cubit.state.activeLiveTipId, isNull);

    await cubit.close();
  });

  test(
    'TourCubit חדש טוען resolvedTips מ-Settings ולא מציג שוב טיפ שנסגרה',
    () async {
      await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);
      final firstCubit = TourCubit();
      await firstCubit.recordInteraction(
        TourInteraction(type: TourInteractionType.textSelected),
      );
      await firstCubit.recordInteraction(
        TourInteraction(type: TourInteractionType.textSelected),
      );
      firstCubit.dismissLiveTip();
      await firstCubit.close();

      final secondCubit = TourCubit();
      expect(
        secondCubit.state.resolvedTips,
        contains(LiveTipId.dictionaryContextMenuHint),
      );

      await secondCubit.recordInteraction(
        TourInteraction(type: TourInteractionType.textSelected),
      );
      await secondCubit.recordInteraction(
        TourInteraction(type: TourInteractionType.textSelected),
      );
      expect(secondCubit.state.activeLiveTipId, isNull);

      await secondCubit.close();
    },
  );

  test('TourCubit מציג טיפ הצג לצד אחרי דילוג חוזר בין שני ספרים', () async {
    await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);
    final cubit = TourCubit();

    for (final title in ['בראשית', 'שמות', 'בראשית', 'שמות', 'בראשית']) {
      await cubit.recordInteraction(
        TourInteraction(
          type: TourInteractionType.currentTabChanged,
          primaryValue: title,
        ),
      );
    }

    expect(
      cubit.state.activeLiveTipId,
      LiveTipId.sideBySideSuggestion,
    );
    await cubit.close();
  });

  test(
    'טיפ התיקיות המותאמות מופיע אחרי ההפעלה השלישית וכמה דקות שימוש',
    () async {
      await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);

      // שתי ההפעלות הראשונות אינן מתזמנות את הטיפ
      for (var i = 0; i < 2; i++) {
        final cubit = TourCubit(delayedTipSchedules: _fastSchedules);
        cubit.registerSession();
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(cubit.state.activeLiveTipId, isNull);
        await cubit.close();
      }

      final cubit = TourCubit(delayedTipSchedules: _fastSchedules);
      cubit.registerSession();
      expect(
        cubit.state.activeLiveTipId,
        isNull,
        reason: 'לפני שחלף זמן השימוש',
      );

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(cubit.state.activeLiveTipId, LiveTipId.customFoldersHint);
      await cubit.close();
    },
  );

  test('אם ההפעלה השלישית הייתה קצרה, הטיפ מופיע בהפעלה הרביעית', () async {
    await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);

    for (var i = 0; i < 2; i++) {
      final warmup = TourCubit()..registerSession();
      await warmup.close();
    }

    // הפעלה שלישית קצרה — נסגרת לפני שהטיימר יורה
    final shortSession = TourCubit(
      delayedTipSchedules: const [
        DelayedTipSchedule(
          id: LiveTipId.customFoldersHint,
          minimumLaunchCount: 3,
          delay: Duration(seconds: 30),
        ),
      ],
    );
    shortSession.registerSession();
    await shortSession.close();
    expect(shortSession.state.activeLiveTipId, isNull);

    final nextSession = TourCubit(delayedTipSchedules: _fastSchedules);
    nextSession.registerSession();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(nextSession.state.activeLiveTipId, LiveTipId.customFoldersHint);
    await nextSession.close();
  });

  test('לאחר סגירת טיפ התיקיות הוא אינו חוזר בהפעלה הבאה', () async {
    await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);

    const singleLaunchSchedules = [
      DelayedTipSchedule(
        id: LiveTipId.customFoldersHint,
        minimumLaunchCount: 1,
        delay: Duration(milliseconds: 10),
      ),
    ];

    final first = TourCubit(delayedTipSchedules: singleLaunchSchedules);
    first.registerSession();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(first.state.activeLiveTipId, LiveTipId.customFoldersHint);
    first.dismissLiveTip();
    expect(first.state.resolvedTips, contains(LiveTipId.customFoldersHint));
    await first.close();

    final second = TourCubit(delayedTipSchedules: singleLaunchSchedules);
    second.registerSession();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(second.state.activeLiveTipId, isNull);
    await second.close();
  });

  test('טיפ הקיצורים מתוזמן מההפעלה החמישית כשטיפ התיקיות כבר נפתר', () async {
    await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);
    await Settings.setValue<int>(LiveTipStorage.launchCountKey, 4);
    await Settings.setValue<String>(
      LiveTipStorage.resolvedTipsKey,
      LiveTipStorage.encode({LiveTipId.customFoldersHint}),
    );

    final cubit = TourCubit(delayedTipSchedules: _fastSchedules);
    cubit.registerSession(); // הפעלה חמישית
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(cubit.state.activeLiveTipId, LiveTipId.shortcutsHint);
    await cubit.close();
  });

  test('כשכמה טיפים מתוזמנים זכאים — מוצג רק הראשון לפי סדר העדיפות', () async {
    await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);
    await Settings.setValue<int>(LiveTipStorage.launchCountKey, 9);

    final cubit = TourCubit(delayedTipSchedules: _fastSchedules);
    cubit.registerSession(); // הפעלה עשירית — כל השלושה זכאים
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(cubit.state.activeLiveTipId, LiveTipId.customFoldersHint);
    await cubit.close();
  });

  test('טיפ הגיבוי מתוזמן מההפעלה העשירית כשהקודמים נפתרו', () async {
    await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);
    await Settings.setValue<int>(LiveTipStorage.launchCountKey, 9);
    await Settings.setValue<String>(
      LiveTipStorage.resolvedTipsKey,
      LiveTipStorage.encode({
        LiveTipId.customFoldersHint,
        LiveTipId.shortcutsHint,
      }),
    );

    final cubit = TourCubit(delayedTipSchedules: _fastSchedules);
    cubit.registerSession();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(cubit.state.activeLiveTipId, LiveTipId.backupHint);
    await cubit.close();
  });

  test('פתיחת טאב הקיצורים פותרת את טיפ הקיצורים', () async {
    await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);
    final cubit = TourCubit();

    await cubit.recordInteraction(
      TourInteraction(type: TourInteractionType.shortcutsSettingsOpened),
    );

    expect(cubit.state.resolvedTips, contains(LiveTipId.shortcutsHint));
    await cubit.close();
  });

  test('פתיחת טאב המערכת פותרת את טיפ הגיבוי', () async {
    await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);
    final cubit = TourCubit();

    await cubit.recordInteraction(
      TourInteraction(type: TourInteractionType.systemSettingsOpened),
    );

    expect(cubit.state.resolvedTips, contains(LiveTipId.backupHint));
    await cubit.close();
  });

  test('טיפ ההדפסה מוצג אחרי פתיחת ספר מההפעלה השביעית', () async {
    await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);
    await Settings.setValue<int>(LiveTipStorage.launchCountKey, 7);
    final cubit = TourCubit(printHintMinimumSessionDuration: Duration.zero);

    await cubit.recordInteraction(
      TourInteraction(
        type: TourInteractionType.openedTextBook,
        primaryValue: 'בראשית',
      ),
    );

    expect(cubit.state.activeLiveTipId, LiveTipId.printHint);
    await cubit.close();
  });

  test('טיפ ההדפסה אינו מוצג לפני ההפעלה השביעית', () async {
    await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);
    await Settings.setValue<int>(LiveTipStorage.launchCountKey, 6);
    final cubit = TourCubit(printHintMinimumSessionDuration: Duration.zero);

    await cubit.recordInteraction(
      TourInteraction(
        type: TourInteractionType.openedTextBook,
        primaryValue: 'בראשית',
      ),
    );

    expect(cubit.state.activeLiveTipId, isNull);
    await cubit.close();
  });

  test('טיפ ההדפסה ממתין לזמן שימוש מינימלי בסשן', () async {
    await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);
    await Settings.setValue<int>(LiveTipStorage.launchCountKey, 7);
    final cubit = TourCubit(
      printHintMinimumSessionDuration: const Duration(minutes: 5),
    );

    await cubit.recordInteraction(
      TourInteraction(
        type: TourInteractionType.openedTextBook,
        primaryValue: 'בראשית',
      ),
    );

    expect(cubit.state.activeLiveTipId, isNull);
    await cubit.close();
  });

  test('הדפסה פותרת את טיפ ההדפסה כך שלא יוצג', () async {
    await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);
    await Settings.setValue<int>(LiveTipStorage.launchCountKey, 7);
    final cubit = TourCubit(printHintMinimumSessionDuration: Duration.zero);

    await cubit.recordInteraction(
      TourInteraction(type: TourInteractionType.printUsed),
    );
    expect(cubit.state.resolvedTips, contains(LiveTipId.printHint));

    await cubit.recordInteraction(
      TourInteraction(
        type: TourInteractionType.openedTextBook,
        primaryValue: 'בראשית',
      ),
    );

    expect(cubit.state.activeLiveTipId, isNull);
    await cubit.close();
  });

  test('טיפ אחד לכל היותר בסשן — טיפ נוסף נדחה להפעלה הבאה', () async {
    await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);
    await Settings.setValue<int>(LiveTipStorage.launchCountKey, 7);
    final cubit = TourCubit(printHintMinimumSessionDuration: Duration.zero);

    await cubit.recordInteraction(
      TourInteraction(type: TourInteractionType.textSelected),
    );
    await cubit.recordInteraction(
      TourInteraction(type: TourInteractionType.textSelected),
    );
    expect(cubit.state.activeLiveTipId, LiveTipId.dictionaryContextMenuHint);
    cubit.dismissLiveTip();

    // תנאי טיפ ההדפסה מתקיים, אבל כבר הוצג טיפ בסשן הזה
    await cubit.recordInteraction(
      TourInteraction(
        type: TourInteractionType.openedTextBook,
        primaryValue: 'בראשית',
      ),
    );

    expect(cubit.state.activeLiveTipId, isNull);
    await cubit.close();
  });

  test('TourCubit מציג טיפ אודות הספר אחרי פתיחת שלושה ספרים שונים', () async {
    await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);
    await Settings.setValue<int>(LiveTipStorage.launchCountKey, 3);
    final cubit = TourCubit();

    for (final title in ['בראשית', 'שמות', 'ויקרא']) {
      await cubit.recordInteraction(
        TourInteraction(
          type: TourInteractionType.openedTextBook,
          primaryValue: title,
        ),
      );
    }

    expect(cubit.state.activeLiveTipId, LiveTipId.bookSourceHint);
    await cubit.close();
  });

  test('TourCubit אינו מציג טיפ אודות הספר בהפעלות הראשונות', () async {
    await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);
    await Settings.setValue<int>(LiveTipStorage.launchCountKey, 2);
    final cubit = TourCubit();

    for (final title in ['בראשית', 'שמות', 'ויקרא']) {
      await cubit.recordInteraction(
        TourInteraction(
          type: TourInteractionType.openedTextBook,
          primaryValue: title,
        ),
      );
    }

    expect(cubit.state.activeLiveTipId, isNull);
    await cubit.close();
  });

  test(
    'TourCubit אינו מציג טיפ אודות הספר על אותו ספר שנפתח שוב ושוב',
    () async {
      await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);
      await Settings.setValue<int>(LiveTipStorage.launchCountKey, 3);
      final cubit = TourCubit();

      for (var i = 0; i < 3; i++) {
        await cubit.recordInteraction(
          TourInteraction(
            type: TourInteractionType.openedTextBook,
            primaryValue: 'בראשית',
          ),
        );
      }

      expect(cubit.state.activeLiveTipId, isNull);
      await cubit.close();
    },
  );

  test('TourCubit פותר את טיפ אודות הספר כאשר נצפה מקור הספר', () async {
    await Settings.setValue<String>(TourSteps.statusKey, TourSteps.completed);
    await Settings.setValue<int>(LiveTipStorage.launchCountKey, 3);
    final cubit = TourCubit();

    await cubit.recordInteraction(
      TourInteraction(type: TourInteractionType.bookSourceViewed),
    );
    expect(cubit.state.resolvedTips, contains(LiveTipId.bookSourceHint));

    for (final title in ['בראשית', 'שמות', 'ויקרא']) {
      await cubit.recordInteraction(
        TourInteraction(
          type: TourInteractionType.openedTextBook,
          primaryValue: title,
        ),
      );
    }

    expect(cubit.state.activeLiveTipId, isNull);
    await cubit.close();
  });

  test('Spotlight של הניווט מוצג בצד ימין בממשק RTL', () {
    final rect = tourTargetRectFor(
      TourSpotlightArea.navigation,
      const Size(1200, 800),
      TextDirection.rtl,
    );

    expect(rect.left, 1122);
    expect(rect.right, 1200);
    expect(rect.bottom, 798);
  });

  test('Spotlight של הניווט מוצג בצד שמאל בממשק LTR', () {
    final rect = tourTargetRectFor(
      TourSpotlightArea.navigation,
      const Size(1200, 800),
      TextDirection.ltr,
    );

    expect(rect.left, 0);
    expect(rect.right, 78);
    expect(rect.bottom, 798);
  });

  test('Spotlight של מסך מלא ב-RTL כולל את אזור התוכן עד סרגל הניווט', () {
    final rect = tourTargetRectFor(
      TourSpotlightArea.fullScreen,
      const Size(1200, 800),
      TextDirection.rtl,
    );

    expect(rect.left, 8);
    expect(rect.top, 38);
    expect(rect.right, 1126);
    expect(rect.bottom, 792);
  });

  test('Spotlight של מסך מלא ב-LTR מתחיל אחרי סרגל הניווט', () {
    final rect = tourTargetRectFor(
      TourSpotlightArea.fullScreen,
      const Size(1200, 800),
      TextDirection.ltr,
    );

    expect(rect.left, 74);
    expect(rect.top, 38);
    expect(rect.right, 1192);
    expect(rect.bottom, 792);
  });

  test('Spotlight של חיפוש הספרייה יושב על שורת החיפוש ולא נמוך מדי', () {
    final rect = tourTargetRectFor(
      TourSpotlightArea.librarySearch,
      const Size(1200, 800),
      TextDirection.rtl,
    );

    expect(rect.top, 40);
    expect(rect.bottom, 92);
    expect(rect.left, 112);
    expect(rect.right, 1090);
  });

  test('Spotlight של קטגוריות הספרייה מכסה את גריד הכרטיסים ב-RTL', () {
    final rect = tourTargetRectFor(
      TourSpotlightArea.libraryCategories,
      const Size(1200, 800),
      TextDirection.rtl,
    );

    expect(rect.left, 444);
    expect(rect.top, 96);
    expect(rect.right, 1126);
    expect(rect.bottom, 758);
  });

  test('Spotlight של פתיחת ספר מוצג על כרטיס ספר בגריד הימני', () {
    final rect = tourTargetRectFor(
      TourSpotlightArea.bookCard,
      const Size(1200, 800),
      TextDirection.rtl,
    );

    expect(rect.left, 744);
    expect(rect.top, 116);
    expect(rect.right, 1080);
    expect(rect.bottom, 250);
  });

  test('Spotlight של טאבים יושב על שורת הטאבים ולא על סרגל הספר', () {
    final rect = tourTargetRectFor(
      TourSpotlightArea.tabs,
      const Size(1200, 800),
      TextDirection.rtl,
    );

    expect(rect.left, 468);
    expect(rect.top, 8);
    expect(rect.right, 732);
    expect(rect.bottom, 44);
  });

  test('TourOverlayScreen מכבה אנימציה ביציאה מהפתיחה ובכניסה לסיום', () {
    expect(
      tourCardSwitchDurationFor(
        fromStepId: 'welcome',
        toStepId: 'navigation',
      ),
      Duration.zero,
    );
    expect(
      tourCardSwitchDurationFor(
        fromStepId: 'restart_welcome',
        toStepId: 'navigation',
      ),
      Duration.zero,
    );
    expect(
      tourCardSwitchDurationFor(
        fromStepId: 'appearance',
        toStepId: 'finish',
      ),
      Duration.zero,
    );
    expect(
      tourCardSwitchDurationFor(
        fromStepId: 'navigation',
        toStepId: 'library',
      ),
      tourCardSwitchDuration,
    );
  });

  test('TourOverlayScreen מעגן כרטיסים לתחתית בזמן אנימציית החלפה', () {
    final layout = tourCardSwitcherLayoutBuilder(
      const SizedBox(key: ValueKey('current')),
      const [SizedBox(key: ValueKey('previous'))],
    );

    expect(layout, isA<Stack>());

    final stack = layout as Stack;
    expect(stack.alignment, AlignmentDirectional.bottomStart);
    expect(stack.children, hasLength(2));
    expect(stack.children.first.key, const ValueKey('previous'));
    expect(stack.children.last.key, const ValueKey('current'));
  });

  testWidgets('TourOverlayScreen מודד מחדש יעד שמשתנה אחרי frame', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = TourCubit()..start(libraryLoaded: true);
    cubit.goToStep(cubit.state.steps.length - 1);
    var resolveCalls = 0;
    final resolvedLeftValues = <double>[];

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: Stack(
            children: [
              TourOverlayScreen(
                onStepChanged: (_) {},
                targetRectResolver: (_) {
                  resolveCalls++;
                  final left = resolveCalls == 1 ? 24.0 : 84.0;
                  resolvedLeftValues.add(left);
                  return Rect.fromLTWH(left, 40, 120, 48);
                },
              ),
            ],
          ),
        ),
      ),
    );
    expect(resolvedLeftValues, [24]);

    await tester.pump();

    expect(resolveCalls, greaterThan(1));
    expect(resolvedLeftValues.last, 84);

    await cubit.close();
  });

  testWidgets('כרטיס הסיור מוצג באנגלית, כולל הקיצור שבתוך הגוף', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await Settings.setValue<String>('key-shortcut-open-more', 'alt+m');

    final cubit = TourCubit()..start(libraryLoaded: true);
    cubit.goToStep(
      cubit.state.steps.indexWhere((step) => step.id == 'tools'),
    );

    await tester.pumpWidget(
      MaterialApp(
        // גופן הבדיקות רחב-קבוע ושורת הכפתורים נשפכת בו בשתי השפות. הקטנת
        // הסקאלה בודקת את הטקסט בלי להיתלות בפריסה שאינה מציאותית.
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(0.5)),
          child: SettingsTextScope(
            language: SettingsLanguage.english,
            child: BlocProvider.value(
              value: cubit,
              child: Stack(
                children: [
                  TourOverlayScreen(
                    onStepChanged: (_) {},
                    targetRectResolver: (_) =>
                        const Rect.fromLTWH(24, 40, 120, 48),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('More tools'), findsOneWidget);
    expect(find.textContaining('Shortcut: Alt+M'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.textContaining('{shortcut}'), findsNothing);

    await cubit.close();
  });

  test('טיפ חי מוצג מעל היעד כאשר אין מקום מתחתיו', () {
    final offset = liveTipCardOffsetFor(
      overlaySize: const Size(620, 500),
      targetRect: const Rect.fromLTWH(500, 430, 64, 48),
      cardSize: const Size(360, 210),
    );

    expect(offset.dy, 208);
    expect(offset.dy + 210, lessThanOrEqualTo(484));
  });
}
