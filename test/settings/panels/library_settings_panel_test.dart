import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart'
    hide SwitchSettingsTile;
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../../helpers/memory_settings_cache.dart';

import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_controller.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_profile.dart';
import 'package:otzaria/external_catalog/responsa/responsa_catalog_repository.dart';
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
    bool showResponsa = false,
    bool showLocalHebrewBooks = true,
  }) : super(
         SettingsState.initial().copyWith(
           enabledExternalProviders: {
             if (showOtzarHachochma) ExternalProviderRegistry.otzar.id,
             if (showHebrewBooks) ExternalProviderRegistry.hebrewBooks.id,
             if (showResponsa) ExternalProviderRegistry.responsa.id,
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

Widget _wrap(
  SettingsBloc settingsBloc, {
  bool catalogExists = true,
  ResponsaCatalogInfo? responsaInfo,
  ResponsaStatus? responsaStatus,
  Future<void> Function()? responsaCatalogBuilder,
}) {
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: BlocProvider<SettingsBloc>.value(
          value: settingsBloc,
          child: SingleChildScrollView(
            child: LibrarySettingsPanel(
              catalogExistsChecker: () async => catalogExists,
              // בלי ההזרקה הזו הפאנל היה קורא את הקטלוג האמיתי של
              // פרויקט השו"ת מהמחשב שמריץ את הבדיקה.
              responsaInfoLoader: () async =>
                  responsaInfo ?? ResponsaCatalogInfo.missing,
              responsaStatusLoader: () async =>
                  responsaStatus ?? ResponsaStatus.notInstalled,
              responsaCatalogBuilder: responsaCatalogBuilder,
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

  group('כרטיס בר אילן', () {
    const installed = ResponsaStatus(
      installed: true,
      running: false,
      version: 25,
      confidence: ResponsaVersionConfidence.verified,
    );
    const withCatalog = ResponsaCatalogInfo(
      exists: true,
      bookCount: 8523,
      sourceVersion: 25,
      schemaVersion: 2,
    );

    testWidgets('אינו מוצג כשבר אילן אינו מותקן', (tester) async {
      await tester.pumpWidget(_wrap(_FakeSettingsBloc()));
      await tester.pumpAndSettle();

      expect(find.text('הצג ופתח ספרי בר אילן'), findsNothing);
    });

    testWidgets('מתג אחד לחיפוש ולפתיחה, לא שניים', (tester) async {
      // המתג הנפרד ל"אפשר פתיחת ספרים בתוכנה" הוסר: ספר שנמצא בחיפוש
      // ואי אפשר לפתוח אותו הוא תוצאה חסרת ערך.
      await tester.pumpWidget(
        _wrap(
          _FakeSettingsBloc(showResponsa: true),
          responsaStatus: installed,
          responsaInfo: withCatalog,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('הצג ופתח ספרי בר אילן'), findsOneWidget);
      expect(find.text('אפשר פתיחת ספרים בתוכנה'), findsNothing);
    });

    testWidgets('שורת הרענון מוצגת רק כשהמתג דלוק', (tester) async {
      // כשהמתג כבוי אין מה לרענן, ושורה שנייה שאינה עושה דבר רק
      // מבלבלת. נבדק בשני הכיוונים כדי שלא ייעלם גם כשהוא כן נחוץ.
      await tester.pumpWidget(
        _wrap(
          _FakeSettingsBloc(),
          responsaStatus: installed,
          responsaInfo: withCatalog,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('הצג ופתח ספרי בר אילן'), findsOneWidget);
      expect(find.text('רענון קטלוג בר אילן'), findsNothing);
      expect(find.text('רענן'), findsNothing);

      await tester.pumpWidget(
        _wrap(
          _FakeSettingsBloc(showResponsa: true),
          responsaStatus: installed,
          responsaInfo: withCatalog,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('רענון קטלוג בר אילן'), findsOneWidget);
      expect(find.text('רענן'), findsOneWidget);
    });

    testWidgets('הדלקה ראשונה בלי קטלוג מתחילה בנייה', (tester) async {
      var builds = 0;
      final settingsBloc = _FakeSettingsBloc();

      await tester.pumpWidget(
        _wrap(
          settingsBloc,
          responsaStatus: installed,
          responsaCatalogBuilder: () async => builds++,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('הצג ופתח ספרי בר אילן'));
      await tester.pumpAndSettle();

      expect(
        settingsBloc.state.enabledExternalProviders,
        contains(ExternalProviderRegistry.responsa.id),
      );
      expect(builds, 1);
    });

    testWidgets('הדלקה כשהקטלוג קיים אינה בונה מחדש', (tester) async {
      var builds = 0;

      await tester.pumpWidget(
        _wrap(
          _FakeSettingsBloc(),
          responsaStatus: installed,
          responsaInfo: withCatalog,
          responsaCatalogBuilder: () async => builds++,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('הצג ופתח ספרי בר אילן'));
      await tester.pumpAndSettle();

      expect(builds, 0);
    });

    testWidgets('קטלוג בסכמה ישנה מבקש רענון', (tester) async {
      await tester.pumpWidget(
        _wrap(
          _FakeSettingsBloc(showResponsa: true),
          responsaStatus: installed,
          responsaInfo: const ResponsaCatalogInfo(
            exists: true,
            bookCount: 8523,
            sourceVersion: 25,
            schemaVersion: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'הקטלוג נבנה בגרסה ישנה של אוצריא. רענון יעדכן את שמות הספרים '
          'ואת אופן הפתיחה.',
        ),
        findsOneWidget,
      );
    });
  });
}
