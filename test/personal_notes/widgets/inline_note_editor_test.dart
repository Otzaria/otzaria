import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/personal_notes/widgets/inline_note_editor.dart';
import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('InlineNoteEditor תופס פוקוס מיד בעלייה', (tester) async {
    // רגרסיה: בצורת הדף, פתיחת הערה חדשה לא תפסה פוקוס במצב הראשוני
    // (autoFocus של QuillEditor איבד את ה-race עם אנימציית הפאנל).
    // הפתרון: requestFocus מפורש ב-post-frame.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineNoteEditor(
            bookId: 'ספר מבחן',
            draftLineNumber: 1,
            linkableNotes: const [],
            onSave: (_) {},
            onCancel: () {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final state = tester.state<State<InlineNoteEditor>>(
      find.byType(InlineNoteEditor),
    );
    // ה-FocusNode הוא private, אבל אפשר לבדוק דרך FocusManager
    // שהפוקוס הוא על משהו בתת-העץ של העורך.
    final primary = FocusManager.instance.primaryFocus;
    expect(
      primary,
      isNotNull,
      reason: 'אמור להיות פוקוס פעיל אחרי שהעורך נטען',
    );
    // ה-FocusNode של InlineNoteEditor מוגדר עם debugLabel כדי שנוכל
    // לוודא שזה אכן הוא שתפס את הפוקוס.
    expect(
      primary?.debugLabel,
      equals('InlineNoteEditor'),
      reason: 'הפוקוס חייב להיות על העורך, לא על widget אחר',
    );
    expect(state.mounted, isTrue);
  });

  testWidgets('InlineNoteEditor תופס פוקוס גם בריטריי המאוחר (350ms)', (
    tester,
  ) async {
    // רגרסיה: ה-post-frame הראשון יורה לפני שהפאנל סיים להיפתח, ולפעמים
    // ה-FocusNode עוד לא נמצא בעץ הפוקוס. הריטריי אחרי 350ms תופס מקרה זה.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineNoteEditor(
            bookId: 'ספר מבחן',
            draftLineNumber: 2,
            linkableNotes: const [],
            onSave: (_) {},
            onCancel: () {},
          ),
        ),
      ),
    );

    // לפני שהריטריי ירה
    await tester.pump(const Duration(milliseconds: 100));
    // אחרי שהריטריי ירה
    await tester.pump(const Duration(milliseconds: 400));

    final primary = FocusManager.instance.primaryFocus;
    expect(primary?.debugLabel, equals('InlineNoteEditor'));
  });
  // issue #1303 — ה-X של הערה חדשה בחלונית הצד מחק את מה שהוקלד בלי אזהרה,
  // בשונה מעורך ההערות בדיאלוג ששואל לפני סגירה.
  group('ביטול עם שינויים שלא נשמרו (issue #1303)', () {
    testWidgets('ביטול אחרי הקלדה פותח אישור ואינו סוגר מיד', (tester) async {
      final cancelRequest = ValueNotifier<int>(0);
      addTearDown(cancelRequest.dispose);
      var cancelled = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InlineNoteEditor(
              bookId: 'ספר מבחן',
              draftLineNumber: 3,
              linkableNotes: const [],
              cancelRequest: cancelRequest,
              onSave: (_) {},
              onCancel: () => cancelled++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final editor = tester.widget<quill.QuillEditor>(
        find.byType(quill.QuillEditor),
      );
      editor.controller.document.insert(0, 'הערה שטרם נשמרה');
      await tester.pump();

      cancelRequest.value++;
      await tester.pumpAndSettle();

      expect(cancelled, 0);
      expect(find.text('שמור טיוטה'), findsOneWidget);
    });

    testWidgets('ביטול בלי שינויים סוגר מיד', (tester) async {
      final cancelRequest = ValueNotifier<int>(0);
      addTearDown(cancelRequest.dispose);
      var cancelled = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InlineNoteEditor(
              bookId: 'ספר מבחן',
              draftLineNumber: 4,
              linkableNotes: const [],
              cancelRequest: cancelRequest,
              onSave: (_) {},
              onCancel: () => cancelled++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      cancelRequest.value++;
      await tester.pumpAndSettle();

      expect(cancelled, 1);
      expect(find.text('שמור טיוטה'), findsNothing);
    });
  });
}
