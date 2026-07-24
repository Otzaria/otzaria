import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/search_query_sync.dart';

void main() {
  test('syncSearchControllerQuery updates text and places caret at end', () {
    final controller = TextEditingController(text: 'ישן');

    syncSearchControllerQuery(controller, 'חדש');

    expect(controller.text, 'חדש');
    expect(controller.selection.baseOffset, 3);
    expect(controller.selection.extentOffset, 3);
  });

  test(
    'syncSearchControllerQuery leaves selection unchanged for same text',
    () {
      final controller = TextEditingController(text: 'קיים')
        ..selection = const TextSelection(baseOffset: 0, extentOffset: 4);

      syncSearchControllerQuery(controller, 'קיים');

      expect(controller.text, 'קיים');
      expect(controller.selection.baseOffset, 0);
      expect(controller.selection.extentOffset, 4);
    },
  );

  test('applyInBookSearchQuery updates controller and notifies state sync', () {
    final controller = TextEditingController();
    String? syncedQuery;

    applyInBookSearchQuery(
      controller: controller,
      query: 'חיפוש מתקדם',
      onQueryChanged: (value) => syncedQuery = value,
    );

    expect(controller.text, 'חיפוש מתקדם');
    expect(syncedQuery, 'חיפוש מתקדם');
  });
}
