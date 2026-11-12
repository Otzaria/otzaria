import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/models/bookmark_group.dart';
import 'package:otzaria/bookmarks/repository/bookmark_repository.dart';
import 'package:otzaria/models/books.dart';

// ─── Fake repository ─────────────────────────────────────────────────────────

class _FakeGroupsRepository implements BookmarkRepository {
  List<BookmarkGroup> groups;
  int saveGroupsCallCount = 0;

  _FakeGroupsRepository({List<BookmarkGroup>? initial})
    : groups = initial ?? [];

  @override
  Future<List<Bookmark>> loadBookmarks() async => [];

  @override
  Future<List<Bookmark>> mutateBookmarks(
    List<Bookmark> Function(List<Bookmark> current) apply,
  ) async => apply(const []);

  @override
  Future<void> clearBookmarks() async {}

  @override
  Future<List<BookmarkGroup>> loadGroups() async => List.from(groups);

  @override
  Future<List<BookmarkGroup>> mutateGroups(
    List<BookmarkGroup> Function(List<BookmarkGroup> current) apply,
  ) async {
    groups = List.from(apply(List.from(groups)));
    saveGroupsCallCount++;
    return List.from(groups);
  }

  @override
  Stream<void> get remoteChanges => const Stream<void>.empty();

  @override
  Stream<void> get groupsRemoteChanges => const Stream<void>.empty();

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

Bookmark _bookmark({String bookTitle = 'ספר א', int index = 0}) => Bookmark(
  ref: '$bookTitle מיקום $index',
  book: TextBook(title: bookTitle, filePath: '/fake/$bookTitle.txt'),
  index: index,
);

BookmarkGroup _group({
  String? id,
  String name = 'פסחים דף ט',
  List<String> bookTitles = const ['ספר א', 'ספר ב'],
}) => BookmarkGroup(
  id: id,
  name: name,
  items: bookTitles.map((t) => _bookmark(bookTitle: t)).toList(),
);

Future<BookmarkBloc> _makeBloc({List<BookmarkGroup>? initial}) async {
  final bloc = BookmarkBloc(_FakeGroupsRepository(initial: initial));
  await Future<void>.delayed(Duration.zero);
  return bloc;
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BookmarkGroup model', () {
    test('toJson ו-fromJson עוברים סיבוב מלא', () {
      final original = BookmarkGroup(
        name: 'פסחים דף ט',
        items: [_bookmark(bookTitle: 'פסחים', index: 17)],
        createdAt: DateTime(2026, 8, 25, 12),
      );

      final restored = BookmarkGroup.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.items, hasLength(1));
      expect(restored.items.first.book.title, 'פסחים');
      expect(restored.items.first.index, 17);
      expect(restored.createdAt, original.createdAt);
    });

    test('id נוצר אוטומטית וייחודי', () {
      final a = _group();
      final b = _group();
      expect(a.id, isNotEmpty);
      expect(a.id, isNot(b.id));
    });

    test('overlapWith — קבוצות זהות מחזירות 1', () {
      final group = _group(bookTitles: ['א', 'ב', 'ג']);
      expect(group.overlapWith(group.bookIdentities), 1.0);
    });

    test('overlapWith — חפיפה חלקית ביחס לקבוצה הגדולה', () {
      final saved = _group(bookTitles: ['א', 'ב', 'ג', 'ד', 'ה']);
      final incoming = _group(
        bookTitles: ['א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ז', 'ח'],
      );
      // חיתוך 5 מתוך הגדולה (8) = 0.625
      expect(saved.overlapWith(incoming.bookIdentities), closeTo(0.625, 1e-9));
    });

    test('overlapWith — קבוצות זרות מחזירות 0', () {
      final a = _group(bookTitles: ['א', 'ב']);
      final b = _group(bookTitles: ['ג', 'ד']);
      expect(a.overlapWith(b.bookIdentities), 0);
    });
  });

  group('BookmarkBloc groups', () {
    test('טוען קבוצות קיימות ב-init', () async {
      final bloc = await _makeBloc(initial: [_group(name: 'סוגיא')]);
      expect(bloc.state.groups, hasLength(1));
      expect(bloc.state.groups.first.name, 'סוגיא');
    });

    test('addGroup מוסיף ושומר', () async {
      final repo = _FakeGroupsRepository();
      final bloc = BookmarkBloc(repo);
      await Future<void>.delayed(Duration.zero);

      bloc.addGroup(_group());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.groups, hasLength(1));
      expect(repo.saveGroupsCallCount, 1);
      expect(repo.groups, hasLength(1));
    });

    test('replaceGroup מחליף תוכן ושומר את המזהה', () async {
      final original = _group(name: 'פסחים דף ט');
      final bloc = await _makeBloc(initial: [original]);

      final replaced = bloc.replaceGroup(
        original.id,
        _group(name: 'פסחים דף יד', bookTitles: ['פסחים', 'רמב"ם']),
      );

      expect(replaced, isTrue);
      expect(bloc.state.groups, hasLength(1));
      expect(bloc.state.groups.first.id, original.id);
      expect(bloc.state.groups.first.name, 'פסחים דף יד');
      expect(bloc.state.groups.first.items, hasLength(2));
    });

    test('replaceGroup עם מזהה לא קיים מחזיר false', () async {
      final bloc = await _makeBloc(initial: [_group()]);
      expect(bloc.replaceGroup('לא-קיים', _group()), isFalse);
    });

    test('removeGroup מסיר לפי מזהה', () async {
      final a = _group(name: 'א');
      final b = _group(name: 'ב');
      final bloc = await _makeBloc(initial: [a, b]);

      expect(bloc.removeGroup(a.id), isTrue);
      expect(bloc.state.groups.single.name, 'ב');
      expect(bloc.removeGroup(a.id), isFalse);
    });

    test('renameGroup משנה שם; שם ריק לא משנה דבר', () async {
      final group = _group(name: 'ישן');
      final bloc = await _makeBloc(initial: [group]);

      bloc.renameGroup(group.id, ' חדש ');
      expect(bloc.state.groups.single.name, 'חדש');

      bloc.renameGroup(group.id, '   ');
      expect(bloc.state.groups.single.name, 'חדש');
    });

    test('findSimilarGroup מזהה קבוצה זהה', () async {
      final saved = _group(bookTitles: ['פסחים', 'שו"ע', 'רמב"ם']);
      final bloc = await _makeBloc(initial: [saved]);

      final incoming = _group(bookTitles: ['פסחים', 'שו"ע', 'רמב"ם']);
      expect(bloc.findSimilarGroup(incoming.bookIdentities)?.id, saved.id);
    });

    test('findSimilarGroup מזהה חפיפת רוב (ספר נוסף נפתח)', () async {
      final saved = _group(bookTitles: ['פסחים', 'שו"ע', 'רמב"ם']);
      final bloc = await _makeBloc(initial: [saved]);

      // 3 מתוך 4 = 0.75 ≥ סף
      final incoming = _group(bookTitles: ['פסחים', 'שו"ע', 'רמב"ם', 'טור']);
      expect(bloc.findSimilarGroup(incoming.bookIdentities)?.id, saved.id);
    });

    test('findSimilarGroup לא מזהה חפיפת מיעוט', () async {
      final saved = _group(bookTitles: ['פסחים', 'שו"ע', 'רמב"ם', 'טור']);
      final bloc = await _makeBloc(initial: [saved]);

      // חיתוך 1 מתוך 4 = 0.25 < סף
      final incoming = _group(bookTitles: ['פסחים']);
      expect(bloc.findSimilarGroup(incoming.bookIdentities), isNull);
    });

    test('findSimilarGroup מחזיר את החופפת ביותר מבין כמה', () async {
      final partial = _group(name: 'חלקית', bookTitles: ['א', 'ב', 'ג']);
      final exact = _group(name: 'מדויקת', bookTitles: ['א', 'ב']);
      final bloc = await _makeBloc(initial: [partial, exact]);

      final incoming = _group(bookTitles: ['א', 'ב']);
      expect(bloc.findSimilarGroup(incoming.bookIdentities)?.name, 'מדויקת');
    });
  });
}
