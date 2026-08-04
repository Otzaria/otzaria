import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/text_book/utils/commentators_context_menu.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

void main() {
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
    void Function(List<String> commentators, {required bool isAdding})?
    onChange,
    void Function()? onOpenPane,
    void Function()? onSelectMultiple,
  }) => buildCommentatorsContextMenuChildren(
    activeCommentators: active,
    availableCommentators: available,
    commentatorGroups: groups,
    onCommentatorsChanged: onChange ?? (_, {required isAdding}) {},
    onOpenPane: onOpenPane,
    onSelectMultiple: onSelectMultiple,
  );

  group('buildCommentatorsContextMenuChildren', () {
    test('מציג את כל הקבוצות והמפרשים בסדר הדורות', () {
      expect(labelsOf(build()), [
        'הצג את כל המפרשים',
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
      expect(entryNamed(entries, 'הצג את כל המפרשים').isSelected, isFalse);
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

      final showAll = entryNamed(entries, 'הצג את כל המפרשים');
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
        availableCommentators: const [],
        commentatorGroups: const [],
        onCommentatorsChanged: (_, {required isAdding}) {},
      );
      expect(labelsOf(entries), ['הצג את כל המפרשים']);
      expect(entries.where((e) => e.isDivider), isEmpty);
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
