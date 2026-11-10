import 'package:flutter/widgets.dart';
import 'package:otzaria/theme/app_density.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/models/books.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';
import 'package:otzaria/plugins/utils/plugin_toolbar_actions.dart';
import 'package:otzaria/plugins/utils/reader_location_resolver.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';

/// The plugin toolbar buttons of a reader screen. [pluginContext] tells the
/// plugins which reader asks, such as `reader-text` or `reader-pdf`.
List<ActionButtonData> buildReaderPluginActions(
  BuildContext context, {
  required OpenedTab tab,
  required String pluginContext,
}) {
  final records = [
    ...PluginToolbarRegistry.instance.getAll(),
    ...?context.read<PluginSystemBloc?>()?.toolbarRegistry?.getAll(),
  ];
  if (records.isEmpty) return const [];
  return buildPluginToolbarActions(
    records: records,
    viewId: View.of(context).viewId,
    windowKeys: AppWindowKeys.of(context),
    context: pluginContext,
    compact: AppDensity.of(context).isCompact,
    locationPayload: () async =>
        (await resolveReaderLocation(tab))?.toJson() ?? const {},
    bookType: readerBookTypeOf(tab),
    bookSource: readerBookSourceOf(tab),
    hostActionDispatcher: context
        .read<PluginSystemBloc?>()
        ?.declarativeHost
        ?.dispatchAction,
  );
}

/// The plugin entries of a reader screen's overflow menu, with their order.
List<(int, ActionButtonData)> buildReaderPluginOverflowActions(
  BuildContext context, {
  required OpenedTab tab,
  required String pluginContext,
}) {
  final records = [
    ...PluginToolbarRegistry.instance.getAll(),
    ...?context.read<PluginSystemBloc?>()?.toolbarRegistry?.getAll(),
  ];
  if (records.isEmpty) return const [];
  return buildOrderedPluginOverflowActions(
    records: records,
    viewId: View.of(context).viewId,
    windowKeys: AppWindowKeys.of(context),
    context: pluginContext,
    compact: AppDensity.of(context).isCompact,
    locationPayload: () async =>
        (await resolveReaderLocation(tab))?.toJson() ?? const {},
    bookType: readerBookTypeOf(tab),
    bookSource: readerBookSourceOf(tab),
    hostActionDispatcher: context
        .read<PluginSystemBloc?>()
        ?.declarativeHost
        ?.dispatchAction,
  );
}

/// הספר שהסרגל של [tab] מציג, או null בלשונית שאינה ספר. כל חלונית בתצוגה
/// מפוצלת בונה את הסרגל שלה עם הלשונית שלה, ולכן `bookTypes`/`bookSources`
/// נבדקים מול הספר שבאותה חלונית ולא מול החלונית הפעילה.
Book? _readerBookOf(OpenedTab tab) => switch (tab) {
  TextBookTab(:final book) => book,
  PdfBookTab(:final book) => book,
  _ => null,
};

/// סוג הספר של הסרגל, כפי שתוספים רואים אותו ב-`type` של זהות הספר.
String? readerBookTypeOf(OpenedTab tab) => switch (_readerBookOf(tab)) {
  final book? => PluginBookIdentity.typeOf(book),
  _ => null,
};

/// מקור הספר של הסרגל, כפי שתוספים רואים אותו ב-`source` של זהות הספר.
String? readerBookSourceOf(OpenedTab tab) => switch (_readerBookOf(tab)) {
  final book? => PluginBookIdentity.sourceOf(book),
  _ => null,
};

/// רישומים משותפים לצד הפקדים הדקלרטיביים של החלון הזה.
Listenable readerPluginToolbarListenable(BuildContext context) =>
    Listenable.merge([
      PluginToolbarRegistry.instance,
      context.read<PluginSystemBloc?>()?.toolbarRegistry,
    ]);
