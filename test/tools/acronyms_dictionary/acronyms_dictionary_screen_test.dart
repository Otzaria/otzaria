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

class _CountingRepository extends DictionaryLookupRepository {
  _CountingRepository(Map<String, List<String>> entries)
    : super(loadAcronyms: () async => entries);

  int normalizations = 0;
  int legacyMatches = 0;

  @override
  String normalizeAcronymQuery(String query) {
    normalizations++;
    return super.normalizeAcronymQuery(query);
  }

  @override
  bool acronymMatchesQuery({required String acronym, required String query}) {
    legacyMatches++;
    return super.acronymMatchesQuery(acronym: acronym, query: query);
  }
}

List<String> _legacyResults(DictionaryLookupRepository repository, String raw) {
  final query = raw.trim();
  if (query.isEmpty) return [];
  final results = repository
      .getAcronymSearchCatalog()
      .where(
        (entry) =>
            entry.displayAcronym.contains(query) ||
            repository.acronymMatchesQuery(
              acronym: entry.displayAcronym,
              query: query,
            ) ||
            entry.meanings.any((meaning) => meaning.contains(query)),
      )
      .toList();
  int rank(AcronymCatalogEntry entry) {
    final acronym = entry.displayAcronym;
    if (acronym == query) return 0;
    if (acronym.startsWith(query)) return 1;
    if (acronym.contains(query)) return 2;
    return repository.acronymMatchesQuery(acronym: acronym, query: query)
        ? 3
        : 4;
  }

  results.sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    final byLength = a.displayAcronym.length.compareTo(b.displayAcronym.length);
    return byLength != 0
        ? byLength
        : a.displayAcronym.compareTo(b.displayAcronym);
  });
  return results.map((entry) => entry.displayAcronym).toList();
}

void main() {
  testWidgets('מילון אמיתי: סדר שקול ונרמול יחיד לכל שאילתה', (tester) async {
    final raw =
        jsonDecode(File('assets/Acronyms.json').readAsStringSync())
            as Map<String, dynamic>;
    final data = raw.map(
      (key, value) => MapEntry(key, (value as List).cast<String>()),
    );
    final repository = _CountingRepository(data);
    final oracle = DictionaryLookupRepository(loadAcronyms: () async => data);
    await repository.ensureAcronymsLoaded();
    await oracle.ensureAcronymsLoaded();
    final catalog = repository.getAcronymSearchCatalog();
    expect(catalog.length, greaterThan(12000));
    for (final entry in catalog) {
      expect(
        entry.normalizedKey,
        oracle.normalizeAcronymQuery(entry.displayAcronym),
      );
    }
    final queries = [
      'א',
      'ש',
      'ר',
      'רמבם',
      'רמב״ם',
      ' רמב"ם ',
      'א׳א',
      'שוע',
      'בית',
      'דבר',
      'א״ב',
      '"',
      '׳',
      '!!!',
      '123',
      '',
      'א-ב',
      'א ב',
      'אַב',
    ];
    for (final entry
        in catalog.where((entry) => entry.displayAcronym.length > 1).take(10)) {
      queries.add(entry.displayAcronym);
      queries.add(entry.displayAcronym.substring(0, 2));
    }
    final expected = {
      for (final query in queries) query: _legacyResults(oracle, query),
    };
    final meaningsByAcronym = {
      for (final entry in catalog) entry.displayAcronym: entry.meanings,
    };
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
    for (final query in queries) {
      repository.normalizations = 0;
      repository.legacyMatches = 0;
      await tester.enterText(find.byType(TextField), query);
      await tester.pumpAndSettle();
      expect(
        repository.normalizations,
        query.trim().isEmpty ? 0 : 1,
        reason: query,
      );
      expect(repository.legacyMatches, 0, reason: query);
      final lists = tester.widgetList<ListView>(find.byType(ListView)).toList();
      final actual = <String>[];
      if (lists.isNotEmpty) {
        final delegate =
            lists.single.childrenDelegate as SliverChildBuilderDelegate;
        final context = tester.element(find.byType(ListView));
        for (var i = 0; i < delegate.childCount!; i++) {
          final card = delegate.builder(context, i)! as AcronymResultCard;
          actual.add(card.acronym);
          expect(card.meanings, meaningsByAcronym[card.acronym]);
        }
      }
      expect(actual, expected[query], reason: query);
      expect(tester.takeException(), isNull);
    }
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.byType(AcronymResultCard), findsNothing);
  });
}
