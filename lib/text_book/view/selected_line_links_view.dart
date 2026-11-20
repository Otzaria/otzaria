import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/text_display/models/text_display_slot.dart';
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';
import 'package:otzaria/text_book/widgets/text_book_state_builder.dart';
import 'package:otzaria/widgets/commentary/links_list_view.dart';

// העזרים הטהורים חיים עם הווידג'ט המשותף; מיוצאים מכאן כדי שצרכני
// כרטיסיית הטקסט (וטסטיה) ימשיכו לייבא אותם מנקודה אחת.
export 'package:otzaria/widgets/commentary/links_list_view.dart';

/// קישורים מבוססי-תווים (inline) מוצגים רק בתוך הטקסט, לא ברשימה.
/// `visibleLinks` כבר מסונן מקישורים תלויי-טקסט, ולכן אין כאן בדיקת סוג.
@visibleForTesting
List<Link> referenceLinksOf(TextBookLoaded state) => state.visibleLinks
    .where((link) => link.start == null && link.end == null)
    .toList();

/// מתאם ה-BLoC ל-[LinksListView]: מזין לרשימה המשותפת את קישורי הקטע הנראה,
/// את בחירת סוגי הקישורים ואת מצב התצוגה מתוך [TextBookBloc].
class SelectedLineLinksView extends StatelessWidget {
  final Function(OpenedTab) openBookCallback;
  final double fontSize;

  final SelectionSyncController? selectionSyncController;

  /// false כשהחלונית סגורה אך נשארת בעץ: גלילה בספר לא בונה בה את הרשימה.
  final bool isPaneOpen;

  const SelectedLineLinksView({
    super.key,
    required this.openBookCallback,
    required this.fontSize,
    this.selectionSyncController,
    this.isPaneOpen = true,
  });

  @override
  Widget build(BuildContext context) {
    return TextBookStateBuilder(
      // רשימת הקישורים תלויה ב-visibleLinks בלבד (ובהצגת הטקסט), לא בתוכן
      // הספר. דילוג על emit-ים של warming/הרחבת-טווח שלא נוגעים לקישורים.
      buildWhen: (previous, current) {
        if (!isPaneOpen) return false;
        if (previous is! TextBookLoaded || current is! TextBookLoaded) {
          return true;
        }
        return previous.visibleLinks != current.visibleLinks ||
            !identical(previous.links, current.links) ||
            previous.selectedLinkTypes != current.selectedLinkTypes ||
            previous.fontSize != current.fontSize ||
            previous.commentaryDisplayProfile !=
                current.commentaryDisplayProfile ||
            previous.bodyDisplayProfile.showAnchorMarkers !=
                current.bodyDisplayProfile.showAnchorMarkers ||
            _copyProfile(previous) != _copyProfile(current);
      },
      builder: (context, built) {
        // בפתיחה ה-builder רץ עם המצב האחרון שעבר את buildWhen, שאולי התיישן.
        final latest = context.read<TextBookBloc>().state;
        final state = latest is TextBookLoaded ? latest : built;
        return LinksListView(
          links: referenceLinksOf(state),
          chipSourceLinks: state.links,
          openBookTitle: state.book.title,
          selectedLinkTypes: state.selectedLinkTypes,
          onSelectedLinkTypesChanged: (types) =>
              context.read<TextBookBloc>().add(UpdateLinkTypeFilter(types)),
          openBookCallback: openBookCallback,
          fontSize: fontSize,
          displayProfile: state.commentaryDisplayProfile,
          copyDisplayProfile: _copyProfile(state),
          showAnchorMarkers: state.bodyDisplayProfile.showAnchorMarkers,
          selectionSyncController: selectionSyncController,
        );
      },
    );
  }

  static TextDisplayProfile _copyProfile(TextBookLoaded state) =>
      state.displayProfile(
        target: TextTarget.commentary,
        channel: TextChannel.copy,
      );
}
