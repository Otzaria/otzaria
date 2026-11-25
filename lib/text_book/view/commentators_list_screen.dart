import 'package:flutter/foundation.dart' show listEquals, setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/book_common/utils/category_settings_utils.dart';
import 'package:otzaria/book_common/utils/commentary_type_filter.dart';
import 'package:otzaria/book_common/utils/commentator_group_builder.dart';
import 'package:otzaria/text_book/widgets/text_book_state_builder.dart';
import 'package:otzaria/widgets/lists/commentators_selection_panel.dart';

class CommentatorsListView extends StatefulWidget {
  /// צ׳יפי הסינון לפי סוג מפרש. ריקים = ציר הסוגים אינו מוצג.
  final List<String> typeChipKeys;
  final Set<String> selectedTypeChips;
  final ValueChanged<Set<String>>? onTypeChipsChanged;

  const CommentatorsListView({
    super.key,
    this.typeChipKeys = const [],
    this.selectedTypeChips = const {},
    this.onTypeChipsChanged,
  });

  @override
  State<CommentatorsListView> createState() => CommentatorsListViewState();
}

class CommentatorsListViewState extends State<CommentatorsListView> {
  WeakReference<TextBookLoaded>? _lineRelevantFor;
  Set<String> _lineRelevant = const {};

  @override
  Widget build(BuildContext context) {
    return TextBookStateBuilder(
      loadingWidget: const Center(),
      buildWhen: _shouldRebuild,
      builder: (context, state) {
        return CommentatorsSelectionPanel(
          groups: state.commentatorGroups,
          selectedCommentators: state.activeCommentators,
          bookTitle: state.book.title,
          rareCommentators: state.rareCommentators,
          lineRelevantCommentators: _lineRelevantCommentators(state),
          onSelectionChanged: (commentators) {
            context.read<TextBookBloc>().add(UpdateCommentators(commentators));
          },
          typeChipKeys: widget.typeChipKeys,
          selectedTypeChips: widget.selectedTypeChips,
          typeChipLabelBuilder: LinkTypes.hebrewLabel,
          commentatorsByType: CommentaryTypeFilter.commentatorsByType(
            state.links,
          ),
          onTypeChipsChanged: widget.onTypeChipsChanged,
          heCategories: bookCategoriesSource(state.book),
          onCategoryDefaultsSaved: () =>
              TextBookPerBookSettings.clearActiveCommentators(
                state.book,
                expected: state.activeCommentators,
              ),
        );
      },
    );
  }

  // גלילה בקורא משדרת מצב בכל שורה; הרשימה נבנית מחדש רק כשקלט שלה השתנה.
  bool _shouldRebuild(TextBookState previous, TextBookState current) {
    if (previous is! TextBookLoaded || current is! TextBookLoaded) return true;
    // BlocBuilder מחזיק את המצב שנבנה; פינוי תוכן חייב לשחרר את הגוף הקודם.
    return !identical(previous.content, current.content) ||
        !identical(previous.book, current.book) ||
        !identical(previous.links, current.links) ||
        previous.commentatorGroups != current.commentatorGroups ||
        !listEquals(previous.activeCommentators, current.activeCommentators) ||
        !setEquals(previous.rareCommentators, current.rareCommentators) ||
        !setEquals(
          _lineRelevantCommentators(previous),
          _lineRelevantCommentators(current),
        );
  }

  /// אינדקסי השורות הנוכחיים (בחירה מרובה אם יש, אחרת הנראות) שלפיהם מחליטים
  /// אילו מפרשים נדירים כן להציג ברשימה.
  Set<String> _lineRelevantCommentators(TextBookLoaded state) {
    if (state.rareCommentators.isEmpty) return const {};
    // ה-build משתמש בסט שכבר חושב עבור אותו מצב ב-buildWhen.
    if (identical(state, _lineRelevantFor?.target)) return _lineRelevant;
    final indexes = state.selectedIndices.isNotEmpty
        ? state.selectedIndices
        : (state.visibleIndices.isNotEmpty
              ? state.visibleIndices
              : (state.selectedIndex != null
                    ? [state.selectedIndex!]
                    : const <int>[]));
    _lineRelevantFor = WeakReference(state);
    return _lineRelevant = lineRelevantRareCommentators(
      rareCommentators: state.rareCommentators,
      currentIndexes: indexes,
      linksByLine: state.linksByLine,
    );
  }
}
