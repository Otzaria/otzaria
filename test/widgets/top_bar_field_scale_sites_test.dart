// סעיף 30 (הערת הבעלים): שדות חיפוש בסרגל העליון (ושדה מיקום הדף ב-PDF) גדלים
// עם הטקסט של המערכת עד פי 1.6 — תקרה גבוהה מזו של הכותרת (1.3).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_page_number_display.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tools/gematria/gematria_search_screen.dart';
import 'package:otzaria/tools/tool_query.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:pdfrx/pdfrx.dart';

import '../helpers/memory_settings_cache.dart';
import '../test_helpers/stub_settings_bloc.dart';

class _Controller extends PdfViewerController {
  @override
  bool get isReady => true;

  @override
  int? get pageNumber => 3;

  @override
  int get pageCount => 125;
}

Widget _scaled(double scale, Widget home) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(scale)),
    child: Directionality(textDirection: TextDirection.rtl, child: child!),
  ),
  home: home,
);

/// גודל הגופן האפקטיבי (לגופן 10) ש-[finder] מקבל.
double _effective(WidgetTester tester, Finder finder) =>
    MediaQuery.textScalerOf(tester.element(finder.first)).scale(10);

void main() {
  late Directory directory;
  late ToolQueryInbox inbox;
  late StubSettingsBloc bloc;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    directory = Directory.systemTemp.createTempSync('topbar-field-scale-test');
    Directory('${directory.path}/ספרייה/תנך/תורה').createSync(recursive: true);
    await Settings.setValue(SettingsRepository.keyLibraryPath, directory.path);
    await Settings.setValue(SettingsRepository.keyLibraryFolderName, '');
    await Settings.setValue(SettingsRepository.keyDbEffectivePath, '');
    inbox = ToolQueryInbox();
    bloc = StubSettingsBloc();
  });

  tearDown(() async {
    await bloc.close();
    inbox.dispose();
    directory.deleteSync(recursive: true);
  });

  group('שדה החיפוש בסרגל של מסך הגימטריה', () {
    Future<void> pump(WidgetTester tester, double scale) async {
      await tester.pumpWidget(
        _scaled(
          scale,
          BlocProvider<SettingsBloc>.value(
            value: bloc,
            child: Scaffold(body: GematriaSearchScreen(queryInbox: inbox)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final field = find.descendant(
      of: find.byType(OtzariaSearchField),
      matching: find.byType(EditableText),
    );

    testWidgets('2.0 נעצר ב-1.6', (tester) async {
      await pump(tester, 2.0);
      expect(_effective(tester, field), closeTo(16, 0.01));
    });

    testWidgets('1.4 גדל כרגיל (מעבר לתקרת הכותרת, 1.3)', (tester) async {
      await pump(tester, 1.4);
      expect(_effective(tester, field), closeTo(14, 0.01));
    });
  });

  group('שדה מיקום הדף ב-PDF', () {
    Future<void> pump(WidgetTester tester, double scale) async {
      await tester.pumpWidget(
        _scaled(
          scale,
          Scaffold(
            body: AppTopBar(
              center: PageNumberDisplay(controller: _Controller()),
            ),
          ),
        ),
      );
      await tester.tap(find.text('3/125'));
      await tester.pump(const Duration(milliseconds: 60));
    }

    testWidgets('2.0 נעצר ב-1.6', (tester) async {
      await pump(tester, 2.0);
      expect(_effective(tester, find.byType(EditableText)), closeTo(16, 0.01));
    });

    testWidgets('1.4 גדל כרגיל (מעבר לתקרת הכותרת, 1.3)', (tester) async {
      await pump(tester, 1.4);
      expect(_effective(tester, find.byType(EditableText)), closeTo(14, 0.01));
    });
  });
}
