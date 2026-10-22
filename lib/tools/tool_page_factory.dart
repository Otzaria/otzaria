import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/marker/view/marker_screen.dart';
import 'package:otzaria/personal_notes/view/personal_notes_screen.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/view/plugin_tab_page.dart';
import 'package:otzaria/tools/acronyms_dictionary/acronyms_dictionary_screen.dart';
import 'package:otzaria/tools/aramaic_dictionary/aramaic_dictionary_screen.dart';
import 'package:otzaria/tools/biographies/biographies_screen.dart';
import 'package:otzaria/tools/calendar/calendar_screen.dart';
import 'package:otzaria/tools/gematria/gematria_search_screen.dart';
import 'package:otzaria/tools/measurement_converter/measurement_converter_screen.dart';
import 'package:otzaria/tools/shamor_zachor/shamor_zachor.dart';
import 'package:otzaria/tools/tikkun_korim/engine/tikkun_engine_impl.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_korim_screen.dart';
import 'package:otzaria/tools/tool_query.dart';

/// בונה את עמוד התוכן של כלי מובנה, או `null` אם המזהה אינו מוכר.
///
/// המפתחות מתקבלים מבחוץ ולא נוצרים כאן, כדי שכל טאב יחזיק מופע משלו —
/// שני טאבי לוח-שנה חייבים מפתחות נפרדים.
Widget? buildBuiltInToolPage(
  String toolId, {
  required GlobalKey<CalendarWidgetState> calendarKey,
  required GlobalKey<GematriaSearchScreenState> gematriaKey,
  required ToolQueryInbox queryInbox,
}) {
  switch (toolId) {
    case 'builtin.calendar':
      return BlocBuilder<CalendarCubit, CalendarState>(
        builder: (context, _) => CalendarWidget(key: calendarKey),
      );
    case 'builtin.shamor_zachor':
      return ShamorZachorWidget(onTitleChanged: (_) {});
    case 'builtin.measurements':
      return const MeasurementConverterScreen();
    case 'builtin.notes':
      return const PersonalNotesManagerScreen();
    case 'builtin.marker':
      return MarkerScreen(queryInbox: queryInbox);
    case 'builtin.tikkun_korim':
      return const TikkunKorimScreen(
        engine: TikkunEngineImpl(),
        data: TikkunDataSourceImpl(),
      );
    case 'builtin.gematria':
      return GematriaSearchScreen(key: gematriaKey, queryInbox: queryInbox);
    case 'builtin.aramaic_dictionary':
      return AramaicDictionaryScreen(queryInbox: queryInbox);
    case 'builtin.acronyms_dictionary':
      return AcronymsDictionaryScreen(queryInbox: queryInbox);
    case 'builtin.biographies':
      return BiographiesScreen(queryInbox: queryInbox);
  }
  return null;
}

/// בונה את עמוד התוסף.
///
/// ה-key כולל `version` ו-`updatedAt` כדי שעדכון התוסף יאלץ יצירה מחדש של
/// ה-State: ל-`PluginTabPage.initState` יש לוגיקה שתלויה בנתיב ובגשר, ובלי
/// הרחבת המפתח Flutter היה משתמש שוב ב-State הישן עם הנתיב הישן.
Widget buildPluginToolPage(
  InstalledPlugin plugin, {
  required String instanceId,
}) => PluginTabPage(
  key: ValueKey(
    'plugin-tab-${plugin.pluginId}-${plugin.version}-'
    '${plugin.updatedAt.millisecondsSinceEpoch}',
  ),
  plugin: plugin,
  instanceId: instanceId,
);
