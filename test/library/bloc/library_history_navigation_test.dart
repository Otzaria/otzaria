import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

import '../../helpers/memory_settings_cache.dart';

class _Repository extends Fake implements DataRepository {
  late Library tree;

  @override
  Future<Library> get library async => tree;
}

Library _library() {
  final root = Library(categories: []);
  for (final title in ['הלכה', 'תנ״ך']) {
    root.subCategories.add(
      Category(
        title: title,
        description: '',
        shortDescription: '',
        order: 1,
        subCategories: [],
        books: [],
        parent: root,
      ),
    );
  }
  return root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Library library;
  late Category halacha;
  late Category tanach;
  late _Repository repository;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    library = _library();
    halacha = library.subCategories[0];
    tanach = library.subCategories[1];
    repository = _Repository()..tree = library;
  });

  LibraryBloc build() =>
      LibraryBloc(repository: repository)
        ..emit(LibraryState(library: library, currentCategory: library));

  Matcher at(String path) => isA<LibraryState>().having(
    (state) => state.currentCategory?.path,
    'currentCategory.path',
    path,
  );

  blocTest<LibraryBloc, LibraryState>(
    'בקשות חזרה וקדימה רצופות מעובדות מול המיקום שהוצג בכל צעד',
    build: build,
    act: (bloc) => bloc
      ..add(NavigateToCategory(halacha))
      ..add(NavigateToCategory(tanach))
      ..add(const TravelLibraryHistory())
      ..add(const TravelLibraryHistory())
      ..add(const TravelLibraryHistory(forward: true))
      ..add(const TravelLibraryHistory(forward: true)),
    expect: () => [
      at(halacha.path),
      at(tanach.path),
      at(halacha.path),
      at('/'),
      at(halacha.path),
      at(tanach.path),
    ],
    verify: (bloc) {
      expect(bloc.navigationHistory.previous, halacha.path);
      expect(bloc.navigationHistory.canGoForward, isFalse);
    },
  );

  blocTest<LibraryBloc, LibraryState>(
    'חזרה וקדימה מבחינות בין תיקיות באותו שם',
    build: build,
    act: (bloc) {
      final attached = Category(
        title: halacha.title,
        pathSegment: Category.attachedRootPathSegment(halacha.title),
        description: '',
        shortDescription: '',
        order: 2,
        subCategories: [],
        books: [],
        parent: library,
      );
      library.subCategories.add(attached);
      bloc
        ..add(NavigateToCategory(halacha))
        ..add(NavigateToCategory(attached))
        ..add(const TravelLibraryHistory())
        ..add(const TravelLibraryHistory(forward: true));
    },
    expect: () => [
      at(halacha.path),
      at(library.subCategories.last.path),
      at(halacha.path),
      at(library.subCategories.last.path),
    ],
    verify: (bloc) {
      expect(bloc.state.currentCategory, same(library.subCategories.last));
    },
  );

  blocTest<LibraryBloc, LibraryState>(
    'ניווט ידני בין בקשות מבטל קדימה ונרשם פעם אחת',
    build: build,
    act: (bloc) => bloc
      ..add(NavigateToCategory(halacha))
      ..add(NavigateToCategory(tanach))
      ..add(const TravelLibraryHistory())
      ..add(NavigateToCategory(library))
      ..add(const TravelLibraryHistory(forward: true))
      ..add(const TravelLibraryHistory())
      ..add(const TravelLibraryHistory()),
    expect: () => [
      at(halacha.path),
      at(tanach.path),
      at(halacha.path),
      at('/'),
      at(halacha.path),
      at('/'),
    ],
    verify: (bloc) {
      expect(bloc.navigationHistory.canGoBack, isFalse);
      expect(bloc.navigationHistory.next, halacha.path);
    },
  );

  blocTest<LibraryBloc, LibraryState>(
    'ניווט שלא משנה מצב אינו תוקע בקשה ואינו מבטל קדימה',
    build: build,
    act: (bloc) => bloc
      ..add(const TravelLibraryHistory())
      ..add(NavigateToCategory(halacha))
      ..add(NavigateToCategory(tanach))
      ..add(const TravelLibraryHistory())
      ..add(NavigateToCategory(halacha))
      ..add(NavigateToCategory(halacha))
      ..add(const TravelLibraryHistory(forward: true)),
    expect: () => [
      at(halacha.path),
      at(tanach.path),
      at(halacha.path),
      at(tanach.path),
    ],
    verify: (bloc) {
      expect(bloc.navigationHistory.previous, halacha.path);
      expect(bloc.navigationHistory.canGoForward, isFalse);
    },
  );

  blocTest<LibraryBloc, LibraryState>(
    'כשכל יעדי הקדימה נמחקו המיקום נשאר אמיתי והבקשה הבאה פועלת',
    build: build,
    act: (bloc) async {
      final reachedRoot = bloc.stream.firstWhere(
        (state) => identical(state.currentCategory, library),
      );
      bloc
        ..add(NavigateToCategory(halacha))
        ..add(NavigateToCategory(tanach))
        ..add(const TravelLibraryHistory())
        ..add(const TravelLibraryHistory());
      await reachedRoot;
      library.subCategories.clear();
      final other = _library().subCategories.first
        ..title = 'חדש'
        ..parent = library;
      library.subCategories.add(other);
      bloc
        ..add(const TravelLibraryHistory(forward: true))
        ..add(NavigateToCategory(other))
        ..add(const TravelLibraryHistory());
    },
    expect: () => [
      at(halacha.path),
      at(tanach.path),
      at(halacha.path),
      at('/'),
      at('/חדש'),
      at('/'),
    ],
    verify: (bloc) {
      expect(bloc.navigationHistory.canGoBack, isFalse);
      expect(bloc.navigationHistory.next, '/חדש');
    },
  );

  blocTest<LibraryBloc, LibraryState>(
    'בנייה מחדש של העץ שומרת קדימה ופותרת את היעד בעץ החדש',
    build: build,
    act: (bloc) async {
      final reachedHalacha = bloc.stream.firstWhere(
        (state) =>
            identical(state.currentCategory, halacha) &&
            bloc.navigationHistory.canGoForward,
      );
      bloc
        ..add(NavigateToCategory(halacha))
        ..add(NavigateToCategory(tanach))
        ..add(const TravelLibraryHistory());
      await reachedHalacha;
      repository.tree = _library();
      final reloaded = bloc.stream.firstWhere(
        (state) => !identical(state.library, library),
      );
      bloc.add(const LibraryChangedInOtherWindow());
      await reloaded;
      bloc.add(const TravelLibraryHistory(forward: true));
    },
    expect: () => [
      at(halacha.path),
      at(tanach.path),
      at(halacha.path),
      at(halacha.path),
      at(tanach.path),
    ],
    verify: (bloc) {
      expect(bloc.state.currentCategory, isNot(same(tanach)));
      expect(bloc.navigationHistory.previous, halacha.path);
      expect(bloc.navigationHistory.canGoForward, isFalse);
    },
  );

  blocTest<LibraryBloc, LibraryState>(
    'התיקייה הראשונה שהוצגה אינה יוצרת ביקור פיקטיבי בשורש',
    build: () =>
        LibraryBloc(repository: repository)
          ..emit(LibraryState(library: library, currentCategory: halacha)),
    act: (bloc) => bloc.add(const TravelLibraryHistory()),
    expect: () => <LibraryState>[],
    verify: (bloc) {
      expect(bloc.state.currentCategory, same(halacha));
      expect(bloc.navigationHistory.canGoBack, isFalse);
      expect(bloc.navigationHistory.canGoForward, isFalse);
    },
  );

  test('סגירת ה־Bloc משחררת את מודל ההיסטוריה', () async {
    final bloc = build();
    final history = bloc.navigationHistory;
    await bloc.close();
    expect(() => history.addListener(() {}), throwsFlutterError);
  });
}
