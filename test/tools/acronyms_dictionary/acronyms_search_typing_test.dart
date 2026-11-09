import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tools/acronyms_dictionary/acronyms_dictionary_screen.dart';
import 'package:otzaria/tools/acronyms_dictionary/widgets/acronym_result_card.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';

class _SettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _SettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// חיפוש מאפס על כל הקטלוג, עם המיון המלא שקובע את סדר התוצאות במסך.
List<String> _searchFromScratch(
  DictionaryLookupRepository repository,
  List<AcronymCatalogEntry> catalog,
  String raw,
) {
  final query = raw.trim();
  if (query.isEmpty) return [];
  final normalizedQuery = repository.normalizeAcronymQuery(query);
  int rank(AcronymCatalogEntry entry) {
    final key = entry.displayAcronym;
    if (key == query) return 0;
    if (key.startsWith(query)) return 1;
    if (key.contains(query)) return 2;
    return normalizedQuery.isNotEmpty &&
            entry.normalizedKey.contains(normalizedQuery)
        ? 3
        : 4;
  }

  final matches =
      catalog
          .where(
            (entry) =>
                entry.displayAcronym.contains(query) ||
                (normalizedQuery.isNotEmpty &&
                    entry.normalizedKey.contains(normalizedQuery)) ||
                entry.meanings.any((meaning) => meaning.contains(query)),
          )
          .toList()
        ..sort((a, b) {
          final byRank = rank(a).compareTo(rank(b));
          if (byRank != 0) return byRank;
          final byLength = a.displayAcronym.length.compareTo(
            b.displayAcronym.length,
          );
          return byLength != 0
              ? byLength
              : a.displayAcronym.compareTo(b.displayAcronym);
        });
  return [for (final entry in matches) entry.displayAcronym];
}

/// כל התוויות ברשימת התוצאות לפי הסדר, גם אלה שמחוץ למסך.
List<String> _shownAcronyms(WidgetTester tester) {
  final lists = tester.widgetList<ListView>(find.byType(ListView)).toList();
  if (lists.isEmpty) return [];
  final delegate = lists.single.childrenDelegate as SliverChildBuilderDelegate;
  final context = tester.element(find.byType(ListView));
  return [
    for (var i = 0; i < delegate.childCount!; i++)
      (delegate.builder(context, i)! as AcronymResultCard).acronym,
  ];
}

void main() {
  testWidgets('הקלדה ומחיקה אות אחר אות: אותן תוצאות כמו חיפוש מאפס', (
    tester,
  ) async {
    final raw =
        jsonDecode(File('assets/Acronyms.json').readAsStringSync())
            as Map<String, dynamic>;
    final data = raw.map(
      (key, value) => MapEntry(key, (value as List).cast<String>()),
    );
    final repository = DictionaryLookupRepository(
      loadAcronyms: () async => data,
    );
    await repository.ensureAcronymsLoaded();
    final catalog = repository.getAcronymSearchCatalog();
    final words = [
      for (var i = 0; i < catalog.length; i += catalog.length ~/ 10)
        catalog[i].displayAcronym,
      for (var i = 5; i < catalog.length; i += catalog.length ~/ 4)
        catalog[i].meanings.first.split(' ').first,
      'רמב"ם',
      // שאילתה שהנרמול שלה מתחיל ריק, ומקף ורווח שהנרמול משנה.
      '!א',
      'א״ב',
      'א־ב',
      'א ב',
    ];
    final steps = [
      for (final word in words) ...[
        for (var n = 1; n <= word.length; n++) word.substring(0, n),
        for (var n = word.length - 1; n >= 0; n--) word.substring(0, n),
      ],
      // השאילתה מתארכת גם בתחילתה.
      'ב',
      'אב',
      'שאב',
    ];

    final settings = _SettingsBloc();
    addTearDown(settings.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SettingsBloc>.value(
          value: settings,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: AcronymsDictionaryScreen(repository: repository),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final expected = <String, List<String>>{};
    for (final query in steps) {
      await tester.enterText(find.byType(TextField), query);
      await tester.pumpAndSettle();
      expect(
        _shownAcronyms(tester),
        expected.putIfAbsent(
          query,
          () => _searchFromScratch(repository, catalog, query),
        ),
        reason: query,
      );
    }
  });
}
