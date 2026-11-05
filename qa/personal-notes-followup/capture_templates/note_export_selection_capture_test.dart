import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_export_dialog.dart' as current;
import 'package:otzaria/settings/engine/app_settings_store.dart';
import '__BASELINE_URI__' as before;
import '__REPO_URI__/test/test_helpers/memory_cache_provider.dart';
import 'qa_capture_helpers.dart' as qa;

List<PersonalNote> notes() => [
  for (final name in ['א', 'ב'])
    PersonalNote(
      id: 'note-$name',
      bookId: 'ספר $name|user',
      lineNumber: 1,
      lastKnownLineNumber: null,
      displayTitle: 'פרק א',
      status: PersonalNoteStatus.located,
      content: 'הערה אישית לדוגמה על המקור המסומן.',
      contentPlain: 'הערה אישית לדוגמה על המקור המסומן.',
      contentFormat: PersonalNoteContentFormat.plain,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(qa.loadCaptureFonts);
  setUp(() async => Settings.init(cacheProvider: MemoryCacheProvider()));
  for (final old in [true, false]) {
    testWidgets('QA capture export selection ${old ? 'before' : 'after'}', (tester) async {
      tester.view.physicalSize = const Size(1100, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: qa.captureTheme(),
          locale: const Locale('he', 'IL'),
          supportedLocales: const [Locale('he', 'IL')],
          localizationsDelegates: qa.localizations,
          builder: qa.captureBuilder,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  child: const Text('ייצוא הערות'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => old
                      ? before.PersonalNotesExportDialog(allNotes: notes())
                      : current.PersonalNotesExportDialog(allNotes: notes()),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ייצוא הערות'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('בחירה ידנית'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile).last);
      await tester.pumpAndSettle();
      await qa.capture(tester, old ? '05-export-selection-before' : '06-export-selection-after', region: find.descendant(of: find.byType(Dialog), matching: find.byType(Material)).first);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
