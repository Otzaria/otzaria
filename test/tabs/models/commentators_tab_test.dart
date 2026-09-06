import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../helpers/memory_settings_cache.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  group('CommentatorsTab', () {
    test(
      'נבנה עם השורה הנבחרת מה-sourceTab ומאתחל bloc עצמאי לאותו אינדקס',
      () {
        final sourceTab = TextBookTab(
          book: TextBook(title: 'ספר בדיקה'),
          index: 3,
          blocOverride: _LoadedTextBookBloc(
            _loadedState(
              selectedIndex: 17,
              visibleIndices: const [17, 18],
            ),
          ),
        );
        addTearDown(sourceTab.dispose);

        final tab = CommentatorsTab(sourceTab: sourceTab);
        addTearDown(tab.dispose);

        expect(tab.title, 'מפרשים | ספר בדיקה');
        expect(tab.initialSelectedLine, 17);

        final initialState = tab.bloc.state as TextBookInitial;
        expect(initialState.book.title, 'ספר בדיקה');
        expect(initialState.index, 17);
        expect(initialState.commentators, isEmpty);
      },
    );

    test('כשאין selectedIndex נופל ל-visibleIndices הראשון', () {
      final sourceTab = TextBookTab(
        book: TextBook(title: 'ספר בדיקה'),
        index: 5,
        blocOverride: _LoadedTextBookBloc(
          _loadedState(
            selectedIndex: null,
            visibleIndices: const [42, 43],
          ),
        ),
      );
      addTearDown(sourceTab.dispose);

      final tab = CommentatorsTab(sourceTab: sourceTab);
      addTearDown(tab.dispose);

      final initialState = tab.bloc.state as TextBookInitial;
      expect(tab.initialSelectedLine, isNull);
      expect(initialState.index, 42);
    });

    test('fromJson משחזר sourceTab ו-isPinned', () {
      final restored = CommentatorsTab.fromJson({
        'type': 'CommentatorsTab',
        'isPinned': true,
        'initialIndex': 11,
        'bookTitle': 'ספר משוחזר',
        'sourceTab': {
          'type': 'TextBookTab',
          'title': 'ספר משוחזר',
          'initalIndex': 11,
          'commentators': const <String>[],
          'book': TextBook(title: 'ספר משוחזר').toJson(),
          'splitedView': true,
          'showPageShapeView': false,
          'showLeftPane': false,
          'isPinned': false,
        },
      });
      addTearDown(restored.dispose);

      expect(restored.isPinned, isTrue);
      expect(restored.sourceTab.book.title, 'ספר משוחזר');
      expect((restored.bloc.state as TextBookInitial).index, 11);
    });

    test('dispose סוגר גם את sourceTab המשוחזר מ-fromJson', () async {
      final restored = CommentatorsTab.fromJson({
        'type': 'CommentatorsTab',
        'isPinned': false,
        'initialIndex': 2,
        'bookTitle': 'ספר משוחזר',
        'sourceTab': {
          'type': 'TextBookTab',
          'title': 'ספר משוחזר',
          'initalIndex': 2,
          'commentators': const <String>[],
          'book': TextBook(title: 'ספר משוחזר').toJson(),
          'splitedView': true,
          'showPageShapeView': false,
          'showLeftPane': false,
          'isPinned': false,
        },
      });

      expect(restored.sourceTab.bloc.isClosed, isFalse);
      restored.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(restored.bloc.isClosed, isTrue);
      expect(restored.sourceTab.bloc.isClosed, isTrue);
    });

    test('נבנה עם בחירת המפרשים מה-sourceTab הטעון', () {
      final sourceTab = TextBookTab(
        book: TextBook(title: 'ספר בדיקה'),
        index: 3,
        blocOverride: _LoadedTextBookBloc(
          _loadedState(
            selectedIndex: 17,
            visibleIndices: const [17],
            activeCommentators: const ['רש"י', 'תוספות'],
          ),
        ),
      );
      addTearDown(sourceTab.dispose);

      final tab = CommentatorsTab(sourceTab: sourceTab);
      addTearDown(tab.dispose);

      expect(tab.selectedCommentators, ['רש"י', 'תוספות']);
    });

    test('toJson משמר את בחירת המפרשים ו-fromJson משחזר אותה', () {
      final sourceTab = TextBookTab(
        book: TextBook(title: 'ספר בדיקה'),
        index: 8,
      );
      addTearDown(sourceTab.dispose);

      final tab = CommentatorsTab(sourceTab: sourceTab)
        ..selectedCommentators = ['רש"י', 'רמב"ן'];
      addTearDown(tab.dispose);

      final json = tab.toJson();
      expect(json['selectedCommentators'], ['רש"י', 'רמב"ן']);

      final restored = CommentatorsTab.fromJson(json);
      addTearDown(restored.dispose);
      expect(restored.selectedCommentators, ['רש"י', 'רמב"ן']);
    });

    test('fromJson מכבד בחירה null שמורה (הצגת כל המפרשים)', () {
      final restored = CommentatorsTab.fromJson({
        'type': 'CommentatorsTab',
        'isPinned': false,
        'initialIndex': 2,
        'bookTitle': 'ספר משוחזר',
        'selectedCommentators': null,
        'sourceTab': {
          'type': 'TextBookTab',
          'title': 'ספר משוחזר',
          'initalIndex': 2,
          'commentators': const ['רש"י'],
          'book': TextBook(title: 'ספר משוחזר').toJson(),
          'splitedView': true,
          'showPageShapeView': false,
          'showLeftPane': false,
          'isPinned': false,
        },
      });
      addTearDown(restored.dispose);

      expect(restored.selectedCommentators, isNull);
    });

    test('fromJson ישן (ללא selectedCommentators) נופל לבחירת ה-sourceTab', () {
      final restored = CommentatorsTab.fromJson({
        'type': 'CommentatorsTab',
        'isPinned': false,
        'initialIndex': 2,
        'bookTitle': 'ספר משוחזר',
        'sourceTab': {
          'type': 'TextBookTab',
          'title': 'ספר משוחזר',
          'initalIndex': 2,
          'commentators': const ['רש"י', 'אבן עזרא'],
          'book': TextBook(title: 'ספר משוחזר').toJson(),
          'splitedView': true,
          'showPageShapeView': false,
          'showLeftPane': false,
          'isPinned': false,
        },
      });
      addTearDown(restored.dispose);

      expect(restored.selectedCommentators, ['רש"י', 'אבן עזרא']);
    });

    test('clone מעתיק את בחירת המפרשים', () {
      final sourceTab = TextBookTab(
        book: TextBook(title: 'ספר בדיקה'),
        index: 8,
      );
      addTearDown(sourceTab.dispose);

      final tab = CommentatorsTab(sourceTab: sourceTab)
        ..selectedCommentators = ['רש"י'];
      addTearDown(tab.dispose);

      final copy = tab.clone() as CommentatorsTab;
      addTearDown(copy.dispose);

      expect(copy.selectedCommentators, ['רש"י']);
      copy.selectedCommentators!.add('תוספות');
      expect(tab.selectedCommentators, ['רש"י']);
    });

    test('fromJson קורא את מיקום הכרטיסיה ולא את זה של ספר המקור', () {
      // ⚠️ שני ערכים **שונים** בכוונה: מיקום זהה אינו יכול להבחין מי נקרא.
      final restored = CommentatorsTab.fromJson({
        'type': 'CommentatorsTab',
        'isPinned': false,
        'initialIndex': 40,
        'bookTitle': 'ספר משוחזר',
        'sourceTab': {
          'type': 'TextBookTab',
          'title': 'ספר משוחזר',
          'initalIndex': 1,
          'commentators': const <String>[],
          'book': TextBook(title: 'ספר משוחזר').toJson(),
          'splitedView': true,
          'showPageShapeView': false,
          'showLeftPane': false,
          'isPinned': false,
        },
      });
      addTearDown(restored.dispose);

      expect(restored.startIndex, 40);
      expect((restored.bloc.state as TextBookInitial).index, 40);
      // שמירה חוזרת אינה מחזירה את המיקום לאחור.
      expect(restored.toJson()['initialIndex'], 40);
    });

    test('clone משמר את מיקום הכרטיסיה ולא נופל למיקום ספר המקור', () {
      final sourceTab = TextBookTab(
        book: TextBook(title: 'ספר בדיקה'),
        index: 1,
        blocOverride: _LoadedTextBookBloc(
          _loadedState(selectedIndex: 40, visibleIndices: const [40]),
        ),
      );
      addTearDown(sourceTab.dispose);

      final tab = CommentatorsTab(sourceTab: sourceTab);
      addTearDown(tab.dispose);
      expect(tab.startIndex, 40);

      final copy = tab.clone() as CommentatorsTab;
      addTearDown(copy.dispose);

      expect(copy.startIndex, 40);
      expect((copy.bloc.state as TextBookInitial).index, 40);
    });

    test('toJson שומר sourceTab ואת סוג הטאב', () {
      final sourceTab = TextBookTab(
        book: TextBook(title: 'ספר בדיקה'),
        index: 8,
      );
      addTearDown(sourceTab.dispose);

      final tab = CommentatorsTab(sourceTab: sourceTab);
      addTearDown(tab.dispose);

      final json = tab.toJson();
      expect(json['type'], 'CommentatorsTab');
      expect(json['bookTitle'], 'ספר בדיקה');
      expect(json['sourceTab'], isA<Map<String, dynamic>>());
      expect(
        (json['sourceTab'] as Map<String, dynamic>)['type'],
        'TextBookTab',
      );
    });
  });
}

class _LoadedTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _LoadedTextBookBloc(super.state) {
    on<TextBookEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TextBookLoaded _loadedState({
  required int? selectedIndex,
  required List<int> visibleIndices,
  List<String> activeCommentators = const <String>[],
}) => TextBookLoaded(
  book: TextBook(title: 'ספר בדיקה'),
  showLeftPane: false,
  content: const ['א', 'ב', 'ג'],
  fontSize: 18,
  showSplitView: true,
  showPageShapeView: false,
  activeCommentators: activeCommentators,
  commentatorGroups: const [],
  availableCommentators: const <String>[],
  links: const <Link>[],
  visibleLinks: const <Link>[],
  linksByLine: const {},
  tableOfContents: const [],
  removeNikud: false,
  visibleIndices: visibleIndices,
  selectedIndex: selectedIndex,
  pinLeftPane: false,
  searchText: '',
  scrollController: ItemScrollController(),
  positionsListener: ItemPositionsListener.create(),
);
