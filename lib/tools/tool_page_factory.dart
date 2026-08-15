import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/anki_native/view/anki_native_host_view.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/personal_notes/view/personal_notes_screen.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/view/plugin_tab_page.dart';
import 'package:otzaria/tools/acronyms_dictionary/acronyms_dictionary_screen.dart';
import 'package:otzaria/tools/aramaic_dictionary/aramaic_dictionary_screen.dart';
import 'package:otzaria/tools/calendar/calendar_screen.dart';
import 'package:otzaria/tools/gematria/gematria_search_screen.dart';
import 'package:otzaria/tools/measurement_converter/measurement_converter_screen.dart';
import 'package:otzaria/tools/shamor_zachor/shamor_zachor.dart';

/// בונה את עמוד התוכן של כלי מובנה, או `null` אם המזהה אינו מוכר.
///
/// המפתחות מתקבלים מבחוץ ולא נוצרים כאן, כדי שכל טאב יחזיק מופע משלו —
/// שני טאבי לוח-שנה חייבים מפתחות נפרדים.
Widget? buildBuiltInToolPage(
  String toolId, {
  required GlobalKey<CalendarWidgetState> calendarKey,
  required GlobalKey<GematriaSearchScreenState> gematriaKey,
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
    case 'builtin.gematria':
      return GematriaSearchScreen(key: gematriaKey);
    case 'builtin.aramaic_dictionary':
      return const AramaicDictionaryScreen();
    case 'builtin.acronyms_dictionary':
      return const AcronymsDictionaryScreen();
  }
  return null;
}

/// בונה את עמוד התוסף.
///
/// ה-key כולל `version` ו-`updatedAt` כדי שעדכון התוסף יאלץ יצירה מחדש של
/// ה-State: ל-`PluginTabPage.initState` יש לוגיקה שתלויה בנתיב ובגשר, ובלי
/// הרחבת המפתח Flutter היה משתמש שוב ב-State הישן עם הנתיב הישן.
@visibleForTesting
bool shouldUseAnkiNativeHost(String pluginId, TargetPlatform platform) =>
    pluginId == 'org.otzaria.anki' && platform == TargetPlatform.windows;

Widget buildPluginToolPage(InstalledPlugin plugin) {
  if (shouldUseAnkiNativeHost(plugin.pluginId, defaultTargetPlatform)) {
    return _AnkiPluginToolPage(
      key: ValueKey(
        'anki-native-host-${plugin.version}-'
        '${plugin.updatedAt.millisecondsSinceEpoch}',
      ),
      plugin: plugin,
    );
  }
  return PluginTabPage(
    key: ValueKey(
      'plugin-tab-${plugin.pluginId}-${plugin.version}-'
      '${plugin.updatedAt.millisecondsSinceEpoch}',
    ),
    plugin: plugin,
  );
}

class _AnkiPluginToolPage extends StatefulWidget {
  final InstalledPlugin plugin;

  const _AnkiPluginToolPage({super.key, required this.plugin});

  @override
  State<_AnkiPluginToolPage> createState() => _AnkiPluginToolPageState();
}

class _AnkiPluginToolPageState extends State<_AnkiPluginToolPage> {
  bool _useMirrorFallback = false;

  @override
  Widget build(BuildContext context) {
    if (_useMirrorFallback) {
      return PluginTabPage(
        key: ValueKey(
          'anki-mirror-${widget.plugin.version}-'
          '${widget.plugin.updatedAt.millisecondsSinceEpoch}',
        ),
        plugin: widget.plugin,
      );
    }
    return AnkiNativeHostView(
      onFallback: () => setState(() => _useMirrorFallback = true),
    );
  }
}
