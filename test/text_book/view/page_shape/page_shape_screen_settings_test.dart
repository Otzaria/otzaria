// טסט רגרסיה לפתיחת פאנל הגדרות צורת הדף דרך ה-notifier:
// כפתור גלגל השיניים בסרגל העליון (TextBookScreen) רק מסמן בקשה ב-notifier,
// ו-PageShapeScreen הוא שפותח את פאנל ההגדרות הצף (ContextOverlayPanel) בצד
// הימני — עם onSettingsChanged מחווט, כדי שכל שינוי יוחל על המסך בעדכון חי.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_screen.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_settings_panel.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/widgets/layout/context_overlay_panel.dart';
import 'package:otzaria/widgets/layout/floating_panel.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  // פאנל ההגדרות הוא ה-ContextOverlayPanel היחיד במסך; בודקים את מצב
  // הפתיחה דרך isOpen כי המעטפת נשארת בעץ גם כשהפאנל סגור.
  ContextOverlayPanel settingsPane(WidgetTester tester) =>
      tester.widget<ContextOverlayPanel>(find.byType(ContextOverlayPanel));

  Future<void> pumpScreen(
    WidgetTester tester,
    ValueNotifier<int> openSettingsNotifier, {
    TextBookLoaded? loadedState,
    PageShapeDefaultsLoader? defaultsLoader,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(
              value: _TestTextBookBloc(loadedState ?? _loadedState()),
            ),
            BlocProvider<PersonalNotesBloc>.value(
              value: _TestPersonalNotesBloc(
                const PersonalNotesState(
                  isLoading: false,
                  bookId: 'ספר בדיקה',
                  locatedNotes: [],
                  missingNotes: [],
                  errorMessage: null,
                  filteredLocatedNotes: [],
                  filteredMissingNotes: [],
                ),
              ),
            ),
            BlocProvider<SettingsBloc>.value(
              value: _TestSettingsBloc(SettingsState.initial()),
            ),
          ],
          child: PageShapeScreen(
            openBookCallback: (_) {},
            openSettingsNotifier: openSettingsNotifier,
            defaultsLoader: defaultsLoader,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'בקשת פתיחה דרך openSettingsNotifier פותחת את החלונית עם עדכון חי מחווט',
    (tester) async {
      final openSettingsNotifier = ValueNotifier<int>(0);
      addTearDown(openSettingsNotifier.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<TextBookBloc>.value(
                value: _TestTextBookBloc(_loadedState()),
              ),
              BlocProvider<PersonalNotesBloc>.value(
                value: _TestPersonalNotesBloc(
                  const PersonalNotesState(
                    isLoading: false,
                    bookId: 'ספר בדיקה',
                    locatedNotes: [],
                    missingNotes: [],
                    errorMessage: null,
                    filteredLocatedNotes: [],
                    filteredMissingNotes: [],
                  ),
                ),
              ),
              BlocProvider<SettingsBloc>.value(
                value: _TestSettingsBloc(SettingsState.initial()),
              ),
            ],
            child: PageShapeScreen(
              openBookCallback: (_) {},
              openSettingsNotifier: openSettingsNotifier,
            ),
          ),
        ),
      );

      // המתנה לסיום טעינת התצורה (DefaultCommentators מחזיר ריק ללא DB)
      await tester.pump();
      await tester.pump();

      expect(find.byType(PageShapeSettingsPanel), findsNothing);

      // לחיצה על כפתור גלגל השיניים בסרגל העליון מתורגמת להעלאת ה-notifier
      openSettingsNotifier.value++;
      await tester.pump();
      await tester.pump();

      expect(find.byType(PageShapeSettingsPanel), findsOneWidget);

      // החיווט החי: החלונית חייבת לקבל onSettingsChanged כדי שהמסך יתעדכן
      // תוך כדי שינוי, ולא רק אחרי סגירתה.
      final panel = tester.widget<PageShapeSettingsPanel>(
        find.byType(PageShapeSettingsPanel),
      );
      expect(panel.onSettingsChanged, isNotNull);
      // כפתור האיפוס חייב להיות מחווט כדי שהמסך יטען מחדש את ברירות המחדל.
      expect(panel.onReset, isNotNull);
      // כפתור ה-X של המעטפת חייב להיות מחווט לסגירת הפאנל.
      expect(settingsPane(tester).onClose, isNotNull);
    },
  );

  testWidgets('יריית notifier שנייה סוגרת את חלונית ההגדרות (טוגל)', (
    tester,
  ) async {
    final openSettingsNotifier = ValueNotifier<int>(0);
    addTearDown(openSettingsNotifier.dispose);

    await pumpScreen(tester, openSettingsNotifier);
    expect(settingsPane(tester).isOpen, isFalse);

    openSettingsNotifier.value++;
    await tester.pump();
    await tester.pump();
    expect(settingsPane(tester).isOpen, isTrue);

    // יריית notifier שנייה = טוגל → החלונית נסגרת.
    openSettingsNotifier.value++;
    await tester.pump();
    await tester.pump();
    expect(settingsPane(tester).isOpen, isFalse);
  });

  testWidgets('כפתור הסגירה בחלונית סוגר אותה וניתן לפתוח שוב', (tester) async {
    final openSettingsNotifier = ValueNotifier<int>(0);
    addTearDown(openSettingsNotifier.dispose);

    await pumpScreen(tester, openSettingsNotifier);

    openSettingsNotifier.value++;
    await tester.pump();
    // המתנה לסיום אנימציית ההחלקה — כפתור ה-X נחשף אחרון (בצד הפנימי)
    // ולכן חייב שהחלונית תיפתח במלואה לפני הלחיצה.
    await tester.pump(const Duration(milliseconds: 500));
    expect(settingsPane(tester).isOpen, isTrue);

    await tester.tap(
      find.widgetWithIcon(IconButton, FluentIcons.dismiss_24_regular),
    );
    await tester.pump();
    await tester.pump();
    expect(settingsPane(tester).isOpen, isFalse);

    // אחרי סגירה מכפתור ה-X עדיין ניתן לפתוח מחדש דרך ה-notifier.
    openSettingsNotifier.value++;
    await tester.pump();
    await tester.pump();
    expect(settingsPane(tester).isOpen, isTrue);
  });

  testWidgets('הקשה על ה-scrim מחוץ לפאנל סוגרת אותו', (tester) async {
    final openSettingsNotifier = ValueNotifier<int>(0);
    addTearDown(openSettingsNotifier.dispose);

    await pumpScreen(tester, openSettingsNotifier);

    openSettingsNotifier.value++;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(settingsPane(tester).isOpen, isTrue);
    expect(find.byType(PageShapeSettingsPanel), findsOneWidget);

    final panelRect = tester.getRect(find.byType(FloatingPanel));
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final scrimX = panelRect.left > 0
        ? panelRect.left / 2
        : panelRect.right + (screenWidth - panelRect.right) / 2;
    await tester.tapAt(Offset(scrimX, 300));
    await tester.pump();
    await tester.pump();
    expect(settingsPane(tester).isOpen, isFalse);
  });

  testWidgets('בחירת קטגוריה שנשמרה עם שם מסכת אחרת מתעדכנת למסכת הנוכחית', (
    tester,
  ) async {
    // "יכין מקואות" — משפחת מפרשים שאין ב שמה "על" — נשמרה כפי שהיא בהגדרת
    // הקטגוריה, וכל מסכת אחרת הציגה את היכין של המסכת הראשונה.
    await PageShapeSettingsManager.saveConfiguration(
      'משנה מקואות',
      const {
        'left': 'יכין מקואות',
        'right': null,
        'bottom': null,
        'bottomRight': null,
      },
      saveToCategory: 'משנה',
    );

    final openSettingsNotifier = ValueNotifier<int>(0);
    addTearDown(openSettingsNotifier.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(
              value: _TestTextBookBloc(
                _loadedState(
                  book: TextBook(
                    title: 'משנה נדה',
                    heCategories: 'אוצריא, משנה, סדר טהרות, נדה',
                  ),
                  availableCommentators: const [
                    'ברטנורא על משנה נדה',
                    'יכין נדה',
                  ],
                ),
              ),
            ),
            BlocProvider<PersonalNotesBloc>.value(
              value: _TestPersonalNotesBloc(
                const PersonalNotesState(
                  isLoading: false,
                  bookId: 'משנה נדה',
                  locatedNotes: [],
                  missingNotes: [],
                  errorMessage: null,
                  filteredLocatedNotes: [],
                  filteredMissingNotes: [],
                ),
              ),
            ),
            BlocProvider<SettingsBloc>.value(
              value: _TestSettingsBloc(SettingsState.initial()),
            ),
          ],
          child: PageShapeScreen(
            openBookCallback: (_) {},
            openSettingsNotifier: openSettingsNotifier,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    openSettingsNotifier.value++;
    await tester.pump();
    await tester.pump();

    final panel = tester.widget<PageShapeSettingsPanel>(
      find.byType(PageShapeSettingsPanel),
    );
    expect(panel.currentLeft, 'יכין נדה');
  });

  testWidgets('מפרש שאינו קיים בספר הנוכחי אינו נמחק מההגדרה', (tester) async {
    // איפוס הבחירה ל-null היה נשמר חזרה מהפאנל ומוחק את המפרש מכל הקטגוריה.
    await PageShapeSettingsManager.saveConfiguration(
      'משנה נדה',
      const {
        'left': 'מלאכת שלמה על משנה מקואות',
        'right': null,
        'bottom': null,
        'bottomRight': null,
      },
    );

    final openSettingsNotifier = ValueNotifier<int>(0);
    addTearDown(openSettingsNotifier.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(
              value: _TestTextBookBloc(
                _loadedState(
                  book: TextBook(title: 'משנה נדה'),
                  availableCommentators: const ['ברטנורא על משנה נדה'],
                ),
              ),
            ),
            BlocProvider<PersonalNotesBloc>.value(
              value: _TestPersonalNotesBloc(
                const PersonalNotesState(
                  isLoading: false,
                  bookId: 'משנה נדה',
                  locatedNotes: [],
                  missingNotes: [],
                  errorMessage: null,
                  filteredLocatedNotes: [],
                  filteredMissingNotes: [],
                ),
              ),
            ),
            BlocProvider<SettingsBloc>.value(
              value: _TestSettingsBloc(SettingsState.initial()),
            ),
          ],
          child: PageShapeScreen(
            openBookCallback: (_) {},
            openSettingsNotifier: openSettingsNotifier,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    openSettingsNotifier.value++;
    await tester.pump();
    await tester.pump();

    final panel = tester.widget<PageShapeSettingsPanel>(
      find.byType(PageShapeSettingsPanel),
    );
    expect(panel.currentLeft, 'מלאכת שלמה על משנה מקואות');
  });

  testWidgets('מפרש מוסתר אינו מוצג בטור שמור, וההגדרה נשמרת', (tester) async {
    const store = HiddenLibraryStore();
    final category = Category(
      title: 'מוסתרת',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: [TextBook(title: 'מפרש מוסתר', categoryId: 7)],
      parent: null,
    );
    final library = Library(categories: [category]);
    category.parent = library;
    DataRepository.instance.library = Future.value(library);
    await store.save(
      const HiddenLibrarySelection(categoryPaths: {'/מוסתרת'}),
    );
    addTearDown(() async {
      DataRepository.instance.invalidateLibraryCache();
      await store.save(const HiddenLibrarySelection());
    });
    await PageShapeSettingsManager.saveConfiguration(
      'ספר בדיקה',
      const {
        'left': 'מפרש מוסתר',
        'right': null,
        'bottom': null,
        'bottomRight': null,
      },
    );

    final notifier = ValueNotifier<int>(0);
    addTearDown(notifier.dispose);
    await pumpScreen(
      tester,
      notifier,
      loadedState: _loadedState(availableCommentators: const ['מפרש גלוי']),
    );
    notifier.value++;
    await tester.pump();
    await tester.pump();

    final panel = tester.widget<PageShapeSettingsPanel>(
      find.byType(PageShapeSettingsPanel),
    );
    expect(panel.currentLeft, isNull);
    final field = tester.widget<AppDropdownField<String>>(
      find
          .descendant(
            of: find.byType(PageShapeSettingsPanel),
            matching: find.byType(AppDropdownField<String>),
          )
          .first,
    );
    expect(field.value, '__NONE__');
    expect(
      PageShapeSettingsManager.loadConfiguration('ספר בדיקה')?['left'],
      'מפרש מוסתר',
    );
  });

  testWidgets('ברירת מחדל מוסתרת נעלמת גם כשאין מפרשים זמינים ומתעדכנת חי', (
    tester,
  ) async {
    const store = HiddenLibraryStore();
    final category = Category(
      title: 'מוסתרת',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: [TextBook(title: 'מפרש מוסתר', categoryId: 7)],
      parent: null,
    );
    final library = Library(categories: [category]);
    category.parent = library;
    DataRepository.instance.library = Future.value(library);
    addTearDown(() async {
      DataRepository.instance.invalidateLibraryCache();
      await store.save(const HiddenLibrarySelection());
    });

    final notifier = ValueNotifier<int>(0);
    addTearDown(notifier.dispose);
    await pumpScreen(
      tester,
      notifier,
      loadedState: _loadedState(availableCommentators: const []),
      defaultsLoader: (book, available) async => (
        commentators: <String, String?>{
          'left': 'מפרש מוסתר',
          'right': null,
          'bottom': null,
          'bottomRight': null,
        },
        visibility: <String, bool>{
          'left': true,
          'right': true,
          'bottom': true,
          'bottomRight': true,
        },
      ),
    );
    notifier.value++;
    await tester.pump();
    await tester.pump();
    PageShapeSettingsPanel panel() => tester.widget<PageShapeSettingsPanel>(
      find.byType(PageShapeSettingsPanel),
    );
    AppDropdownField<String> leftField() =>
        tester.widget<AppDropdownField<String>>(
          find
              .descendant(
                of: find.byType(PageShapeSettingsPanel),
                matching: find.byType(AppDropdownField<String>),
              )
              .first,
        );
    expect(panel().currentLeft, 'מפרש מוסתר');
    expect(leftField().value, 'מפרש מוסתר');

    await store.save(
      const HiddenLibrarySelection(categoryPaths: {'/מוסתרת'}),
    );
    await tester.pump();
    await tester.pump();
    expect(panel().currentLeft, isNull);
    expect(leftField().value, '__NONE__');

    await store.save(const HiddenLibrarySelection());
    await tester.pump();
    await tester.pump();
    expect(panel().currentLeft, 'מפרש מוסתר');
    expect(leftField().value, 'מפרש מוסתר');
  });

  testWidgets('הגדרת קטגוריה נטענת גם כש-heCategories מגיע מההעשרה ברקע', (
    tester,
  ) async {
    // issue #770: בפתיחת ספר heCategories הוא null עד שההעשרה ברקע מסתיימת.
    // הטעינה הראשונה מדלגת על הגדרת הקטגוריה ומציגה ברירות מחדל, וכשההעשרה
    // מגיעה המסך חייב לטעון מחדש — אחרת בחירת המשתמש "נעלמת".
    await PageShapeSettingsManager.saveConfiguration(
      'בראשית',
      const {
        'left': null,
        'right': 'תרגום אונקלוס על בראשית',
        'bottom': 'רש"י על בראשית',
        'bottomRight': 'רמב"ן על בראשית',
      },
      saveToCategory: 'תורה',
    );

    const commentators = [
      'רש"י על בראשית',
      'רמב"ן על בראשית',
      'תרגום אונקלוס על בראשית',
    ];
    final bloc = _TestTextBookBloc(
      _loadedState(
        book: TextBook(title: 'בראשית'),
        availableCommentators: commentators,
      ),
    );
    addTearDown(bloc.close);

    final openSettingsNotifier = ValueNotifier<int>(0);
    addTearDown(openSettingsNotifier.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: bloc),
            BlocProvider<PersonalNotesBloc>.value(
              value: _TestPersonalNotesBloc(
                const PersonalNotesState(
                  isLoading: false,
                  bookId: 'בראשית',
                  locatedNotes: [],
                  missingNotes: [],
                  errorMessage: null,
                  filteredLocatedNotes: [],
                  filteredMissingNotes: [],
                ),
              ),
            ),
            BlocProvider<SettingsBloc>.value(
              value: _TestSettingsBloc(SettingsState.initial()),
            ),
          ],
          child: PageShapeScreen(
            openBookCallback: (_) {},
            openSettingsNotifier: openSettingsNotifier,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // ההעשרה ברקע הסתיימה — הספר מקבל heCategories.
    bloc.emitState(
      _loadedState(
        book: TextBook(title: 'בראשית', heCategories: 'תנ"ך, תורה'),
        availableCommentators: commentators,
      ),
    );
    await tester.pump();
    await tester.pump();

    openSettingsNotifier.value++;
    await tester.pump();
    await tester.pump();

    final panel = tester.widget<PageShapeSettingsPanel>(
      find.byType(PageShapeSettingsPanel),
    );
    expect(panel.currentLeft, isNull);
    expect(panel.currentRight, 'תרגום אונקלוס על בראשית');
    expect(panel.currentBottom, 'רש"י על בראשית');
    expect(panel.currentBottomRight, 'רמב"ן על בראשית');
  });

  testWidgets('כשל טעינת מפרש תחתון אינו שומר הסתרה גלובלית', (tester) async {
    const missingCommentator = 'מפרש בדיקה שלא קיים במאגר';

    await PageShapeSettingsManager.saveConfiguration(
      'ספר בדיקה',
      const {
        'left': null,
        'right': null,
        'bottom': missingCommentator,
        'bottomRight': null,
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(
              value: _TestTextBookBloc(
                _loadedState(
                  availableCommentators: const [missingCommentator],
                ),
              ),
            ),
            BlocProvider<PersonalNotesBloc>.value(
              value: _TestPersonalNotesBloc(
                const PersonalNotesState(
                  isLoading: false,
                  bookId: 'ספר בדיקה',
                  locatedNotes: [],
                  missingNotes: [],
                  errorMessage: null,
                  filteredLocatedNotes: [],
                  filteredMissingNotes: [],
                ),
              ),
            ),
            BlocProvider<SettingsBloc>.value(
              value: _TestSettingsBloc(SettingsState.initial()),
            ),
          ],
          child: PageShapeScreen(openBookCallback: (_) {}),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();

    expect(
      Settings.getValue<bool>('page_shape_global_visibility_bottom'),
      isNot(false),
    );
    expect(
      Settings.getValue<bool>('page_shape_use_book_settings_ספר בדיקה'),
      isNot(true),
    );
  });
  testWidgets(
    'בורר המפרשים של צורת הדף אינו מציע את "הערות" ולא מפרשים נדירים',
    (tester) async {
      final openSettingsNotifier = ValueNotifier<int>(0);
      addTearDown(openSettingsNotifier.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<TextBookBloc>.value(
                value: _TestTextBookBloc(
                  _loadedState(
                    availableCommentators: const [
                      'רש"י על ספר בדיקה',
                      kNotesCommentatorTitle,
                      'דברים',
                    ],
                    rareCommentators: const {'דברים'},
                  ),
                ),
              ),
              BlocProvider<PersonalNotesBloc>.value(
                value: _TestPersonalNotesBloc(
                  const PersonalNotesState(
                    isLoading: false,
                    bookId: 'ספר בדיקה',
                    locatedNotes: [],
                    missingNotes: [],
                    errorMessage: null,
                    filteredLocatedNotes: [],
                    filteredMissingNotes: [],
                  ),
                ),
              ),
              BlocProvider<SettingsBloc>.value(
                value: _TestSettingsBloc(SettingsState.initial()),
              ),
            ],
            child: PageShapeScreen(
              openBookCallback: (_) {},
              openSettingsNotifier: openSettingsNotifier,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      openSettingsNotifier.value++;
      await tester.pumpAndSettle();

      final panel = tester.widget<PageShapeSettingsPanel>(
        find.byType(PageShapeSettingsPanel),
      );
      // 'הערות' הוא מפרש וירטואלי בלי קישורים — טור שנפתח ונעלם (issue #1227);
      // מפרש "נדיר" הוא בדרך כלל קישור שסווג בטעות (issue #1233).
      expect(panel.availableCommentators, ['רש"י על ספר בדיקה']);
    },
  );
}

TextBookLoaded _loadedState({
  List<String> availableCommentators = const ['רש"י על ספר בדיקה'],
  Set<String> rareCommentators = const {},
  TextBook? book,
}) {
  return TextBookLoaded(
    rareCommentators: rareCommentators,
    book: book ?? TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    showPageShapeView: true,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: availableCommentators,
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  void emitState(TextBookState newState) => emit(newState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _TestPersonalNotesBloc(super.initialState) {
    on<PersonalNotesEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
