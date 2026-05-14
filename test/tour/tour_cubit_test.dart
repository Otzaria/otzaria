import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/models/live_tip.dart';
import 'package:otzaria/tour/models/tour_step.dart';
import 'package:otzaria/tour/models/tour_steps.dart';
import 'package:otzaria/tour/view/tour_overlay_screen.dart';

import '../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  test('בונה סיור מלא עם 26 שלבים כאשר הספרייה טעונה', () {
    final steps = TourSteps.build(libraryLoaded: true);

    expect(steps, hasLength(26));
    expect(steps.first.id, 'welcome');
    expect(steps.last.id, 'finish');
    expect(steps.any((step) => step.id == 'empty_library'), isFalse);
  });

  test('בונה סיור מקוצר עם שלב ספרייה ריקה כאשר הספרייה אינה טעונה', () {
    final steps = TourSteps.build(libraryLoaded: false);

    expect(steps.first.id, 'welcome');
    expect(steps[1].id, 'empty_library');
    expect(steps.any((step) => step.id == 'library'), isFalse);
    expect(steps.last.title, 'הסיור המקוצר הסתיים');
  });

  test('מציג קיצורי מקלדת לפי Settings ולא לפי ברירת מחדל קבועה', () async {
    await Settings.setValue<String>(
      'key-shortcut-open-settings',
      'ctrl+comma',
    );
    await Settings.setValue<String>('key-shortcut-open-more', 'alt+m');

    final navigationStep = TourSteps.build(libraryLoaded: true)
        .firstWhere((step) => step.id == 'navigation');

    expect(navigationStep.body, contains('הגדרות Ctrl+,'));
    expect(navigationStep.body, contains('כלים Alt+M'));
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

  test('TourCubit שומר skipped_without_library כאשר מדלגים בלי ספרייה',
      () async {
    final cubit = TourCubit()..start(libraryLoaded: false);

    await cubit.skip();

    expect(cubit.state.isActive, isFalse);
    expect(
      Settings.getValue<String>(TourSteps.statusKey),
      TourSteps.skippedWithoutLibrary,
    );
    await cubit.close();
  });

  test('TourCubit שומר completed_without_library כאשר מסיימים בלי ספרייה',
      () async {
    final cubit = TourCubit()..start(libraryLoaded: false);

    await cubit.complete();

    expect(cubit.state.isActive, isFalse);
    expect(
      Settings.getValue<String>(TourSteps.statusKey),
      TourSteps.completedWithoutLibrary,
    );
    await cubit.close();
  });

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
    final startedNextSession =
        nextSessionCubit.startIfNeeded(libraryLoaded: true);

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

  test('TourCubit חדש טוען resolvedTips מ-Settings ולא מציג שוב טיפ שנסגרה',
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
  });

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
        fromStepId: 'shortcuts',
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

  testWidgets('TourOverlayScreen מודד מחדש יעד שמשתנה אחרי frame',
      (tester) async {
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
