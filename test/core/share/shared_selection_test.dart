import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/core/share/shared_selection.dart';
import 'package:otzaria/core/share/text_share_service.dart';
import 'package:otzaria/divine_names/models/divine_name_forms.dart';

class _FakeShareService implements TextShareService {
  final shared = <String>[];

  @override
  Future<void> shareText(String text, {Rect? origin}) async => shared.add(text);
}

String _lines(int count) =>
    [for (var i = 1; i <= count; i++) 'שורה $i'].join('\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeShareService share;
  late TextShareService previous;

  setUp(() {
    previous = TextShareService.instance;
    share = _FakeShareService();
    TextShareService.instance = share;
  });

  tearDown(() => TextShareService.instance = previous);

  group('isAvailableOn', () {
    test('רק Android ו-iOS', () {
      expect(TextShareService.isAvailableOn(TargetPlatform.android), isTrue);
      expect(TextShareService.isAvailableOn(TargetPlatform.iOS), isTrue);
      for (final p in [
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.fuchsia,
      ]) {
        expect(TextShareService.isAvailableOn(p), isFalse, reason: '$p');
      }
    });
  });

  group('shareSelectedText', () {
    test('משתף את הטקסט כמות שהוא', () async {
      await shareSelectedText('בראשית ברא');
      expect(share.shared, ['בראשית ברא']);
    });

    test('טקסט ריק או רווחים לא משותף', () async {
      await shareSelectedText('  \n ');
      expect(share.shared, isEmpty);
    });

    test('מסיר את תווי החיבור של שמות קדושים כמו בהעתקה', () async {
      final text =
          'ה$kDivineNameWordJoiner'
          'שם';
      await shareSelectedText(text);
      expect(share.shared, [withoutDivineNameJoiners(text)]);
    });

    test('בספר מוגן: מעל המגבלה נחסם, עד המגבלה מותר', () async {
      const protection = BookProtection(level: 1);
      await shareSelectedText(
        _lines(BookProtection.copySegmentLimit + 1),
        protection: protection,
      );
      expect(share.shared, isEmpty);

      final allowed = _lines(BookProtection.copySegmentLimit);
      await shareSelectedText(allowed, protection: protection);
      expect(share.shared, [allowed]);
    });
  });
}
