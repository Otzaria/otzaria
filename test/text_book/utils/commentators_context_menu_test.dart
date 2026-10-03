import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:otzaria/text_book/utils/commentators_context_menu.dart';
import 'package:otzaria/user_content_import/models/user_import_models.dart';
import 'package:otzaria/user_content_import/repository/user_content_repository.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:path/path.dart' as path;

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  const groups = [
    CommentatorGroup(title: 'ראשונים', commentators: ['רש"י', 'רמב"ן']),
    CommentatorGroup(title: 'אחרונים', commentators: ['מלבי"ם']),
  ];
  const available = ['רש"י', 'רמב"ן', 'מלבי"ם'];

  List<String> labelsOf(List<AppContextMenuEntry> entries) => [
    for (final entry in entries)
      if (!entry.isDivider) entry.label!,
  ];

  AppContextMenuEntry entryNamed(
    List<AppContextMenuEntry> entries,
    String label,
  ) => entries.firstWhere((e) => !e.isDivider && e.label == label);

  List<AppContextMenuEntry> build({
    List<String> active = const [],
    List<String> availableCommentators = available,
    bool linksLoading = false,
    void Function(List<String> commentators, {required bool isAdding})?
    onChange,
    void Function()? onOpenPane,
    void Function()? onSelectMultiple,
  }) => buildCommentatorsContextMenuChildren(
    activeCommentators: active,
    availableCommentators: availableCommentators,
    commentatorGroups: groups,
    onCommentatorsChanged: onChange ?? (_, {required isAdding}) {},
    onOpenPane: onOpenPane,
    onSelectMultiple: onSelectMultiple,
    linksLoading: linksLoading,
  );

  group('buildCommentatorsContextMenuChildren', () {
    test('מציג את כל הקבוצות והמפרשים בסדר הדורות', () {
      expect(labelsOf(build()), [
        'הצג את כל המפרשים על פסקה זו',
        'הצג את כל ראשונים',
        'רש"י',
        'רמב"ן',
        'הצג את כל אחרונים',
        'מלבי"ם',
      ]);
    });

    test('פריטי פתיחת החלונית מוצגים רק כשסופקו callbacks', () {
      expect(
        labelsOf(build()).contains('פתח את חלונית המפרשים'),
        isFalse,
      );

      final labels = labelsOf(
        build(onOpenPane: () {}, onSelectMultiple: () {}),
      );
      expect(labels.first, 'פתח את חלונית המפרשים');
      expect(labels[1], 'בחר מפרשים מרובים');
    });

    test('סימון בחירה משקף את המפרשים הפעילים', () {
      final entries = build(active: const ['רש"י']);
      expect(entryNamed(entries, 'רש"י').isSelected, isTrue);
      expect(entryNamed(entries, 'רמב"ן').isSelected, isFalse);
      expect(entryNamed(entries, 'הצג את כל ראשונים').isSelected, isFalse);
      expect(
        entryNamed(entries, 'הצג את כל המפרשים על פסקה זו').isSelected,
        isFalse,
      );
    });

    test('כשכל המפרשים פעילים — "הצג את כל המפרשים" מסומן ומכבה את הבחירה', () {
      List<String>? updated;
      bool? adding;
      final entries = build(
        active: available,
        onChange: (commentators, {required isAdding}) {
          updated = commentators;
          adding = isAdding;
        },
      );

      final showAll = entryNamed(entries, 'הצג את כל המפרשים על פסקה זו');
      expect(showAll.isSelected, isTrue);
      showAll.onTap!();
      expect(updated, isEmpty);
      expect(adding, isFalse);
    });

    test('לחיצה על מפרש כבוי מוסיפה אותו ומסמנת הוספה', () {
      List<String>? updated;
      bool? adding;
      final entries = build(
        active: const ['רש"י'],
        onChange: (commentators, {required isAdding}) {
          updated = commentators;
          adding = isAdding;
        },
      );

      entryNamed(entries, 'רמב"ן').onTap!();
      expect(updated, ['רש"י', 'רמב"ן']);
      expect(adding, isTrue);
    });

    test(
      'לחיצה על מפרש פעיל אינה מסירה אותו ומסומנת כהוספה (פתיחת חלונית)',
      () {
        List<String>? updated;
        bool? adding;
        final entries = build(
          active: const ['רש"י', 'רמב"ן'],
          onChange: (commentators, {required isAdding}) {
            updated = commentators;
            adding = isAdding;
          },
        );

        entryNamed(entries, 'רש"י').onTap!();
        expect(updated, ['רש"י', 'רמב"ן']);
        expect(adding, isTrue);
      },
    );

    test('לחיצה על קבוצה פעילה מסירה את כל מפרשיה בלבד', () {
      List<String>? updated;
      bool? adding;
      final entries = build(
        active: const ['רש"י', 'רמב"ן', 'מלבי"ם'],
        onChange: (commentators, {required isAdding}) {
          updated = commentators;
          adding = isAdding;
        },
      );

      entryNamed(entries, 'הצג את כל ראשונים').onTap!();
      expect(updated, ['מלבי"ם']);
      expect(adding, isFalse);
    });

    test('קבוצה ריקה אינה יוצרת פריטים או מפריד', () {
      final entries = buildCommentatorsContextMenuChildren(
        activeCommentators: const [],
        availableCommentators: const ['רש"י'],
        commentatorGroups: const [],
        onCommentatorsChanged: (_, {required isAdding}) {},
      );
      expect(labelsOf(entries), ['הצג את כל המפרשים על פסקה זו']);
      expect(entries.where((e) => e.isDivider), isEmpty);
    });

    test('הקבוצות מסוננות למפרשי הפסקה בלבד, וקבוצה שהתרוקנה נעלמת', () {
      final entries = build(availableCommentators: const ['רמב"ן']);
      expect(labelsOf(entries), [
        'הצג את כל המפרשים על פסקה זו',
        'הצג את כל ראשונים',
        'רמב"ן',
      ]);
    });

    test('"הצג את כל [קבוצה]" מוסיף ומסיר רק את מפרשי הפסקה מהקבוצה', () {
      List<String>? updated;
      final entries = build(
        availableCommentators: const ['רמב"ן'],
        active: const ['רש"י'],
        onChange: (commentators, {required isAdding}) => updated = commentators,
      );
      entryNamed(entries, 'הצג את כל ראשונים').onTap!();
      expect(updated, ['רש"י', 'רמב"ן']);
    });

    test('בלי מפרשים לפסקה — תת-התפריט ריק (issue #1413)', () {
      final entries = build(
        availableCommentators: const [],
        onOpenPane: () {},
        onSelectMultiple: () {},
      );
      expect(entries, isEmpty);
      expect(hasEnabledAppContextMenuEntries(entries), isFalse);
    });

    test('בזמן טעינת הקישורים מוצג פריט "טוען" מושבת', () {
      final entries = build(
        availableCommentators: const [],
        linksLoading: true,
        onOpenPane: () {},
        onSelectMultiple: () {},
      );
      expect(labelsOf(entries), ['טוען מפרשים…']);
      expect(entries.single.enabled, isFalse);
      expect(hasEnabledAppContextMenuEntries(entries), isFalse);
    });
  });

  group('paragraphCommentators', () {
    Link commentaryLink(int line, String path) => Link(
      heRef: '',
      index1: line,
      path2: path,
      index2: 1,
      connectionType: 'commentary',
    );

    test('מחזיר רק מפרשים עם קישור-מפרש על הפסקה, בסדר הרשימה הכללית', () {
      final result = paragraphCommentators(
        availableCommentators: const ['רש"י', 'רמב"ן', 'מלבי"ם'],
        content: const ['א', 'ב'],
        paragraphIndex: 1,
        linksByLine: {
          1: [commentaryLink(1, r'מפרשים\רש"י.txt')],
          2: [
            commentaryLink(2, r'מפרשים\מלבי"ם.txt'),
            commentaryLink(2, r'מפרשים\רמב"ן.txt'),
            Link(
              heRef: '',
              index1: 2,
              path2: r'תנ"ך\בראשית.txt',
              index2: 1,
              connectionType: 'reference',
            ),
          ],
        },
      );
      expect(result, ['רמב"ן', 'מלבי"ם']);
    });

    test('שאילת הטווח מציגה גם מפרש שאינו פעיל בתפריט', () {
      final onParagraph = paragraphCommentators(
        availableCommentators: const ['רש"י', 'רמב"ן'],
        content: const ['פסקה'],
        paragraphIndex: 0,
        linksByLine: {
          1: [commentaryLink(1, 'רש"י')],
        },
        queriedCommentators: const ['רש"י', 'רמב"ן'],
      );
      final entries = build(
        active: const ['רש"י'],
        availableCommentators: onParagraph,
      );

      expect(entryNamed(entries, 'רש"י').isSelected, isTrue);
      expect(entryNamed(entries, 'רמב"ן').isSelected, isFalse);
    });

    test('"הערות" נכלל רק כשיש הערות inline בפסקה', () {
      const available = ['רש"י', kNotesCommentatorTitle];
      const content = [
        'בלי הערות',
        'עם <sup>1</sup><i class="footnote">הערה</i>',
      ];
      expect(
        paragraphCommentators(
          availableCommentators: available,
          content: content,
          paragraphIndex: 0,
          linksByLine: const {},
        ),
        isEmpty,
      );
      expect(
        paragraphCommentators(
          availableCommentators: available,
          content: content,
          paragraphIndex: 1,
          linksByLine: const {},
        ),
        [kNotesCommentatorTitle],
      );
    });
  });

  group('ParagraphCommentatorsCache — קישורי משתמש', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'otzaria-paragraph-commentators-',
      );
      await UserBooksDatabaseHolder.instance.close();
      AppPaths.debugOverrideDataRootPath(tempDir.path);
      await Settings.setValue<String>(
        SettingsRepository.keyDatabasesPath,
        path.join(tempDir.path, 'databases'),
      );
    });

    tearDown(() async {
      await UserBooksDatabaseHolder.instance.close();
      await Settings.setValue<String>(SettingsRepository.keyDatabasesPath, '');
      AppPaths.debugOverrideDataRootPath(null);
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('שאילת הטווח כוללת מפרש משתמש שאינו פעיל', () async {
      final userBooksRepository =
          await UserBooksDatabaseHolder.instance.repository;
      await UserContentRepository(userBooksRepository.database).upsertUserLink(
        const UserLinkRecord(
          sourceTitle: 'ספר בסיס',
          sourceIsUserBook: false,
          sourceLineIndex: 0,
          targetTitle: 'מפרש אישי',
          targetIsUserBook: true,
          targetLineIndex: 0,
          connectionType: 'COMMENTARY',
        ),
      );
      final cache = ParagraphCommentatorsCache();
      addTearDown(cache.dispose);
      final repository = TextBookRepository(fileSystem: FileSystemData());
      final book = TextBook(title: 'ספר בסיס');

      await cache.prefetch(
        repository: repository,
        book: book,
        paragraphIndex: 0,
      );

      expect(cache.value(book, 0), ['מפרש אישי']);
    });

    test('שאילת הטווח שומרת את קישורי הפסקה שאינם מפרשים', () async {
      final userBooksRepository =
          await UserBooksDatabaseHolder.instance.repository;
      await UserContentRepository(userBooksRepository.database).upsertUserLink(
        const UserLinkRecord(
          sourceTitle: 'ספר בסיס',
          sourceIsUserBook: false,
          sourceLineIndex: 0,
          targetTitle: 'ספר מקושר',
          targetIsUserBook: true,
          targetLineIndex: 0,
          connectionType: 'REFERENCE',
        ),
      );
      final cache = ParagraphCommentatorsCache();
      addTearDown(cache.dispose);
      final book = TextBook(title: 'ספר בסיס');

      await cache.prefetch(
        repository: TextBookRepository(fileSystem: FileSystemData()),
        book: book,
        paragraphIndex: 0,
      );

      expect(cache.value(book, 0), isEmpty);
      expect(
        cache.referenceLinks(book, 0)?.map((link) => link.connectionType),
        ['REFERENCE'],
      );
    });
  });

  group('מדיניות הצגת פריטי הפתיחה', () {
    test('פתיחת החלונית דורשת מפרשים נבחרים ולשונית מפרשים לא פעילה', () {
      expect(
        shouldShowOpenCommentatorsPaneEntry(
          hasSelectedCommentators: true,
          showCommentaryAsExpansionTiles: false,
          isCommentatorsTabActive: false,
        ),
        isTrue,
      );
      expect(
        shouldShowOpenCommentatorsPaneEntry(
          hasSelectedCommentators: false,
          showCommentaryAsExpansionTiles: false,
          isCommentatorsTabActive: false,
        ),
        isFalse,
      );
      expect(
        shouldShowOpenCommentatorsPaneEntry(
          hasSelectedCommentators: true,
          showCommentaryAsExpansionTiles: false,
          isCommentatorsTabActive: true,
        ),
        isFalse,
      );
    });

    test('"בחר מפרשים מרובים" מוצג גם בלי מפרשים נבחרים', () {
      expect(
        shouldShowSelectCommentatorsEntry(
          hasOpenCommentatorsPaneWithFilterCallback: true,
          isCommentatorsTabActive: false,
        ),
        isTrue,
      );
      expect(
        shouldShowSelectCommentatorsEntry(
          hasOpenCommentatorsPaneWithFilterCallback: true,
          isCommentatorsTabActive: true,
        ),
        isFalse,
      );
      expect(
        shouldShowSelectCommentatorsEntry(
          hasOpenCommentatorsPaneWithFilterCallback: false,
          isCommentatorsTabActive: false,
        ),
        isFalse,
      );
    });
  });
}
