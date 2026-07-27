import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
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

  /// נשמר לתאימות ה-API של הקוראים; אינו משנה את הרשימה עצמה, שמוזנת
  /// מ-`visibleLinks` בכל מקרה.
  final bool showVisibleLinksIfNoSelection;
  final SelectionSyncController? selectionSyncController;

  const SelectedLineLinksView({
    super.key,
    required this.openBookCallback,
    required this.fontSize,
    this.showVisibleLinksIfNoSelection = false,
    this.selectionSyncController,
  });

  @override
  Widget build(BuildContext context) {
    return TextBookStateBuilder(
      // רשימת הקישורים תלויה ב-visibleLinks בלבד (ובהצגת הטקסט), לא בתוכן
      // הספר. דילוג על emit-ים של warming/הרחבת-טווח שלא נוגעים לקישורים.
      buildWhen: (previous, current) {
        if (previous is! TextBookLoaded || current is! TextBookLoaded) {
          return true;
        }
        return previous.visibleLinks != current.visibleLinks ||
            !identical(previous.links, current.links) ||
            previous.selectedLinkTypes != current.selectedLinkTypes ||
            previous.fontSize != current.fontSize ||
            previous.removeNikud != current.removeNikud ||
            previous.removePunctuation != current.removePunctuation;
      },
      builder: (context, state) {
        return LinksListView(
          links: referenceLinksOf(state),
          chipSourceLinks: state.links,
          openBookTitle: state.book.title,
          selectedLinkTypes: state.selectedLinkTypes,
          onSelectedLinkTypesChanged: (types) =>
              context.read<TextBookBloc>().add(UpdateLinkTypeFilter(types)),
          openBookCallback: openBookCallback,
          fontSize: fontSize,
          removeNikud: state.removeNikud,
          removePunctuation: state.removePunctuation,
          selectionSyncController: selectionSyncController,
        );
      },
    );
  }
}
