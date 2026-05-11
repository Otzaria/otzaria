import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// טאב המציג מפרשים לספר טקסט ספציפי עם בחירת פרק/פסוק עצמאית.
///
/// יוצר BLoC עצמאי שמאותחל מאותו ספר ומיקום כמו sourceTab,
/// אך פועל לגמרי בנפרד ואינו משפיע על sourceTab כלל.
class CommentatorsTab extends OpenedTab {
  final TextBookTab sourceTab;
  late final TextBookBloc bloc;
  final ItemScrollController scrollController = ItemScrollController();
  final ItemPositionsListener positionsListener = ItemPositionsListener.create();

  /// השורה שנבחרה ב-sourceTab בעת הפתיחה (אם הייתה), null אם לא הייתה בחירה
  final int? initialSelectedLine;

  static int? _resolveSelectedLine(TextBookTab tab) {
    final s = tab.bloc.state;
    return s is TextBookLoaded ? s.selectedIndex : null;
  }

  CommentatorsTab({required this.sourceTab})
      : initialSelectedLine = _resolveSelectedLine(sourceTab),
        super('מפרשים | ${sourceTab.title}') {
    // קורא מיקום התחלתי מה-state הנוכחי של sourceTab
    final sourceState = sourceTab.bloc.state;
    final int startIndex = sourceState is TextBookLoaded
        ? (sourceState.selectedIndex ??
            (sourceState.visibleIndices.isNotEmpty
                ? sourceState.visibleIndices.first
                : sourceTab.index))
        : sourceTab.index;

    bloc = TextBookBloc(
      repository: TextBookRepository(
        fileSystem: FileSystemData.instance,
      ),
      initialState: TextBookInitial.named(
        sourceTab.book,
        startIndex,
        false,      // openLeftPane
        const [],   // commentators — ייטען אחרי availableCommentators
      ),
      scrollController: scrollController,
      positionsListener: positionsListener,
    );
  }

  /// שחזור מ-JSON — יוצר sourceTab מדומה על בסיס הנתונים השמורים
  factory CommentatorsTab.fromJson(Map<String, dynamic> json) {
    // Hive מחזיר nested maps כ-Map<dynamic, dynamic> — צריך להמיר
    final rawSourceTab = json['sourceTab'];
    final Map<String, dynamic>? sourceJson = rawSourceTab is Map
        ? Map<String, dynamic>.from(rawSourceTab)
        : null;
    final TextBookTab sourceTab = sourceJson != null
        ? TextBookTab.fromJson(sourceJson)
        : TextBookTab(
            index: json['initialIndex'] ?? 0,
            book: TextBook(title: json['bookTitle'] ?? ''),
            commentators: const [],
          );

    final tab = CommentatorsTab(sourceTab: sourceTab)
      ..isPinned = json['isPinned'] ?? false;
    return tab;
  }

  @override
  void dispose() {
    bloc.close();
    super.dispose();
  }

  @override
  Map<String, dynamic> toJson() {
    // שמור את ה-sourceTab כדי לשחזר אחרי הפעלה מחדש
    int currentIndex = sourceTab.index;
    if (bloc.state is TextBookLoaded) {
      final s = bloc.state as TextBookLoaded;
      if (s.visibleIndices.isNotEmpty) currentIndex = s.visibleIndices.first;
    }
    return {
      'title': title,
      'type': 'CommentatorsTab',
      'isPinned': isPinned,
      'initialIndex': currentIndex,
      'bookTitle': sourceTab.book.title,
      'sourceTab': sourceTab.toJson(),
    };
  }
}
