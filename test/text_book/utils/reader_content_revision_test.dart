import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reader_build_policy.dart';

void main() {
  test('revision חדש בונה מחדש בלי לסרוק את כל תוכן הספר', () {
    final beforeContent = _CountingContent(100000, 'לפני');
    final afterContent = _CountingContent(100000, 'אחרי');
    final before = _state(beforeContent, version: 4);
    final after = _state(afterContent, version: 5);

    expect(shouldRebuildReader(before, after), isTrue);
    expect(beforeContent.reads + afterContent.reads, 0);
  });

  test('מטא-בחירה בלבד באותו snapshot אינו קורא שורות ואינו בונה', () {
    final content = _CountingContent(100000, 'טקסט');
    final before = _state(content, version: 8);
    final after = before.copyWith(visibleIndices: const [90000]);

    expect(shouldRebuildReader(before, after), isFalse);
    expect(content.reads, 0);
  });

  test('תוכן שונה באותה revision עדיין בונה עבור צרכנים ללא revision', () {
    final beforeContent = _CountingContent(100, 'לפני');
    final afterContent = _CountingContent(100, 'אחרי');

    expect(
      shouldRebuildReader(_state(beforeContent), _state(afterContent)),
      isTrue,
    );
    expect(beforeContent.reads + afterContent.reads, greaterThan(0));
  });

  test('תוכן שווה בעותקים שונים ללא revision משמר השוואת תוכן', () {
    final before = _state(_CountingContent(100, 'טקסט'));
    final after = _state(_CountingContent(100, 'טקסט'));

    expect(shouldRebuildReader(before, after), isFalse);
  });

  test('טעינת שורה ריקה נחשבת שינוי גם כשזהות התוכן לא השתנתה', () {
    final before = _state(const ['', ''], version: 3).copyWith(
      loadedLineFlags: const [true, false],
    );
    final after = before.copyWith(
      contentVersion: 4,
      loadedLineFlags: const [true, true],
    );

    expect(shouldRebuildReader(before, after), isTrue);
  });

  test('המסנן שמתעלם מבחירה עדיין מזהה שינוי תוכן ללא סריקה', () {
    final beforeContent = _CountingContent(100000, 'לפני');
    final afterContent = _CountingContent(100000, 'אחרי');
    final before = _state(beforeContent, version: 4);
    final after = _state(afterContent, version: 5).copyWith(
      selectedIndex: 99999,
      selectedIndices: const {99999},
    );

    expect(shouldRebuildIgnoringSelection(before, after), isTrue);
    expect(beforeContent.reads + afterContent.reads, 0);
  });
}

TextBookLoaded _state(List<String> content, {int version = 0}) =>
    TextBookLoaded(
      book: TextBook(title: 'בדיקת revision'),
      content: content,
      contentVersion: version,
      fontSize: 20,
      showLeftPane: false,
      showSplitView: false,
      activeCommentators: const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      linksByLine: const {},
      tableOfContents: const [],
      removeNikud: false,
      visibleIndices: const [0],
      pinLeftPane: false,
      searchText: '',
    );

class _CountingContent extends ListBase<String> {
  _CountingContent(this._length, this.lastLine);

  final int _length;
  final String lastLine;
  var reads = 0;

  @override
  int get length => _length;

  @override
  set length(int value) => throw UnsupportedError('Read-only test list');

  @override
  String operator [](int index) {
    RangeError.checkValidIndex(index, this);
    reads++;
    return index + 1 == length ? lastLine : 'טקסט';
  }

  @override
  void operator []=(int index, String value) =>
      throw UnsupportedError('Read-only test list');
}
