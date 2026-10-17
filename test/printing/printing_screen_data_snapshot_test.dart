import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:pdf/pdf.dart';

import '../helpers/memory_settings_cache.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _FakeSettingsRepository extends Fake implements SettingsRepository {
  @override
  bool hasProtectedModePassword() => false;
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  testWidgets(
    'PDF uses the line count of its captured data when the future is replaced',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final settingsBloc = _MockSettingsBloc();
      whenListen(
        settingsBloc,
        const Stream<SettingsState>.empty(),
        initialState: SettingsState.initial(),
      );
      final oldData = Completer<String>();
      // Suppress automatic preview rendering; exercise the real PDF export.
      final preview = Completer<Uint8List>();
      Widget app(Future<String> data) =>
          RepositoryProvider<SettingsRepository>.value(
            value: _FakeSettingsRepository(),
            child: BlocProvider<SettingsBloc>.value(
              value: settingsBloc,
              child: MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(0.5)),
                  child: child!,
                ),
                home: PrintingScreen(
                  data: data,
                  bookId: 'snapshot-test',
                  createPdfOverride: (_) => preview.future,
                  displayProfile: const TextDisplayProfile(),
                ),
              ),
            ),
          );

      await tester.pumpWidget(app(oldData.future));
      final dynamic state = tester.state(find.byType(PrintingScreen));
      state.endLine = 3;
      Uint8List? pdf;
      Object? error;
      final export = (state.createPdf(PdfPageFormat.a4) as Future<Uint8List>)
          .then<void>((bytes) => pdf = bytes, onError: (Object e) => error = e);

      await tester.pumpWidget(app(Future.value('book\nnew1\nnew2\nnew3')));
      await tester.pump();
      state.endLine = 3;
      oldData.complete('book\nold1');
      for (var i = 0; i < 300 && pdf == null && error == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(error, isNull);
      expect(pdf, isNotNull);
      expect(pdf!.take(5), '%PDF-'.codeUnits);
      await export;
      await tester.pumpWidget(const SizedBox());
    },
  );
}
