import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/theme/app_density.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tools/measurement_converter/measurement_converter_screen.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late SettingsBloc settingsBloc;

  setUp(() {
    settingsBloc = SettingsBloc(repository: SettingsRepository())
      ..add(LoadSettings());
  });

  tearDown(() async {
    await settingsBloc.close();
  });

  testWidgets('גודל תיבת ההקלדה במדות ושיעורים נשמר בגובה 40px עם ובלי ערך', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: settingsBloc,
          child: const Scaffold(
            body: MeasurementConverterScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rtlFinder = find.byType(RtlTextField);
    expect(rtlFinder, findsOneWidget);
    final inputDecFinder = find.descendant(
      of: rtlFinder,
      matching: find.byType(InputDecorator),
    );

    Size getContainerSize() {
      final RenderBox decRb = tester.renderObject(inputDecFinder);
      Size? containerSize;
      decRb.visitChildren((child) {
        if (child is RenderBox) {
          child.visitChildren((grandchild) {
            if (grandchild is RenderBox &&
                grandchild.runtimeType.toString().contains(
                  'RenderCustomPaint',
                )) {
              containerSize = grandchild.size;
            }
          });
        }
      });
      return containerSize ?? decRb.size;
    }

    Size editableSize() => tester.getSize(
      find.descendant(of: rtlFinder, matching: find.byType(EditableText)),
    );

    final sizeWith = getContainerSize();
    final editableWith = editableSize();
    expect(sizeWith.height, 40.0);

    // נלחץ על כפתור המחיקה (dismiss icon)
    final clearBtn = find.byIcon(FluentIcons.dismiss_24_regular);
    expect(clearBtn, findsOneWidget);
    await tester.tap(clearBtn);
    await tester.pumpAndSettle();

    final sizeWithout = getContainerSize();
    // הגובה חייב להישאר זהה לחלוטין (40.0) ולא להתכווץ ל-16.0!
    expect(sizeWithout.height, 40.0);
    expect(sizeWithout, equals(sizeWith));
    // בפונט אמיתי גובה השורה אינו בדיוק fontSize, ורק משבצת הסיומת מחזיקה את הגובה
    expect(editableSize().width, editableWith.width);
  });

  testWidgets('גודל תיבת ההקלדה נשמר גם במצב compactMenuMode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final compactBloc = _TestSettingsBloc(
      SettingsState.initial().copyWith(compactMenuMode: true),
    );
    addTearDown(compactBloc.close);

    await tester.pumpWidget(
      MaterialApp(
        // הצפיפות מגיעה מערכת הנושא, כמו ב-App.
        theme: ThemeData(extensions: const [AppDensity.compact]),
        home: BlocProvider<SettingsBloc>.value(
          value: compactBloc,
          child: const Scaffold(
            body: MeasurementConverterScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rtlFinder = find.byType(RtlTextField);
    expect(rtlFinder, findsOneWidget);
    final inputDecFinder = find.descendant(
      of: rtlFinder,
      matching: find.byType(InputDecorator),
    );

    Size getContainerSize() {
      final RenderBox decRb = tester.renderObject(inputDecFinder);
      Size? containerSize;
      decRb.visitChildren((child) {
        if (child is RenderBox) {
          child.visitChildren((grandchild) {
            if (grandchild is RenderBox &&
                grandchild.runtimeType.toString().contains(
                  'RenderCustomPaint',
                )) {
              containerSize = grandchild.size;
            }
          });
        }
      });
      return containerSize ?? decRb.size;
    }

    final sizeWith = getContainerSize();
    expect(sizeWith.height, 36.0);

    // נלחץ על כפתור המחיקה (dismiss icon)
    final clearBtn = find.byIcon(FluentIcons.dismiss_24_regular);
    expect(clearBtn, findsOneWidget);
    await tester.tap(clearBtn);
    await tester.pumpAndSettle();

    final sizeWithout = getContainerSize();
    expect(sizeWithout.height, 36.0);
    expect(sizeWithout, equals(sizeWith));
  });
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc([SettingsState? initialState])
    : super(initialState ?? SettingsState.initial()) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
