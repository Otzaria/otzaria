import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart'
    hide SwitchSettingsTile;
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../../helpers/memory_settings_cache.dart';

import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/panels/library_settings_panel.dart';

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  final List<SettingsEvent> dispatched = [];

  _FakeSettingsBloc({
    bool showOtzarHachochma = false,
    bool showHebrewBooks = false,
    bool showLocalHebrewBooks = true,
  }) : super(
         SettingsState.initial().copyWith(
           enabledExternalProviders: {
             if (showOtzarHachochma) ExternalProviderRegistry.otzar.id,
             if (showHebrewBooks) ExternalProviderRegistry.hebrewBooks.id,
           },
           showLocalHebrewBooks: showLocalHebrewBooks,
         ),
       ) {
    on<SettingsEvent>((event, emit) {
      dispatched.add(event);
      if (event is UpdateEnabledExternalProviders) {
        emit(state.copyWith(enabledExternalProviders: event.providers));
      } else if (event is UpdateShowLocalHebrewBooks) {
        emit(state.copyWith(showLocalHebrewBooks: event.showLocalHebrewBooks));
      }
    });
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Widget _wrap(SettingsBloc settingsBloc, {bool catalogExists = true}) {
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: BlocProvider<SettingsBloc>.value(
          value: settingsBloc,
          child: SingleChildScrollView(
            child: LibrarySettingsPanel(
              catalogExistsChecker: () async => catalogExists,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  Future<void> setHebrewBooksPath(String path) =>
      Settings.setValue<String>(SettingsRepository.keyHebrewBooksPath, path);

  const localTileTitle = 'הצג ספרי היברובוקס שברשותך';

  testWidgets('מציג "אל תציג" כשהצגת ספרים חיצוניים כבויה', (tester) async {
    await tester.pumpWidget(_wrap(_FakeSettingsBloc()));
    await tester.pumpAndSettle();

    expect(find.text('אל תציג'), findsOneWidget);
    expect(
      find.text('ספרים חיצוניים לא יוצגו בתוצאות החיפוש במסך הספרייה'),
      findsOneWidget,
    );
  });

  testWidgets('מציג "הצג הכל" כששני המקורות מופעלים', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeSettingsBloc(
          showOtzarHachochma: true,
          showHebrewBooks: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('הצג הכל'), findsOneWidget);
    expect(
      find.text(
        'יוצגו ספרים מאוצר החכמה ומהיברובוקס בתוצאות החיפוש במסך הספרייה',
      ),
      findsOneWidget,
    );
  });

  testWidgets('מציג "אוצר החכמה בלבד" כשרק אוצר החכמה מופעל', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeSettingsBloc(
          showOtzarHachochma: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('אוצר החכמה בלבד'), findsOneWidget);
  });

  testWidgets('מציג "היברובוקס בלבד" כשרק היברובוקס מופעל', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeSettingsBloc(
          showHebrewBooks: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('היברובוקס בלבד'), findsOneWidget);
  });

  testWidgets(
    'בחירת "אל תציג" מכבה את כל המקורות',
    (tester) async {
      final settingsBloc = _FakeSettingsBloc(
        showOtzarHachochma: true,
        showHebrewBooks: true,
      );

      await tester.pumpWidget(_wrap(settingsBloc));
      await tester.pumpAndSettle();

      await tester.tap(find.text('הצג הכל'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('אל תציג').last);
      await tester.pumpAndSettle();

      expect(settingsBloc.state.showExternalBooks, isFalse);
      expect(settingsBloc.state.showOtzarHachochma, isFalse);
      expect(settingsBloc.state.showHebrewBooks, isFalse);
    },
  );

  testWidgets('כשהקטלוג חסר — מוצג כפתור הורדה במקום התפריט', (tester) async {
    await tester.pumpWidget(_wrap(_FakeSettingsBloc(), catalogExists: false));
    await tester.pumpAndSettle();

    expect(find.text('הורד קטלוג'), findsOneWidget);
    expect(find.textContaining('חסר במערכת'), findsOneWidget);
    // תפריט המקורות אינו מוצג כשאין קטלוג.
    expect(find.text('אל תציג'), findsNothing);
  });

  testWidgets('מתג הספרים המקומיים מוצג רק כשהוגדרה תיקיית היברובוקס', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_FakeSettingsBloc()));
    await tester.pumpAndSettle();
    expect(find.text(localTileTitle), findsNothing);

    await setHebrewBooksPath(r'C:\HebrewBooks');
    await tester.pumpWidget(_wrap(_FakeSettingsBloc()));
    await tester.pumpAndSettle();
    expect(find.text(localTileTitle), findsOneWidget);
  });

  testWidgets('המתג מוסתר כשהיברובוקס כבר מוצג מהקטלוג', (tester) async {
    await setHebrewBooksPath(r'C:\HebrewBooks');

    await tester.pumpWidget(
      _wrap(
        _FakeSettingsBloc(showHebrewBooks: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(localTileTitle), findsNothing);
  });

  testWidgets('כיבוי המתג משדר UpdateShowLocalHebrewBooks', (tester) async {
    await setHebrewBooksPath(r'C:\HebrewBooks');
    final settingsBloc = _FakeSettingsBloc();

    await tester.pumpWidget(_wrap(settingsBloc));
    await tester.pumpAndSettle();

    // המתג הראשון בעמוד הוא "הצג תצוגה מקדימה"; זה של הספרים המקומיים אחרון.
    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();

    expect(settingsBloc.state.showLocalHebrewBooks, isFalse);
    expect(
      find.text('ספרים מתיקיית היברובוקס לא יוצגו בתוצאות איתור הספר'),
      findsOneWidget,
    );
  });
}
