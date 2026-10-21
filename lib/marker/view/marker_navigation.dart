import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/marker_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/services/marker_book_index.dart';
import 'package:otzaria/marker/services/marker_paint.dart';
import 'package:otzaria/plugins/models/plugin_highlight.dart';
import 'package:otzaria/plugins/services/plugin_highlight_reveal_service.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tools/open_tool_tab.dart';
import 'package:otzaria/utils/navigation/open_book.dart';
import 'package:otzaria/marker/models/marker_book_uid.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';

const String kMarkerToolId = 'builtin.marker';

/// סימון שמסך המרקר מתבקש להציג כשהוא נפתח או כשהוא כבר פתוח.
final ValueNotifier<MarkerHighlight?> markerFocusRequest = ValueNotifier(null);

void openMarkerList(BuildContext context, {MarkerHighlight? focus}) {
  // כלי מוסתר אינו נפתח, ובקשה שנשארת הייתה מסננת אותו בפתיחה הבאה.
  final hidden = context
      .read<SettingsBloc>()
      .state
      .hiddenBuiltInToolIds
      .contains(kMarkerToolId);
  if (focus != null && !hidden) markerFocusRequest.value = focus;
  openToolTabById(context, kMarkerToolId);
}

/// הבלטה ששייכת לספר אחר באותה כותרת (מהדורה, ספר אישי). סימון מרקר נבדק
/// לפי המזהה עם המהדורה; הדגשת תוסף — לפי המזהה בלבד, כמו בציור שלה.
bool revealTargetsOtherBook(PluginHighlight highlight, Book book) =>
    highlight.ownerPluginId == kMarkerHighlightOwner
    ? markerOtherBook(highlight.bookUid, markerBookUidOf(book))
    : markerOtherBook(highlight.bookUid, PluginBookIdentity.uidOf(book));

/// פותח את הספר בפסקה של הסימון ומבליט את הסימון לרגע.
void openMarkInBook(BuildContext context, MarkerHighlight mark) {
  final library = context.read<LibraryBloc>().state.library;
  if (library == null) {
    UiSnack.show(MarkerMessages.libraryNotReady);
    return;
  }
  final book = MarkerBookIndex.of(
    library,
  ).find(mark.bookTitle, mark.bookUid, pdf: mark.pdf);
  if (book == null) {
    UiSnack.showError(MarkerMessages.bookNotFound);
    return;
  }
  openBook(
    context,
    book,
    mark.sectionStart,
    '',
    explicitIndex: true,
    requiresStableLayout: true,
    navigateToPositionIfReused: true,
  );
  // ב-PDF המעבר הוא לעמוד; ההבלטה הרגעית קיימת רק בקורא הטקסט.
  if (mark.pdf) return;
  final segment = mark.segments.first;
  PluginHighlightRevealService.instance.reveal(
    PluginHighlight(
      highlightId: mark.id,
      ownerPluginId: kMarkerHighlightOwner,
      bookId: book.title,
      bookUid: mark.bookUid,
      sectionIndex: segment.sectionIndex,
      range: segment.range,
      style: PluginHighlightStyle(backgroundColor: mark.colorHex),
      createdAt: mark.createdAt,
      updatedAt: mark.updatedAt,
    ),
  );
}
