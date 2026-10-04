import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/search_feedback/semantic_search_strings.dart';
import 'package:otzaria/settings/panels/search_feedback_panel.dart';

class _FakeStore implements SearchFeedbackConsentStore {
  final _controller = StreamController<SearchFeedbackConsent>.broadcast();
  SearchFeedbackConsent current = SearchFeedbackConsent.unknown;
  final calls = <String>[];

  void _set(SearchFeedbackConsent value, String call) {
    calls.add(call);
    current = value;
    _controller.add(value);
  }

  @override
  SearchFeedbackConsent get consent => current;

  @override
  Stream<SearchFeedbackConsent> get changes => _controller.stream;

  @override
  Future<void> grant() async => _set(SearchFeedbackConsent.granted, 'grant');

  @override
  Future<void> decline() async =>
      _set(SearchFeedbackConsent.declined, 'decline');

  @override
  Future<void> revoke() async => _set(SearchFeedbackConsent.declined, 'revoke');
}

void main() {
  testWidgets('the switch grants consent and turning it off revokes', (
    tester,
  ) async {
    final store = _FakeStore();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he', 'IL'),
        home: Scaffold(
          body: SingleChildScrollView(child: SearchFeedbackPanel(store: store)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('שיפור המנגנון'), findsOneWidget);
    expect(find.text(semanticSearchConsentText), findsOneWidget);

    await tester.tap(find.text('שיפור המנגנון'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('שיפור המנגנון'));
    await tester.pumpAndSettle();

    expect(store.calls, ['grant', 'revoke']);
  });
}
