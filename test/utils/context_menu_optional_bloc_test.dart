import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/utils/ui/context_menu_utils.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

class _StubTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _StubTextBookBloc()
    : super(
        TextBookInitial.named(
          TextBook(title: 'ספר בדיקה'),
          0,
          false,
          const [],
        ),
      ) {
    on<TextBookEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// תפריט ההקשר של מפרש נבנה בשני משטחים: כרטיסיית טקסט (יש `TextBookBloc`)
/// וחלונית ה-PDF (אין). הטסטים כאן נועלים את שני המסלולים — הרגרסיה שהם
/// מונעים היא `read<TextBookBloc>()` שזרק בחלונית ה-PDF וסגר את התפריט בשקט,
/// כך ש"דווח על טעות בספר" ו"העתק את כל הפסקה" לא עשו דבר.
Link _link({bool targetIsUserBook = false}) {
  return Link(
    heRef: 'רש"י פסוק א',
    index1: 12,
    path2: 'רש"י על שבת',
    index2: 5,
    connectionType: 'COMMENTARY',
    targetIsUserBook: targetIsUserBook,
  );
}

/// עוטף כפתור שבונה את תפריט ההקשר של המפרש בלחיצה, ומאפשר לטסט לבדוק
/// שהבנייה הצליחה (ללא ProviderNotFoundException) ומה הפריטים שהוחזרו.
class _MenuProbe extends StatelessWidget {
  const _MenuProbe({required this.link, required this.onEntries});

  final Link link;
  final ValueChanged<List<AppContextMenuEntry>> onEntries;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => onEntries(
        ContextMenuUtils.buildCommentaryContextMenu(
          context: context,
          link: link,
          openBookCallback: (_) {},
          fontSize: 16,
          savedSelectedText: 'טקסט מסומן',
          onCopySelected: () {},
        ),
      ),
      child: const Text('פתח'),
    );
  }
}

void main() {
  Future<List<AppContextMenuEntry>> buildMenu(
    WidgetTester tester, {
    required bool withTextBookBloc,
    bool targetIsUserBook = false,
  }) async {
    List<AppContextMenuEntry>? captured;
    final probe = _MenuProbe(
      link: _link(targetIsUserBook: targetIsUserBook),
      onEntries: (entries) => captured = entries,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: withTextBookBloc
              ? BlocProvider<TextBookBloc>(
                  create: (_) => _StubTextBookBloc(),
                  child: probe,
                )
              : probe,
        ),
      ),
    );

    await tester.tap(find.text('פתח'));
    await tester.pump();
    return captured!;
  }

  group('תפריט הקשר של מפרש — ללא TextBookBloc (חלונית PDF)', () {
    testWidgets('נבנה בהצלחה גם כשאין TextBookBloc בעץ', (tester) async {
      final entries = await buildMenu(tester, withTextBookBloc: false);
      expect(entries, isNotEmpty);
    });

    testWidgets('"דווח על טעות בספר" קיים בתפריט', (tester) async {
      final entries = await buildMenu(tester, withTextBookBloc: false);
      expect(
        entries.map((e) => e.label),
        contains('דווח על טעות בספר'),
      );
    });

    testWidgets('"העתק את כל הפסקה" קיים בתפריט', (tester) async {
      final entries = await buildMenu(tester, withTextBookBloc: false);
      expect(
        entries.map((e) => e.label),
        contains('העתק את כל הפסקה'),
      );
    });

    testWidgets('ספר אישי אינו מקבל פריט דיווח', (tester) async {
      final entries = await buildMenu(
        tester,
        withTextBookBloc: false,
        targetIsUserBook: true,
      );
      expect(
        entries.map((e) => e.label),
        isNot(contains('דווח על טעות בספר')),
      );
    });
  });

  group('תפריט הקשר של מפרש — עם TextBookBloc (כרטיסיית טקסט)', () {
    testWidgets('אותם פריטים כמו במסלול ה-PDF', (tester) async {
      final withBloc = await buildMenu(tester, withTextBookBloc: true);
      final withoutBloc = await buildMenu(tester, withTextBookBloc: false);
      expect(
        withBloc.map((e) => e.label).toList(),
        equals(withoutBloc.map((e) => e.label).toList()),
      );
    });
  });

  group('_maybeTextBookState — סמנטיקת התלות האופציונלית', () {
    testWidgets('read<TextBookBloc?> מחזיר null כשאין provider', (
      tester,
    ) async {
      TextBookBloc? resolved;
      var didThrow = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              try {
                resolved = context.read<TextBookBloc?>();
              } catch (_) {
                didThrow = true;
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(didThrow, isFalse, reason: 'תלות אופציונלית אינה אמורה לזרוק');
      expect(resolved, isNull);
    });

    testWidgets('read<TextBookBloc?> מוצא את ה-BLoC כשהוא קיים', (
      tester,
    ) async {
      TextBookBloc? resolved;
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<TextBookBloc>(
            create: (_) => _StubTextBookBloc(),
            child: Builder(
              builder: (context) {
                resolved = context.read<TextBookBloc?>();
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(
        resolved,
        isNotNull,
        reason:
            'provider מחפש את אותו _InheritedProviderScope עבור T ועבור T? — '
            'אם זה נשבר, המסלול של כרטיסיית הטקסט מאבד את ה-state בשקט',
      );
    });
  });

  group('commentaryReportArgs — הדיווח מופנה לספר המפרש', () {
    test('ללא בחירת טקסט מדווחים על כל פסקת המפרש', () {
      final args = ContextMenuUtils.commentaryReportArgs(
        link: _link(),
        rawContent: '<b>תוכן</b> המפרש',
      );
      expect(args.book.title, 'רש"י על שבת');
      expect(args.bookTitle, 'רש"י על שבת');
      expect(args.content, isNotEmpty);
    });

    test('עם בחירת טקסט מדווחים על הבחירה', () {
      final args = ContextMenuUtils.commentaryReportArgs(
        link: _link(),
        rawContent: 'תוכן המפרש המלא',
        savedSelectedText: 'המפרש',
      );
      expect(args.selectedText, contains('המפרש'));
    });

    test('הדיווח מכוון ל-index2 של המפרש ולא ל-index1 של הספר הפתוח', () {
      final args = ContextMenuUtils.commentaryReportArgs(
        link: _link(),
        rawContent: 'תוכן',
      );
      expect(args.lineIndex, 5 - 1);
    });

    test('זהות ספר היעד נשמרת (ספר אישי)', () {
      final args = ContextMenuUtils.commentaryReportArgs(
        link: _link(targetIsUserBook: true),
        rawContent: 'תוכן',
      );
      expect(args.book, isA<TextBook>());
      expect(args.book.isUserBook, isTrue);
    });
  });
}
