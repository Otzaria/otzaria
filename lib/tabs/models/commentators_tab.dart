import 'package:flutter/foundation.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';

/// טאב המציג מפרשים לספר טקסט ספציפי עם בחירת פרק/פסוק עצמאית.
///
/// יוצר BLoC עצמאי שמאותחל מאותו ספר ומיקום כמו sourceTab,
/// אך פועל לגמרי בנפרד ואינו משפיע על sourceTab כלל.
class CommentatorsTab extends OpenedTab {
  final TextBookTab sourceTab;
  SourceTabOwnership? _sourceTabOwnership;

  /// נבנה בגישה הראשונה, כמו ב-[TextBookTab.bloc]: שולחנות עבודה מפענחים
  /// את כל הטאבים בכל שינוי.
  TextBookBloc get bloc => _bloc ??= _createBloc();
  TextBookBloc? _bloc;
  late final TextBookInitial _initialState;
  bool _isDisposed = false;

  /// ה-state הנוכחי, בלי לבנות bloc לטאב שטרם הוצג.
  TextBookState get blocState => _bloc?.state ?? _initialState;

  /// השורה שנבחרה ב-sourceTab בעת הפתיחה (אם הייתה), null אם לא הייתה בחירה
  final int? initialSelectedLine;

  /// בחירת המפרשים של הכרטיסייה. null = ללא בחירה (מוצגים כל מפרשי הספר).
  /// נשמר ב-toJson — בלעדיו הבחירה אבדה בסגירת התוכנה ושוחזרו "כל המפרשים".
  List<String>? selectedCommentators;

  /// ריבוי-הבחירה (Ctrl) של הכרטיסייה, בשורות. ריק = בחירה יחידה.
  /// נגזר מטאב המקור בפתיחה, ומסך המפרשים מעדכן אותו ישירות.
  final Set<int> selectedIndices = <int>{};

  /// מיקום הפתיחה של הכרטיסיה הזו. עצמאי מזה של [sourceTab] — זו כל מטרתה.
  final int startIndex;

  static int? _resolveSelectedLine(TextBookTab tab) {
    final s = tab.blocState;
    return s is TextBookLoaded ? s.selectedIndex : null;
  }

  static int _resolveStartIndex(TextBookTab tab) {
    final s = tab.blocState;
    return (s is TextBookLoaded ? s.selectedIndex : null) ?? tab.index;
  }

  CommentatorsTab({
    required this.sourceTab,
    bool disposeSourceTabOnDispose = false,
    // בשכפול ה-bloc של ה-sourceTab החדש עדיין ב-TextBookInitial, ולכן השורה
    // הנבחרת מועברת במפורש. null = "גזור מה-sourceTab".
    int? initialSelectedLine,
    // ⚠️ בשחזור ובשכפול ה-`sourceTab` הטרי עדיין ב-`TextBookInitial`, ולכן
    // הגזירה ממנו מחזירה את מיקום **הספר** ומיקום הכרטיסיה אובד.
    int? startIndex,
    @visibleForTesting TextBookBloc? blocOverride,
  }) : initialSelectedLine =
           initialSelectedLine ?? _resolveSelectedLine(sourceTab),
       startIndex = startIndex ?? _resolveStartIndex(sourceTab),
       super('מפרשים | ${sourceTab.title}') {
    final sourceState = sourceTab.blocState;
    if (sourceState is TextBookLoaded &&
        sourceState.activeCommentators.isNotEmpty) {
      selectedCommentators = List<String>.from(sourceState.activeCommentators);
    }
    if (sourceState is TextBookLoaded &&
        sourceState.selectedIndices.length > 1) {
      selectedIndices.addAll(sourceState.selectedIndices);
    }

    _initialState = TextBookInitial.named(
      sourceTab.book,
      this.startIndex,
      false, // openLeftPane
      const [], // commentators — ייטען אחרי availableCommentators
    );
    // blocOverride קיים רק לטסטים שצריכים bloc עם repository מזויף.
    _bloc = blocOverride;
    if (disposeSourceTabOnDispose) {
      _sourceTabOwnership = SourceTabOwnership(sourceTab)..retain();
    }
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

    final tab = CommentatorsTab(
      sourceTab: sourceTab,
      disposeSourceTabOnDispose: true,
      startIndex: json['initialIndex'] as int?,
    )..isPinned = json['isPinned'] ?? false;
    final savedIndices = json['selectedIndices'];
    if (savedIndices is List) {
      tab.selectedIndices.addAll(savedIndices.whereType());
    }
    if (json.containsKey('selectedCommentators')) {
      final saved = json['selectedCommentators'];
      tab.selectedCommentators = saved is List
          ? List<String>.from(saved)
          : null;
    } else {
      // JSON מגרסה שלא שמרה את בחירת הכרטיסייה — הבחירה של טאב המקור קרובה יותר
      // מאשר "כל המפרשים".
      final sourceCommentators = sourceTab.commentators;
      if (sourceCommentators != null && sourceCommentators.isNotEmpty) {
        tab.selectedCommentators = List<String>.from(sourceCommentators);
      }
    }
    return tab;
  }

  /// המקור והשכפול חייבים לקבל [sourceTab] נפרד, אחרת [dispose] של האחד סוגר
  /// את ה-BLoC ואת הבקרים של השני.
  @override
  OpenedTab clone() =>
      CommentatorsTab(
          // `OpenedTab.from` מוצהר כמחזיר OpenedTab; הענף של TextBookTab מחזיר
          // תמיד את אותו טיפוס, ובדיקת השכפול מוודאת שזה נשאר נכון.
          sourceTab: OpenedTab.from(sourceTab) as TextBookTab,
          // השכפול הוא הבעלים של ה-sourceTab שנוצר כאן; בלי זה ה-BLoC והבקרים
          // שלו לא משוחררים לעולם.
          disposeSourceTabOnDispose: true,
          initialSelectedLine: initialSelectedLine,
          startIndex: currentIndex,
        )
        ..isPinned = isPinned
        ..selectedIndices.addAll(selectedIndices)
        ..selectedCommentators = selectedCommentators == null
            ? null
            : List<String>.from(selectedCommentators!);

  TextBookBloc _createBloc() {
    final created = TextBookBloc(
      repository: TextBookRepository(fileSystem: FileSystemData.instance),
      initialState: _initialState,
    );
    if (_isDisposed) created.close();
    return created;
  }

  /// יורש את הבעלות על [sourceTab] כשטאב הספר שהחזיק אותו נסגר.
  ///
  /// ⚠️ בלי זה שחרור טאב הספר משאיר את הכרטיסיה הזו מצביעה על `bloc`
  /// ו-`currentTitle` משוחררים — ורצועת הכרטיסיות עצמה מאזינה להם.
  void assumeSourceTabOwnership(SourceTabOwnership ownership) {
    assert(identical(ownership.sourceTab, sourceTab));
    _sourceTabOwnership = ownership..retain();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _bloc?.close();
    _sourceTabOwnership?.release();
    _sourceTabOwnership = null;
    super.dispose();
  }

  /// השורה הראשונה של הבחירה בניווט הכרטיסיה. ה-bloc שלה אינו גולל,
  /// ולכן `visibleIndices` נשאר על מיקום הפתיחה.
  int? navigatedIndex;

  /// המיקום שהכרטיסיה מוצגת בו כרגע. נופל ל-[startIndex] כל עוד ה-bloc
  /// לא נטען — ולא ל-`sourceTab.index`, שהוא המיקום של הספר ולא שלה.
  int get currentIndex {
    if (navigatedIndex != null) return navigatedIndex!;
    final s = blocState;
    if (s is TextBookLoaded && s.visibleIndices.isNotEmpty) {
      return s.visibleIndices.first;
    }
    return startIndex;
  }

  @override
  Map<String, dynamic> toJson() {
    // שמור את ה-sourceTab כדי לשחזר אחרי הפעלה מחדש
    return {
      'title': title,
      'type': 'CommentatorsTab',
      'isPinned': isPinned,
      'initialIndex': currentIndex,
      'bookTitle': sourceTab.book.title,
      'sourceTab': sourceTab.toJson(),
      'selectedCommentators': selectedCommentators,
      if (selectedIndices.isNotEmpty)
        'selectedIndices': selectedIndices.toList()..sort(),
    };
  }
}
