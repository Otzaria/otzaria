import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/utils/snippet_builder.dart';

void main() {
  test('SnippetBuilder שומר גרשיים בתצוגת ראשי תיבות', () {
    final spans = SnippetBuilder.createSnippetSpans(
      fullHtml: '<p>רש"י אומר</p>',
      query: 'רשי',
      defaultStyle: const TextStyle(),
      highlightStyle: const TextStyle(fontWeight: FontWeight.bold),
      availableWidth: 400,
      searchOptions: const {},
      alternativeWords: const {},
    );

    final renderedText = spans
        .whereType<TextSpan>()
        .map((span) => span.text ?? '')
        .join();

    expect(renderedText, contains('רש"י'));
  });
}
