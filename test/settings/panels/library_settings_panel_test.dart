import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../../helpers/memory_settings_cache.dart';

import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/panels/library_settings_panel.dart';

class _TrackingSettingsCache extends MemorySettingsCache {
  final writes = <String>[];

  @override
  Future<void> setObject<T>(String key, T? value) {
    writes.add(key);
    return super.setObject<T>(key, value);
  }
}

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  final List<SettingsEvent> dispatched = [];

  _FakeSettingsBloc({
    bool showExternalBooks = false,
    bool showOtzarHachochma = false,
    bool showHebrewBooks = false,
    bool showLocalHebrewBooks = true,
    String hebrewBooksPath = '',
  }) : super(
         SettingsState.initial().copyWith(
           showExternalBooks: showExternalBooks,
           showOtzarHachochma: showOtzarHachochma,
           showHebrewBooks: showHebrewBooks,
           showLocalHebrewBooks: showLocalHebrewBooks,
           hebrewBooksPath: hebrewBooksPath,
         ),
       ) {
    on<SettingsEvent>((event, emit) {
      dispatched.add(event);
      if (event is UpdateShowExternalBooks) {
        emit(state.copyWith(showExternalBooks: event.showExternalBooks));
      } else if (event is UpdateShowOtzarHachochma) {
        emit(state.copyWith(showOtzarHachochma: event.showOtzarHachochma));
      } else if (event is UpdateShowHebrewBooks) {
        emit(state.copyWith(showHebrewBooks: event.showHebrewBooks));
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
  Future<bool> Function()? catalogChecker,
}) {
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: BlocProvider<SettingsBloc>.value(
          value: settingsBloc,
          child: SingleChildScrollView(
            child: LibrarySettingsPanel(
              catalogExistsChecker: catalogChecker ?? () async => catalogExists,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _TrackingSettingsCache cache;

  setUp(() async {
    cache = _TrackingSettingsCache();
    await Settings.init(cacheProvider: cache);
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
          showExternalBooks: true,
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
          showExternalBooks: true,
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
          showExternalBooks: true,
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
        showExternalBooks: true,
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

  // הנתיב מגיע מ־SettingsState: כתיבה שלא עברה דרך הבלוק (הגדרת התיקייה
  // בלשונית הספרייה) מגיעה אליו בזרם השינויים, כמו ב־AppScopeProviders.
  testWidgets('מתג הספרים המקומיים מוצג רק כשהוגדרה תיקיית היברובוקס', (
    tester,
  ) async {
    final changes = StreamController<String>.broadcast();
    addTearDown(changes.close);
    final repository = SettingsRepository();
    final settingsBloc = SettingsBloc(
      repository: repository,
      initialSettings: repository.readSettings(),
      externalChanges: changes.stream,
      ensureFontLoaded: (_) async {},
    );
    addTearDown(settingsBloc.close);

    await tester.pumpWidget(_wrap(settingsBloc));
    await tester.pumpAndSettle();
    expect(find.text(localTileTitle), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);

    await setHebrewBooksPath(r'C:\HebrewBooks');
    changes.add(SettingsRepository.keyHebrewBooksPath);
    await tester.pumpAndSettle();
    expect(find.text(localTileTitle), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(2));
  });

  testWidgets('המתג מוסתר כשהיברובוקס כבר מוצג מהקטלוג', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeSettingsBloc(
          showExternalBooks: true,
          showHebrewBooks: true,
          hebrewBooksPath: r'C:\HebrewBooks',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(localTileTitle), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('כיבוי המתג משדר UpdateShowLocalHebrewBooks', (tester) async {
    final settingsBloc = _FakeSettingsBloc(hebrewBooksPath: r'C:\HebrewBooks');

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

  const unavailableCases = [
    (
      name: 'קטלוג חסר',
      catalog: false,
      path: r'C:\HebrewBooks',
      included: false,
      explanation:
          'כדי להציג ספרי היברובוקס מקומיים, יש להוריד את הקטלוג באמצעות "הורד קטלוג".',
    ),
    (
      name: 'תיקייה חסרה',
      catalog: true,
      path: '',
      included: false,
      explanation:
          'כדי להציג ספרי היברובוקס שברשותך, יש לבחור תיקייה ב"מיקום ספרי היברובוקס".',
    ),
    (
      name: 'כלול במקורות',
      catalog: true,
      path: r'C:\HebrewBooks',
      included: true,
      explanation:
          'ספרי היברובוקס שברשותך כבר כלולים במקור היברובוקס שנבחר ב"מקורות אחרים לספרים".',
    ),
  ];
  for (final item in unavailableCases) {
    testWidgets('חיפוש היברובוקס: ${item.name}', (tester) async {
      await setHebrewBooksPath(item.path);
      final settingsBloc = _FakeSettingsBloc(
        showExternalBooks: item.included,
        showHebrewBooks: item.included,
        hebrewBooksPath: item.path,
      );
      addTearDown(settingsBloc.close);
      cache.writes.clear();
      await tester.pumpWidget(_wrap(settingsBloc, catalogExists: item.catalog));
      await tester.pumpAndSettle();
      expect(
        find.text(localTileTitle),
        findsOneWidget,
        reason: 'תוצאת חיפוש היברובוקס צריכה להציג את תנאי הזמינות',
      );
      expect(find.text(item.explanation), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
      expect(settingsBloc.dispatched, isEmpty);
      expect(cache.writes, isEmpty);
      expect(
        Settings.getValue<String>(SettingsRepository.keyHebrewBooksPath),
        item.path,
      );
    });
  }

  testWidgets('שורת היברובוקס ממתינה לתוצאת בדיקת הקטלוג', (tester) async {
    final checked = Completer<bool>();
    final settingsBloc = _FakeSettingsBloc();
    addTearDown(settingsBloc.close);
    await tester.pumpWidget(
      _wrap(settingsBloc, catalogChecker: () => checked.future),
    );
    await tester.pump();
    expect(find.text(localTileTitle), findsNothing);
    expect(cache.writes, isEmpty);
    checked.complete(false);
    await tester.pumpAndSettle();
    expect(find.text(localTileTitle), findsOneWidget);
    expect(find.text('הורד קטלוג'), findsOneWidget);
    expect(cache.writes, isEmpty);
  });

  testWidgets('מעבר מקורות מחליף הסבר ומתג בלי לשנות את הבחירה המקומית', (
    tester,
  ) async {
    await setHebrewBooksPath(r'C:\HebrewBooks');
    final settingsBloc = _FakeSettingsBloc(
      showLocalHebrewBooks: false,
      hebrewBooksPath: r'C:\HebrewBooks',
    );
    addTearDown(settingsBloc.close);
    await tester.pumpWidget(_wrap(settingsBloc));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsNWidgets(2));
    cache.writes.clear();
    settingsBloc.add(const UpdateShowExternalBooks(true));
    settingsBloc.add(const UpdateShowHebrewBooks(true));
    await tester.pumpAndSettle();
    expect(find.text(localTileTitle), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.text(unavailableCases.last.explanation), findsOneWidget);
    settingsBloc.add(const UpdateShowHebrewBooks(false));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsNWidgets(2));
    expect(settingsBloc.state.showLocalHebrewBooks, isFalse);
    expect(cache.writes, isEmpty);
  });
}
