import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/search_feedback/search_feedback_service.dart';
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
          body: SingleChildScrollView(
            child: SearchFeedbackPanel(store: store, platformSupported: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('שיפור המנגנון'), findsOneWidget);
    expect(find.text(kSemanticSearchConsentTemplate), findsOneWidget);

    await tester.tap(find.text('שיפור המנגנון'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('שיפור המנגנון'));
    await tester.pumpAndSettle();

    expect(store.calls, ['grant', 'revoke']);
  });
  testWidgets('פלטפורמה לא נתמכת אינה מציגה מתג או נוסח הסכמה', (tester) async {
    final store = _FakeStore();
    await tester.pumpWidget(
      MaterialApp(
        home: SearchFeedbackPanel(store: store, platformSupported: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('שיפור המנגנון'), findsNothing);
    expect(find.text(kSemanticSearchConsentTemplate), findsNothing);
    expect(store.calls, isEmpty);
  });

  testWidgets('the blocked-network line shows only while blocked', (
    tester,
  ) async {
    final block = ValueNotifier<SearchFeedbackNetworkBlock?>(null);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SearchFeedbackPanel(
              store: _FakeStore(),
              platformSupported: true,
              networkBlock: block,
            ),
          ),
        ),
      ),
    );
    final line = find.byKey(const ValueKey('search-feedback-network-block'));
    expect(line, findsNothing);

    final seen = DateTime.utc(2026, 10, 4);
    block.value = SearchFeedbackNetworkBlock(
      firstSeen: seen,
      lastSeen: seen,
      retryAt: seen.add(const Duration(hours: 6)),
    );
    await tester.pump();
    expect(line, findsOneWidget);
    expect(find.textContaining('הנתונים נשמרים במחשב'), findsOneWidget);

    block.value = null;
    await tester.pump();
    expect(line, findsNothing);
  });
}
