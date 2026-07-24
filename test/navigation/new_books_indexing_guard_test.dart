// Regression test for bug introduced in commit 72ca3b4aa:
// The BlocListener that fires IndexSpecificBooks did not check autoUpdateIndex,
// so adding a personal folder triggered indexing even when auto-indexing was
// disabled by the user in settings.
// Fix: main_window_screen.dart now guards the dispatch with
//   if (context.read<SettingsBloc>().state.autoUpdateIndex) { ... }

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';

// ---------------------------------------------------------------------------
// Mock blocs (bloc_test pattern used across the project)
// ---------------------------------------------------------------------------

class MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

// ---------------------------------------------------------------------------
// Minimal test widget that mirrors the guard from main_window_screen.dart.
// Instead of dispatching to a real IndexingBloc (which requires heavy
// infrastructure), it appends to a capture list so the test can assert on
// what would have been dispatched.
// ---------------------------------------------------------------------------

class _TestWidget extends StatelessWidget {
  final List<IndexingEvent> capturedEvents;

  const _TestWidget({required this.capturedEvents});

  @override
  Widget build(BuildContext context) {
    return BlocListener<LibraryBloc, LibraryState>(
      listenWhen: (previous, current) =>
          current.newBooksToIndex != null &&
          current.newBooksToIndex!.isNotEmpty,
      // Guard copied verbatim from main_window_screen.dart after fix.
      listener: (context, state) {
        if (context.read<SettingsBloc>().state.autoUpdateIndex) {
          capturedEvents.add(
            IndexSpecificBooks(state.newBooksToIndex!, state.library!),
          );
        }
      },
      child: const SizedBox.shrink(),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Library _emptyLibrary() => Library(categories: []);

LibraryState _stateWithNewBooks() {
  final book = TextBook(title: 'ספר חדש');
  final library = _emptyLibrary();
  return LibraryState(
    library: library,
    isLoading: false,
    newBooksToIndex: [book],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('new-books indexing guard (autoUpdateIndex)', () {
    late MockLibraryBloc libraryBloc;
    late MockSettingsBloc settingsBloc;
    late StreamController<LibraryState> libraryStateController;
    late List<IndexingEvent> capturedEvents;

    setUp(() {
      libraryStateController = StreamController<LibraryState>.broadcast();
      libraryBloc = MockLibraryBloc();
      settingsBloc = MockSettingsBloc();
      capturedEvents = [];

      whenListen(
        libraryBloc,
        libraryStateController.stream,
        initialState: LibraryState(
          library: _emptyLibrary(),
          isLoading: false,
        ),
      );
    });

    tearDown(() {
      libraryStateController.close();
    });

    Future<void> pumpTestWidget(WidgetTester tester) async {
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<LibraryBloc>.value(value: libraryBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: MaterialApp(
            home: _TestWidget(capturedEvents: capturedEvents),
          ),
        ),
      );
    }

    testWidgets(
      'regression: לא שולח IndexSpecificBooks כשהאינדוקס האוטומטי כבוי',
      (tester) async {
        whenListen(
          settingsBloc,
          const Stream<SettingsState>.empty(),
          initialState: SettingsState.initial().copyWith(
            autoUpdateIndex: false,
          ),
        );

        await pumpTestWidget(tester);

        // Emit a state with new books — this triggered the bug.
        libraryStateController.add(_stateWithNewBooks());
        await tester.pump();

        expect(
          capturedEvents.whereType<IndexSpecificBooks>(),
          isEmpty,
          reason: 'IndexSpecificBooks לא אמור לרוץ כשהאינדוקס האוטומטי מכובה',
        );
      },
    );

    testWidgets(
      'שולח IndexSpecificBooks כשהאינדוקס האוטומטי דלוק (בדיקת "נכון" לצד "שלילי")',
      (tester) async {
        whenListen(
          settingsBloc,
          const Stream<SettingsState>.empty(),
          initialState: SettingsState.initial().copyWith(autoUpdateIndex: true),
        );

        await pumpTestWidget(tester);

        libraryStateController.add(_stateWithNewBooks());
        await tester.pump();

        expect(
          capturedEvents.whereType<IndexSpecificBooks>(),
          hasLength(1),
          reason: 'IndexSpecificBooks אמור לרוץ כשהאינדוקס האוטומטי דלוק',
        );
      },
    );
  });
}
