import 'package:bloc_test/bloc_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import '../../test_helpers/memory_cache_provider.dart';

class _FakeTextBookRepository extends TextBookRepository {
  _FakeTextBookRepository() : super(fileSystem: FileSystemData.instance);
}

/// ApplyDisplayPatch כותב עקיפה לחריץ של התצוגה הפעילה בלבד, וClearDisplayOverrides
/// מנקה את כולן.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TextBookBloc bloc;
  late TextBook book;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    book = TextBook(title: 'ספר בדיקה');
    bloc = TextBookBloc(
      repository: _FakeTextBookRepository(),
      initialState: TextBookInitial.named(book, 0, true, const []),
    );
  });

  tearDown(() => bloc.close());

  TextBookLoaded seed({bool pageShape = false}) => TextBookLoaded(
    book: book,
    content: const ['שורה א'],
    fontSize: 20,
    showLeftPane: true,
    showSplitView: false,
    showPageShapeView: pageShape,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    pinLeftPane: false,
    searchText: '',
  );

  blocTest<TextBookBloc, TextBookState>(
    'טלאי על הגוף מסתיר ניקוד בגוף ובמפרשים (ירושה)',
    build: () => bloc,
    seed: seed,
    act: (bloc) => bloc.add(
      const ApplyDisplayPatch(
        target: TextTarget.body,
        patch: TextDisplayPatch(nikud: MarkVisibility.hide),
      ),
    ),
    expect: () => [
      isA<TextBookLoaded>()
          .having((s) => s.removeNikud, 'גוף', isTrue)
          .having((s) => s.commentaryRemoveNikud, 'מפרשים', isTrue),
    ],
  );

  blocTest<TextBookBloc, TextBookState>(
    'טלאי על המפרשים אינו משנה את הגוף',
    build: () => bloc,
    seed: seed,
    act: (bloc) => bloc.add(
      const ApplyDisplayPatch(
        target: TextTarget.commentary,
        patch: TextDisplayPatch(punctuation: MarkVisibility.hide),
      ),
    ),
    expect: () => [
      isA<TextBookLoaded>()
          .having((s) => s.removePunctuation, 'גוף', isFalse)
          .having((s) => s.commentaryRemovePunctuation, 'מפרשים', isTrue),
    ],
  );

  blocTest<TextBookBloc, TextBookState>(
    'בצורת הדף הטלאי נכתב לחריץ צורת הדף בלבד',
    build: () => bloc,
    seed: () => seed(pageShape: true),
    act: (bloc) => bloc.add(
      const ApplyDisplayPatch(
        target: TextTarget.body,
        patch: TextDisplayPatch(teamim: TeamimVisibility.hide),
      ),
    ),
    expect: () => [
      isA<TextBookLoaded>()
          .having((s) => s.bodyDisplayProfile.removeTeamim, 'צורת הדף', isTrue)
          .having(
            (s) => s
                .displayProfile(target: TextTarget.body, view: TextView.regular)
                .removeTeamim,
            'רגילה',
            isFalse,
          ),
    ],
  );

  blocTest<TextBookBloc, TextBookState>(
    'טלאי ריק אינו פולט state',
    build: () => bloc,
    seed: seed,
    act: (bloc) => bloc.add(
      const ApplyDisplayPatch(
        target: TextTarget.body,
        patch: TextDisplayPatch.empty,
      ),
    ),
    expect: () => const <TextBookState>[],
  );

  blocTest<TextBookBloc, TextBookState>(
    'שינוי שהוחזר לערך הקודם נמחק מהעקיפה',
    build: () => bloc,
    seed: seed,
    act: (bloc) => bloc
      ..add(
        const ApplyDisplayPatch(
          target: TextTarget.body,
          patch: TextDisplayPatch(punctuation: MarkVisibility.hide),
        ),
      )
      ..add(
        const ApplyDisplayPatch(
          target: TextTarget.body,
          patch: TextDisplayPatch(punctuation: MarkVisibility.show),
        ),
      ),
    expect: () => [
      isA<TextBookLoaded>().having(
        (s) => s.displayOverrides.isEmpty,
        'עקיפות',
        isFalse,
      ),
      isA<TextBookLoaded>()
          .having((s) => s.displayOverrides.isEmpty, 'עקיפות', isTrue)
          .having((s) => s.removePunctuation, 'פיסוק', isFalse),
    ],
  );

  blocTest<TextBookBloc, TextBookState>(
    'שדה שחזר לערך הקודם נמחק, ושאר השדות בעקיפה נשארים',
    build: () => bloc,
    seed: seed,
    act: (bloc) => bloc
      ..add(
        const ApplyDisplayPatch(
          target: TextTarget.commentary,
          patch: TextDisplayPatch(
            nikud: MarkVisibility.hide,
            punctuation: MarkVisibility.hide,
          ),
        ),
      )
      ..add(
        const ApplyDisplayPatch(
          target: TextTarget.commentary,
          patch: TextDisplayPatch(nikud: MarkVisibility.show),
        ),
      ),
    skip: 1,
    expect: () => [
      isA<TextBookLoaded>().having(
        (s) => s.displayOverrides.patchFor(TextDisplaySlot.commentaryDisplay),
        'מפרשים',
        const TextDisplayPatch(punctuation: MarkVisibility.hide),
      ),
    ],
  );

  blocTest<TextBookBloc, TextBookState>(
    'ערך מפורש למפרשים שזהה לעקיפה של הגוף נשאר, ולא עוקב אחרי הגוף',
    build: () => bloc,
    seed: seed,
    act: (bloc) => bloc
      ..add(
        const ApplyDisplayPatch(
          target: TextTarget.body,
          patch: TextDisplayPatch(nikud: MarkVisibility.hide),
        ),
      )
      ..add(
        const ApplyDisplayPatch(
          target: TextTarget.commentary,
          patch: TextDisplayPatch(nikud: MarkVisibility.hide),
        ),
      )
      ..add(
        const ApplyDisplayPatch(
          target: TextTarget.body,
          patch: TextDisplayPatch(nikud: MarkVisibility.show),
        ),
      ),
    skip: 1,
    expect: () => [
      isA<TextBookLoaded>().having(
        (s) => s.displayOverrides.patchFor(TextDisplaySlot.commentaryDisplay),
        'מפרשים',
        const TextDisplayPatch(nikud: MarkVisibility.hide),
      ),
      isA<TextBookLoaded>()
          .having((s) => s.removeNikud, 'גוף', isFalse)
          .having((s) => s.commentaryRemoveNikud, 'מפרשים', isTrue)
          .having(
            (s) => s.displayOverrides.patchFor(TextDisplaySlot.root),
            'גוף',
            TextDisplayPatch.empty,
          ),
    ],
  );

  blocTest<TextBookBloc, TextBookState>(
    'בחירה מפורשת למפרשים נשמרת גם כשהיא שווה לערך שנורש',
    build: () => bloc,
    seed: seed,
    act: (bloc) => bloc
      ..add(
        const ApplyDisplayPatch(
          target: TextTarget.commentary,
          patch: TextDisplayPatch(nikud: MarkVisibility.show),
        ),
      )
      ..add(
        const ApplyDisplayPatch(
          target: TextTarget.commentary,
          patch: TextDisplayPatch(punctuation: MarkVisibility.hide),
        ),
      )
      ..add(
        const ApplyDisplayPatch(
          target: TextTarget.body,
          patch: TextDisplayPatch(nikud: MarkVisibility.hide),
        ),
      ),
    skip: 2,
    expect: () => [
      isA<TextBookLoaded>()
          .having((s) => s.removeNikud, 'גוף', isTrue)
          .having((s) => s.commentaryRemoveNikud, 'מפרשים', isFalse)
          .having((s) => s.commentaryRemovePunctuation, 'פיסוק', isTrue),
    ],
  );

  blocTest<TextBookBloc, TextBookState>(
    'בצורת הדף ערך שחזר לקודם נמחק מחריץ צורת הדף',
    build: () => bloc,
    seed: () => seed(pageShape: true),
    act: (bloc) => bloc
      ..add(
        const ApplyDisplayPatch(
          target: TextTarget.body,
          patch: TextDisplayPatch(teamim: TeamimVisibility.hide),
        ),
      )
      ..add(
        const ApplyDisplayPatch(
          target: TextTarget.body,
          patch: TextDisplayPatch(teamim: TeamimVisibility.followNikud),
        ),
      ),
    skip: 1,
    expect: () => [
      isA<TextBookLoaded>().having(
        (s) => s.displayOverrides.isEmpty,
        'עקיפות',
        isTrue,
      ),
    ],
  );

  test(
    'ערך מפורש למפרשים ששונה מעקיפת הגוף נכתב, גם כשהוא שווה לברירת המחדל',
    () async {
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      bloc.emit(seed());
      bloc.add(
        const ApplyDisplayPatch(
          target: TextTarget.body,
          patch: TextDisplayPatch(nikud: MarkVisibility.hide),
        ),
      );
      await bloc.stream.first;
      expect((bloc.state as TextBookLoaded).commentaryRemoveNikud, isTrue);

      // המשתמש מדליק את הניקוד במקטע המפרשים בלבד.
      bloc.add(
        const ApplyDisplayPatch(
          target: TextTarget.commentary,
          patch: TextDisplayPatch(nikud: MarkVisibility.show),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final state = bloc.state as TextBookLoaded;
      expect(state.removeNikud, isTrue, reason: 'הגוף');
      expect(state.commentaryRemoveNikud, isFalse, reason: 'המפרשים');
    },
  );

  blocTest<TextBookBloc, TextBookState>(
    'ClearDisplayOverrides מחזיר לברירת המחדל',
    build: () => bloc,
    seed: () => seed().copyWith(removeNikud: true),
    act: (bloc) => bloc.add(const ClearDisplayOverrides()),
    expect: () => [
      isA<TextBookLoaded>()
          .having((s) => s.removeNikud, 'ניקוד', isFalse)
          .having((s) => s.displayOverrides.isEmpty, 'עקיפות', isTrue),
    ],
  );
}
