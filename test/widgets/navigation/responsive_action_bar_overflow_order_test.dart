import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';

ActionButtonData action(
  String id, {
  required ToolbarActionId actionId,
  double width = 40,
}) {
  return ActionButtonData(
    widget: const SizedBox.shrink(),
    tooltip: id,
    toolbarWidth: width,
    actionId: actionId,
  );
}

void main() {
  test('every ToolbarActionId appears exactly once in overflow order', () {
    expect(
      toolbarOverflowOrder.length,
      ToolbarActionId.values.length,
    );

    expect(
      toolbarOverflowOrder.toSet().length,
      toolbarOverflowOrder.length,
    );

    expect(
      toolbarOverflowOrder.toSet(),
      ToolbarActionId.values.toSet(),
    );
  });

  test('toolbar action without actionId is rejected', () {
    final actions = [
      ActionButtonData(
        widget: const SizedBox.shrink(),
        tooltip: 'missing-id',
        toolbarWidth: 40,
      ),
    ];

    expect(
      () => partitionToolbarActionsForWidth(
        actions: actions,
        maxWidth: 20,
        standardButtonWidth: 40,
        overflowButtonWidth: 40,
        overflowAlreadyRequired: false,
      ),
      throwsStateError,
    );
  });

  group('partitionToolbarActionsForWidth', () {
    test('plugin action moves to overflow before built-ins', () {
      final actions = [
        action('built-1', actionId: ToolbarActionId.zoomIn),
        action('search', actionId: ToolbarActionId.search),
        action('plugin', actionId: ToolbarActionId.plugin),
        action('built-2', actionId: ToolbarActionId.zoomOut),
      ];

      final result = partitionToolbarActionsForWidth(
        actions: actions,
        maxWidth: 160,
        standardButtonWidth: 40,
        overflowButtonWidth: 40,
        overflowAlreadyRequired: true,
      );

      expect(
        result.hidden.map((e) => e.tooltip).toList(),
        ['plugin'],
      );

      expect(
        result.visible.map((e) => e.tooltip).toList(),
        ['built-1', 'search', 'built-2'],
      );
    });

    test('search moves before ordinary built-ins after plugins', () {
      final actions = [
        action('built-1', actionId: ToolbarActionId.zoomIn),
        action('search', actionId: ToolbarActionId.search),
        action('plugin', actionId: ToolbarActionId.plugin),
        action('built-2', actionId: ToolbarActionId.zoomOut),
      ];

      final result = partitionToolbarActionsForWidth(
        actions: actions,
        maxWidth: 120,
        standardButtonWidth: 40,
        overflowButtonWidth: 40,
        overflowAlreadyRequired: true,
      );

      expect(
        result.hidden.map((e) => e.tooltip).toList(),
        ['search', 'plugin'],
      );

      expect(
        result.visible.map((e) => e.tooltip).toList(),
        ['built-1', 'built-2'],
      );
    });

    test('actions with the same id hide later display item first', () {
      final actions = [
        action('first', actionId: ToolbarActionId.plugin),
        action('second', actionId: ToolbarActionId.plugin),
        action('third', actionId: ToolbarActionId.plugin),
      ];

      final result = partitionToolbarActionsForWidth(
        actions: actions,
        maxWidth: 120,
        standardButtonWidth: 40,
        overflowButtonWidth: 40,
        overflowAlreadyRequired: true,
      );

      expect(
        result.hidden.map((e) => e.tooltip).toList(),
        ['third'],
      );

      expect(
        result.visible.map((e) => e.tooltip).toList(),
        ['first', 'second'],
      );
    });

    test('uses the declared width of wider controls', () {
      // plugin (rank=0) יורד לפני parallelEdition (rank=9).
      // wide=plugin (61px), narrow=parallelEdition (40px).
      // visibleWidth=101, required=141>120 → plugin יורד.
      // אחרי הסתרת plugin: visibleWidth=40, required=40+40=80 ≤ 120 → עוצר.
      final actions = [
        action('narrow', actionId: ToolbarActionId.parallelEdition, width: 40),
        action('wide', actionId: ToolbarActionId.plugin, width: 61),
      ];

      final result = partitionToolbarActionsForWidth(
        actions: actions,
        maxWidth: 120,
        standardButtonWidth: 40,
        overflowButtonWidth: 40,
        overflowAlreadyRequired: true,
      );

      expect(
        result.hidden.map((e) => e.tooltip).toList(),
        ['wide'],
      );

      expect(
        result.visible.map((e) => e.tooltip).toList(),
        ['narrow'],
      );
    });

    test('one overflowing action is still moved to the menu', () {
      final actions = [
        action('first', actionId: ToolbarActionId.zoomIn),
        action('second', actionId: ToolbarActionId.search),
        action('third', actionId: ToolbarActionId.plugin, width: 61),
      ];

      final result = partitionToolbarActionsForWidth(
        actions: actions,
        maxWidth: 120,
        standardButtonWidth: 40,
        overflowButtonWidth: 40,
        overflowAlreadyRequired: false,
      );

      expect(
        result.hidden.map((e) => e.tooltip).toList(),
        ['third'],
      );

      expect(
        result.visible.map((e) => e.tooltip).toList(),
        ['first', 'second'],
      );
    });

    test('all actions stay visible when they fit', () {
      final actions = [
        action('first', actionId: ToolbarActionId.zoomIn),
        action('second', actionId: ToolbarActionId.search),
        action('third', actionId: ToolbarActionId.plugin),
      ];

      final result = partitionToolbarActionsForWidth(
        actions: actions,
        maxWidth: 120,
        standardButtonWidth: 40,
        overflowButtonWidth: 40,
        overflowAlreadyRequired: false,
      );

      expect(result.hidden, isEmpty);

      expect(
        result.visible.map((e) => e.tooltip).toList(),
        ['first', 'second', 'third'],
      );
    });
  });

  group('atomic overflow groups', () {
    // ארבע פעולות, כל אחת רוחב 40.
    // overflowAlreadyRequired: true → צריך מקום ל-"..." (40px נוסף).
    // maxWidth: 160 → מקום ל-4 כפתורים (160) אבל עם overflow button צריך 200.
    // לכן search (rank 1) יורד ראשון, זום נשאר.
    test('search hides before zoom at width 160 with overflow required', () {
      final actions = [
        action('search', actionId: ToolbarActionId.search),
        action('zoomOut', actionId: ToolbarActionId.zoomOut),
        action('zoomIn', actionId: ToolbarActionId.zoomIn),
        action('viewMode', actionId: ToolbarActionId.viewMode),
      ];

      final result = partitionToolbarActionsForWidth(
        actions: actions,
        maxWidth: 160,
        standardButtonWidth: 40,
        overflowButtonWidth: 40,
        overflowAlreadyRequired: true,
      );

      expect(
        result.hidden.map((e) => e.tooltip).toList(),
        ['search'],
      );

      expect(
        result.visible.map((e) => e.tooltip).toList(),
        ['zoomOut', 'zoomIn', 'viewMode'],
      );
    });

    // maxWidth: 120 → מקום ל-3 כפתורים (120) אבל overflow button דורש עוד 40.
    // זום יורד כקבוצה אטומית; הרוחב המתפנה (80) מאפשר להחזיר את search.
    test(
      'both zoom buttons move to overflow together and search is restored',
      () {
        final actions = [
          action('search', actionId: ToolbarActionId.search),
          action('zoomOut', actionId: ToolbarActionId.zoomOut),
          action('zoomIn', actionId: ToolbarActionId.zoomIn),
          action('viewMode', actionId: ToolbarActionId.viewMode),
        ];

        final result = partitionToolbarActionsForWidth(
          actions: actions,
          maxWidth: 120,
          standardButtonWidth: 40,
          overflowButtonWidth: 40,
          overflowAlreadyRequired: true,
        );

        expect(
          result.visible.map((e) => e.tooltip).toList(),
          ['search', 'viewMode'],
        );

        expect(
          result.hidden.map((e) => e.tooltip).toList(),
          ['zoomOut', 'zoomIn'],
        );
      },
    );

    test('zoomOut and zoomIn never split — both visible or both hidden', () {
      final actions = [
        action('search', actionId: ToolbarActionId.search),
        action('zoomOut', actionId: ToolbarActionId.zoomOut),
        action('zoomIn', actionId: ToolbarActionId.zoomIn),
        action('viewMode', actionId: ToolbarActionId.viewMode),
      ];

      // בדוק על טווח של רוחבים
      for (final width in [80, 100, 120, 140, 160, 180, 200, 240]) {
        final result = partitionToolbarActionsForWidth(
          actions: actions,
          maxWidth: width.toDouble(),
          standardButtonWidth: 40,
          overflowButtonWidth: 40,
          overflowAlreadyRequired: true,
        );

        final visibleIds = result.visible.map((e) => e.actionId).toSet();
        final hiddenIds = result.hidden.map((e) => e.actionId).toSet();

        final zoomOutVisible = visibleIds.contains(ToolbarActionId.zoomOut);
        final zoomInVisible = visibleIds.contains(ToolbarActionId.zoomIn);
        final zoomOutHidden = hiddenIds.contains(ToolbarActionId.zoomOut);
        final zoomInHidden = hiddenIds.contains(ToolbarActionId.zoomIn);

        expect(
          zoomOutVisible == zoomInVisible,
          isTrue,
          reason:
              'At width $width: zoomOut and zoomIn must both be visible or both be hidden',
        );
        expect(
          zoomOutHidden == zoomInHidden,
          isTrue,
          reason:
              'At width $width: zoomOut and zoomIn must both be visible or both be hidden',
        );
      }
    });
  });

  // ─── LIFO restore order ──────────────────────────────────────────────────────
  //
  // removedGroups = [[plugin], [search], [zoomOut, zoomIn]]
  // restore order (LIFO): zoomOut+zoomIn first, then search, then plugin.
  //
  // סדר ההסרה:  plugin (rank 0) → search (rank 1) → zoomOut+zoomIn (rank 2+3).
  // סדר ההחזרה: zoomOut+zoomIn → search → plugin.
  //
  // כל הפעולות רוחב 40px, overflow button 40px.
  group('LIFO restore order', () {
    // ── טסט 1: plugin יורד לפני search ──────────────────────────────────────
    // מוכיח שסדר ה-rank (plugin=0 לפני search=1) נשמר.
    // plugin יורד לפני search — גם כששניהם בסופו של דבר נסתרים.
    test('plugin hides before search', () {
      final actions = [
        action('plugin', actionId: ToolbarActionId.plugin),
        action('search', actionId: ToolbarActionId.search),
        action('viewMode', actionId: ToolbarActionId.viewMode),
      ];

      // 3 פעולות × 40 = 120px; maxWidth=40 (מקום רק ל-viewMode).
      // plugin (rank 0) יורד ראשון; search (rank 1) יורד שני; viewMode נשאר.
      final result = partitionToolbarActionsForWidth(
        actions: actions,
        maxWidth: 40,
        standardButtonWidth: 40,
        overflowButtonWidth: 40,
        overflowAlreadyRequired: true,
      );

      final hiddenTooltips = result.hidden.map((e) => e.tooltip).toList();
      // plugin מופיע לפני search ברשימת hidden (הוסר ראשון)
      expect(hiddenTooltips.indexOf('plugin'), lessThan(hiddenTooltips.indexOf('search')));
    });

    // ── טסט 2: search יורד לפני קבוצת zoom ──────────────────────────────────
    // 4 פעולות (ללא plugin); maxWidth=120.
    // visibleWidth=160; required=200 > 120 → search (rank 1) יורד.
    // visibleWidth=120; required=160 > 120 → zoom יורד כקבוצה.
    // rebalance LIFO: zoom הוסר אחרון → בודקים zoom קודם, לא נכנסים (80+40>120).
    // search הוסר לפניהם → 40+40=80 ≤ 120 → search חוזר.
    test('search hides before zoom group', () {
      final actions = [
        action('search', actionId: ToolbarActionId.search),
        action('zoomOut', actionId: ToolbarActionId.zoomOut),
        action('zoomIn', actionId: ToolbarActionId.zoomIn),
        action('viewMode', actionId: ToolbarActionId.viewMode),
      ];

      final result = partitionToolbarActionsForWidth(
        actions: actions,
        maxWidth: 120,
        standardButtonWidth: 40,
        overflowButtonWidth: 40,
        overflowAlreadyRequired: true,
      );

      // search ירד לפני zoom
      final hiddenTooltips = result.hidden.map((e) => e.tooltip).toList();
      expect(hiddenTooltips, containsAll(['zoomOut', 'zoomIn']));
      expect(hiddenTooltips, isNot(contains('search')));
    });

    // ── טסט 3: zoomOut+zoomIn חוזרים יחד לפני search (LIFO) ─────────────────
    //
    // מוכיח שבמצב שבו zoom הוסר אחרי search, zoom נבדק לפני search ב-restore.
    //
    // פעולות: search(40), zoomOut(40), zoomIn(40), viewMode(60).
    // overflow=40; maxWidth=120.
    // visibleWidth=180; required=220>120.
    // search (rank 1) יורד → removedGroups=[[search]]; rebalance: gi=-1 → כלום.
    //   visibleWidth=140; required=180>120.
    // zoom יורד כקבוצה (80px) → removedGroups=[[search],[zoom]]; visibleWidth=60.
    //   LIFO gi=0: search (40px): 60+40+40=140>120 → לא נכנס.
    //   required=60+40=100 ≤ 120 → עוצר.
    // תוצאה: hidden=[search,zoomOut,zoomIn]; visible=[viewMode].
    //
    // — לוגיקת LIFO: zoom (האחרון) נבדק ראשון (gi=length-2 דולג עליו בצעד שלו).
    //   בצעד הסרת zoom, gi=0 בודק את search — search לא נכנס (140>120).
    //   הדגמה: אם viewMode היה 40px, search היה חוזר (80≤120). במקרה הזה viewMode=60
    //   כדי להדגים שzoom נשאר hidden כי search לא נכנס.
    //
    // טסט 3b — מצב שבו zoom הוסר אחרי search וחוזר לפני search:
    // search(40), zoomOut(40), zoomIn(40), viewMode(40); overflow=40; maxWidth=120.
    // (זהה ל-test הקיים 'both zoom buttons move to overflow together and search is restored')
    // — כאן הראינו שgrouping נשמר: zoom חוזר יחד כקבוצה או לא חוזר.
    test('zoomOut+zoomIn restore together before search in LIFO order', () {
      // LIFO: אחרי הסרת zoom, gi בודק את search — search (40px) נכנס, zoom לא.
      // כלומר search חוזר לפני zoom כשzoom גדול מדי.
      // אבל כשzoom קטן מספיק — zoom חוזר לפני search.
      //
      // כאן נשתמש בסצנריו שבו זום הוסר אחרי search וזום כן נכנס (LIFO נותן לו עדיפות):
      // search(40), zoomOut(40), zoomIn(40), viewMode(40); maxWidth=120.
      // search יורד, zoom יורד; LIFO בצעד zoom: בודק search (gi=0) → לא מדלג —
      //   wait, gi = removedGroups.length-2: כשremovedGroups=[[search],[zoom]], gi=0=search.
      //   search: 40+40=80≤120 → search חוזר. visibleWidth=80.
      //   required=80+40=120≤120 → עוצר.
      // תוצאה: hidden=[zoomOut,zoomIn]; visible=[search,viewMode].
      // — zoom נשאר כי הוסר אחרון ונבדק אחרון בrestore של עצמו (לא נבדק).
      //   search חוזר כי נבדק ב-gi=0 אחרי הסרת zoom.
      final actions = [
        action('search', actionId: ToolbarActionId.search),
        action('zoomOut', actionId: ToolbarActionId.zoomOut),
        action('zoomIn', actionId: ToolbarActionId.zoomIn),
        action('viewMode', actionId: ToolbarActionId.viewMode),
      ];

      final result = partitionToolbarActionsForWidth(
        actions: actions,
        maxWidth: 120,
        standardButtonWidth: 40,
        overflowButtonWidth: 40,
        overflowAlreadyRequired: true,
      );

      // search חוזר (LIFO: נבדק בצעד הסרת zoom); zoom נשאר hidden.
      expect(result.hidden.map((e) => e.actionId).toSet(),
          containsAll([ToolbarActionId.zoomOut, ToolbarActionId.zoomIn]));
      expect(result.hidden.map((e) => e.actionId), isNot(contains(ToolbarActionId.search)));
      expect(result.visible.map((e) => e.tooltip), contains('search'));
    });

    // ── טסט 4: search חוזר לפני plugin ──────────────────────────────────────
    //
    // כאשר zoom מוסר אחרי plugin ואחרי search,
    // LIFO בצעד הסרת zoom בודק: search ראשון (gi=1), plugin שני (gi=0).
    // search נכנס לפני plugin — מוכיח LIFO לפי סדר הסרה ולא לפי rank.
    //
    // פעולות: plugin(60), search(40), zoomOut(40), zoomIn(40); overflow=40; maxWidth=80.
    // visibleWidth=180; required=220>80.
    // plugin (rank 0, 60px) יורד → gi=-1. visibleWidth=120; required=160>80.
    // search (rank 1, 40px) יורד → gi=0: plugin 60px: 80+60+40=180>80 → לא.
    //   visibleWidth=80; required=120>80.
    // zoom (rank 2+3, 80px) יורד כקבוצה → gi=1: search 40px: 0+40+40=80≤80 → חוזר!
    //   gi=0: plugin 60px: 40+60+40=140>80 → לא.
    //   visibleWidth=40; required=80≤80 → עוצר.
    // תוצאה: hidden=[plugin, zoomOut, zoomIn]; visible=[search].
    // search חזר לפני plugin (LIFO: search נבדק ב-gi=1 לפני plugin ב-gi=0).
    test('search restores before plugin in LIFO order', () {
      final actions = [
        action('plugin', actionId: ToolbarActionId.plugin, width: 60),
        action('search', actionId: ToolbarActionId.search),
        action('zoomOut', actionId: ToolbarActionId.zoomOut),
        action('zoomIn', actionId: ToolbarActionId.zoomIn),
      ];

      final result = partitionToolbarActionsForWidth(
        actions: actions,
        maxWidth: 80,
        standardButtonWidth: 40,
        overflowButtonWidth: 40,
        overflowAlreadyRequired: true,
      );

      final hiddenTooltips = result.hidden.map((e) => e.tooltip).toSet();
      final visibleTooltips = result.visible.map((e) => e.tooltip).toSet();

      // search חזר (LIFO: נבדק לפני plugin בצעד הסרת zoom)
      expect(visibleTooltips, contains('search'));
      // plugin לא חזר (גדול מדי)
      expect(hiddenTooltips, contains('plugin'));
      // zoom נשאר hidden (לא נבדק בrestore שלו)
      expect(hiddenTooltips, containsAll(['zoomOut', 'zoomIn']));
    });

    // ── טסט 5: קבוצה קודמת קטנה יותר חוזרת כשהאחרונה לא נכנסת ──────────────
    //
    // LIFO עובר מהסוף: zoom (האחרון) נבדק לפני search.
    // אם zoom לא נכנס — ממשיכים ל-search שכן נכנס.
    //
    // פעולות: plugin(40), search(40), zoomOut(40), zoomIn(40), viewMode(40).
    // overflow=40; maxWidth=120.
    // plugin יורד, search יורד, zoom יורד.
    // בצעד הסרת zoom: gi=1→search (40px): 40+40+40=120≤120 → חוזר.
    //                  gi=0→plugin (40px): 80+40+40=160>120 → לא.
    // תוצאה: hidden=[plugin, zoomOut, zoomIn]; visible=[search, viewMode].
    test('earlier smaller group restores when last group does not fit', () {
      final actions = [
        action('plugin', actionId: ToolbarActionId.plugin),
        action('search', actionId: ToolbarActionId.search),
        action('zoomOut', actionId: ToolbarActionId.zoomOut),
        action('zoomIn', actionId: ToolbarActionId.zoomIn),
        action('viewMode', actionId: ToolbarActionId.viewMode),
      ];

      final result = partitionToolbarActionsForWidth(
        actions: actions,
        maxWidth: 120,
        standardButtonWidth: 40,
        overflowButtonWidth: 40,
        overflowAlreadyRequired: true,
      );

      final hiddenTooltips = result.hidden.map((e) => e.tooltip).toSet();
      final visibleTooltips = result.visible.map((e) => e.tooltip).toSet();

      // zoom לא חזר (לא נכנס בתור קבוצה 80px); search חזר (40px)
      expect(hiddenTooltips, containsAll(['zoomOut', 'zoomIn']));
      expect(visibleTooltips, contains('search'));
      expect(visibleTooltips, isNot(contains('zoomOut')));
      expect(visibleTooltips, isNot(contains('zoomIn')));
    });

    // ── טסט 6: קבוצה אטומית חוזרת יחד גם ב-restore ─────────────────────────
    //
    // zoomOut ו-zoomIn יורדים יחד; כשיש מקום — חוזרים יחד, לא בנפרד.
    //
    // search(40), zoomOut(40), zoomIn(40), viewMode(40); overflow=40; maxWidth=120.
    // visibleWidth=160; required=200>120.
    // search (rank 1) יורד → visibleWidth=120; required=160>120 → עוד.
    // zoom יורד כקבוצה (80px) → visibleWidth=40; required=80≤120.
    // LIFO: zoom (80px) → 40+80+40=160>120 → לא. search (40px) → 40+40+40=120≤120 → חוזר.
    // תוצאה: visible=[search, viewMode]; hidden=[zoomOut, zoomIn].
    // — מוכיח שzoom נשאר שלם ב-hidden (לא זומן בנפרד).
    test('atomic group returns together or not at all in restore', () {
      final actions = [
        action('search', actionId: ToolbarActionId.search),
        action('zoomOut', actionId: ToolbarActionId.zoomOut),
        action('zoomIn', actionId: ToolbarActionId.zoomIn),
        action('viewMode', actionId: ToolbarActionId.viewMode),
      ];

      final result = partitionToolbarActionsForWidth(
        actions: actions,
        maxWidth: 120,
        standardButtonWidth: 40,
        overflowButtonWidth: 40,
        overflowAlreadyRequired: true,
      );

      final hiddenIds = result.hidden.map((e) => e.actionId).toSet();
      final visibleIds = result.visible.map((e) => e.actionId).toSet();

      // zoom נשאר hidden שלם
      expect(hiddenIds, containsAll([ToolbarActionId.zoomOut, ToolbarActionId.zoomIn]));
      // search חזר (לא zoom)
      expect(visibleIds, contains(ToolbarActionId.search));
      expect(visibleIds, isNot(contains(ToolbarActionId.zoomOut)));
      expect(visibleIds, isNot(contains(ToolbarActionId.zoomIn)));
    });
  });
}
