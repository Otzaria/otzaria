// דהיית חיצי הדפדוף בריחוף ניתקה את הסמנטיקה ('!child.attached') והקריסה את התוכנה.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:material_ui/material_ui.dart' as mui;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart' as events;
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../helpers/memory_settings_cache.dart';

void main() {
  testWidgets(
    'ריחוף על קצות הכפולה אחרי הגדלה אינו שובר את עץ הנגישות (issue #2021)',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await Settings.init(cacheProvider: MemorySettingsCache());
      final directory = Directory.systemTemp.createTempSync('otzaria-2021-');
      addTearDown(() => directory.deleteSync(recursive: true));
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final originalModulePath = Pdfrx.pdfiumModulePath;
      Pdfrx.pdfiumModulePath = File(
        'build/native_assets/${Platform.operatingSystem}/'
        '${Platform.isWindows
            ? 'pdfium.dll'
            : Platform.isMacOS
            ? 'libpdfium.dylib'
            : 'libpdfium.so'}',
      ).absolute.path;
      addTearDown(() => Pdfrx.pdfiumModulePath = originalModulePath);

      final path = '${directory.path}/book.pdf';
      await tester.runAsync(() async {
        await pdfrxFlutterInitialize();
        final pdf = pw.Document();
        for (var i = 0; i < 6; i++) {
          pdf.addPage(pw.Page(build: (_) => pw.Center(child: pw.Text('$i'))));
        }
        File(path).writeAsBytesSync(await pdf.save());
      });
      final tab = PdfBookTab(
        book: PdfBook(title: 'ספר', path: path),
        pageNumber: 3,
      );
      final tabsBloc = TabsBloc(repository: _TabsRepository());
      // ignore: invalid_use_of_visible_for_testing_member
      tabsBloc.emit(TabsState(tabs: [tab], currentTabIndex: 0));
      final settings = _SettingsBloc();
      final tour = TourCubit();
      addTearDown(tab.dispose);
      addTearDown(tabsBloc.close);
      addTearDown(settings.close);
      addTearDown(tour.close);
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            mui.DefaultMaterialLocalizations.delegate,
          ],
          home: MultiBlocProvider(
            providers: [
              BlocProvider<SettingsBloc>.value(value: settings),
              BlocProvider<TabsBloc>.value(value: tabsBloc),
              BlocProvider<TourCubit>.value(value: tour),
            ],
            child: Scaffold(body: PdfBookScreen(tab: tab)),
          ),
        ),
      );
      final viewer = find.byType(PdfViewer);
      final bloc = tester.element(viewer).read<PdfBookBloc>();
      Future<void> settle(int frames) async {
        for (var i = 0; i < frames; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      for (var i = 0; i < 200 && bloc.state is! PdfBookLoaded; i++) {
        await settle(1);
      }
      bloc.add(const events.SetLayoutMode(PdfLayoutMode.bookView));
      await settle(30);
      bloc.add(const events.ZoomIn());
      await settle(15);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(700, 450));
      addTearDown(mouse.removePointer);
      for (final x in [5.0, 30.0, 700.0, 1370.0, 1395.0, 700.0]) {
        await mouse.moveTo(Offset(x, 450));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 700));
      }

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 200));
      semantics.dispose();
    },
  );
}

class _TabsRepository implements TabsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #loadTabs) return [];
    if (invocation.memberName == #loadCurrentTabIndex) return 0;
    return Future<void>.value();
  }
}

class _SettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _SettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
