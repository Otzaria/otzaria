// לתחזוקת מטרות הסיור המודרך ראו: docs/guided_tour_developer_guide.md

import 'package:flutter/widgets.dart';

final List<GlobalKey> tourMainNavigationTargetKeys = List<GlobalKey>.generate(
  6,
  (index) => GlobalKey(debugLabel: 'tour_main_navigation_$index'),
);

final List<GlobalKey> tourMainNavigationItemTargetKeys =
    List<GlobalKey>.generate(
      6,
      (index) => GlobalKey(debugLabel: 'tour_main_navigation_item_$index'),
    );

final GlobalKey tourReadingScreenTargetKey = GlobalKey(
  debugLabel: 'tour_reading_screen_target',
);
final GlobalKey tourReadingTabsTargetKey = GlobalKey(
  debugLabel: 'tour_reading_tabs_target',
);
final GlobalKey tourReadingSettingsButtonTargetKey = GlobalKey(
  debugLabel: 'tour_reading_settings_button_target',
);
final GlobalKey tourFindRefDialogTargetKey = GlobalKey(
  debugLabel: 'tour_find_ref_dialog_target',
);

final GlobalKey tourSearchDialogTargetKey = GlobalKey(
  debugLabel: 'tour_search_dialog_target',
);

final Map<int, GlobalKey> tourSettingsTabTargetKeys = {
  0: GlobalKey(debugLabel: 'tour_settings_design_tab_target'),
};

final GlobalKey tourTitleBarHistoryButtonTargetKey = GlobalKey(
  debugLabel: 'tour_title_bar_history_button_target',
);
final GlobalKey tourTitleBarBookmarkButtonTargetKey = GlobalKey(
  debugLabel: 'tour_title_bar_bookmark_button_target',
);
