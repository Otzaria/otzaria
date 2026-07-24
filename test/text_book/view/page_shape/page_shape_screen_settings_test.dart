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
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_screen.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_settings_panel.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/widgets/layout/context_overlay_panel.dart';
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
    ValueNotifier<int> openSettingsNotifier,
  ) async {
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

    // הפאנל (רוחב 400) יושב בצד הימני; הקשה בקצה השמאלי פוגעת ב-scrim.
    await tester.tapAt(const Offset(30, 300));
    await tester.pump();
    await tester.pump();
    expect(settingsPane(tester).isOpen, isFalse);
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
}

TextBookLoaded _loadedState({
  List<String> availableCommentators = const ['רש"י על ספר בדיקה'],
}) {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
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
