import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../test_helpers/memory_cache_provider.dart';

/// issue #937 — לחיצה ימנית משמרת-בחירה במפרש בצורת הדף פולטת אירוע בחירה
/// ריקה רגעי; עיבודו מחק את הטקסט השמור, ו-Ctrl+C הפסיק לעבוד לצמיתות
/// ("אנא בחר טקסט להעתקה") בעוד תפריט ההקשר המשיך להציע העתקה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  tearDown(UiSnack.hide);

  testWidgets('Ctrl+C ממפרש ממשיך לעבוד אחרי לחיצה ימנית על הבחירה', (
    tester,
  ) async {
    final textBookBloc = _TestTextBookBloc(_loadedState());
    final personalNotesBloc = _TestPersonalNotesBloc(
      const PersonalNotesState(
        isLoading: false,
        bookId: 'ספר בדיקה',
        locatedNotes: [],
        missingNotes: [],
        errorMessage: null,
        filteredLocatedNotes: [],
        filteredMissingNotes: [],
      ),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final sync = SelectionSyncController();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: Row(
              textDirection: TextDirection.rtl,
              children: [
                Expanded(
                  child: SimpleTextViewer(
                    content: const ['שורה ראשית ראשונה'],
                    fontSize: 18,
                    openBookCallback: (_) {},
                    isMainText: true,
                    selectionSyncController: sync,
                  ),
                ),
                Expanded(
                  child: SimpleTextViewer(
                    content: const [
                      'פירוש ארוך של המפרש על השורה הראשונה בספר',
                    ],
                    fontSize: 18,
                    openBookCallback: (_) {},
                    isMainText: false,
                    bookTitle: 'מפרש בדיקה',
                    selectionSyncController: sync,
                    notesRepository: _FakeNotesRepository(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> selectInCommentary() async {
      final rect = tester.getRect(find.textContaining('פירוש ארוך').first);
      final gesture = await tester.startGesture(
        Offset(rect.right - 5, rect.center.dy),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(Offset(rect.left + 5, rect.center.dy));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    // Ctrl+C; מחזירה true אם מסלול ההעתקה הופעל (בסביבת בדיקה הלוח אינו
    // זמין ולכן הצלחה = כל הודעה שאינה "אנא בחר טקסט להעתקה").
    Future<bool> pressCtrlCAndCopyReached() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final noText = find.text('אנא בחר טקסט להעתקה').evaluate().isNotEmpty;
      final anySnack = find.textContaining('העתק').evaluate().isNotEmpty;
      UiSnack.hide();
      await tester.pump();
      // המתנה לאיפוס דגל _commentaryCopyHandled (100ms) בין לחיצות.
      await tester.pump(const Duration(milliseconds: 200));
      return !noText && anySnack;
    }

    await selectInCommentary();
    expect(
      await pressCtrlCAndCopyReached(),
      isTrue,
      reason: 'העתקה ראשונה אחרי בחירה אמורה לעבוד',
    );

    // לחיצה ימנית על אמצע הבחירה — פותחת תפריט הקשר ומשמרת את הבחירה.
    final rect = tester.getRect(find.textContaining('פירוש ארוך').first);
    final rightClick = await tester.startGesture(
      rect.center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await rightClick.up();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(
      await pressCtrlCAndCopyReached(),
      isTrue,
      reason: 'Ctrl+C אחרי לחיצה ימנית משמרת-בחירה חייב להמשיך לעבוד',
    );

    // גם בחירה טרייה של אותו טקסט (שאינה פולטת אירוע שינוי) ממשיכה לעבוד.
    await selectInCommentary();
    expect(
      await pressCtrlCAndCopyReached(),
      isTrue,
      reason: 'בחירה מחדש אחרי לחיצה ימנית חייבת לאפשר העתקה',
    );
  });
}

class _FakeNotesRepository implements PersonalNotesRepository {
  @override
  Future<List<PersonalNote>> loadNotes(String bookId, {int? categoryId}) async {
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TextBookLoaded _loadedState() {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה ראשית ראשונה'],
    fontSize: 18,
    showSplitView: false,
    showPageShapeView: true,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
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
