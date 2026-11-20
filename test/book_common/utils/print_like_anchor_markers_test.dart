import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/book_common/utils/link_anchor_variants.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_display/models/text_display_layer.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/text_display/models/text_display_slot.dart';
import 'package:otzaria/text_display/text_display_resolver.dart';

const _commentator = 'באר הגולה על שולחן ערוך אורח חיים';

final _link = Link(
  heRef: '$_commentator א, א',
  index1: 1,
  path2: _commentator,
  index2: 1,
  connectionType: 'commentary',
  anchorStart: 4,
  anchorEnd: null,
  anchorLabel: 'א',
);

String _inject({required bool printLike}) => injectLinkAnchorMarkers(
  rawLine: 'ישכים בבקר',
  anchorLinks: [_link],
  styleIndexByCommentator: anchorStyleIndexByCommentator([_link]),
  lineIndex: 0,
  printLike: printLike,
);

void main() {
  group('print-like commentary markers (issue #4394)', () {
    test('כבדפוס: האות בלי סוגריים, במחלקת הווריאנט "כבדפוס"', () {
      final html = _inject(printLike: true);
      expect(html, contains('link-anchor-$kLinkAnchorPrintStyleIndex"'));
      expect(html, contains('>א</a>'));
      expect(html, isNot(matches(RegExp(r'[(\[{]א[)\]}]'))));
    });

    test('בלי האפשרות: וריאנט המפרש וסוגריו, כמו קודם', () {
      final html = _inject(printLike: false);
      final index = anchorStyleIndexByCommentator([_link])[_commentator]!;
      expect(index, lessThan(kLinkAnchorPrintStyleIndex));
      expect(html, contains('link-anchor-$index"'));
      expect(html, contains('>${wrapLinkAnchorLetter('א', index)}</a>'));
    });

    test('שני מסלולי הרינדור: גופן הטקסט, בלי הדגשה, נטייה או קו תחתון', () {
      final variant = linkAnchorVariantFromClasses([
        'link-anchor',
        'link-anchor-$kLinkAnchorPrintStyleIndex',
      ]);
      expect(variant, same(kLinkAnchorPrintVariant));
      expect(linkAnchorVariantCss(variant), isEmpty);
      const base = TextStyle(fontFamily: 'FrankRuhlCLM', fontSize: 20);
      expect(applyLinkAnchorVariant(variant, base), base);
    });

    test('הקצאת וריאנט למפרש לעולם אינה נופלת על "כבדפוס"', () {
      for (var i = 0; i < 200; i++) {
        final link = Link(
          heRef: 'מפרש $i א, א',
          index1: 1,
          path2: 'מפרש $i',
          index2: 1,
          connectionType: 'commentary',
          anchorStart: 0,
        );
        expect(
          anchorStyleIndexByCommentator([link])['מפרש $i'],
          lessThan(kLinkAnchorPrintStyleIndex),
        );
      }
    });

    test('טלאי: JSON הלוך-חזור, ירושה מהשכבה, וברירת מחדל ללא שינוי', () {
      expect(
        TextDisplayProfile.defaults.anchorMarkerStyle,
        AnchorMarkerStyle.variants,
      );
      const patch = TextDisplayPatch(
        anchorMarkerStyle: AnchorMarkerStyle.print,
      );
      expect(patch.toJson(), {'anchorMarkerStyle': 'print'});
      expect(TextDisplayPatch.fromJson(patch.toJson()), patch);
      expect(
        TextDisplayPatch.fromJson(const {'anchorMarkerStyle': 'x'}).isEmpty,
        isTrue,
      );
      final resolved = TextDisplayResolver.resolve(
        slot: TextDisplaySlot.root,
        layers: [
          TextDisplayLayer({TextDisplaySlot.root: patch}),
        ],
      );
      expect(resolved.printLikeAnchorMarkers, isTrue);
      expect(
        patch.pruneAgainst(resolved).isEmpty,
        isTrue,
        reason: 'ערך ששווה לבסיס נמחק מהטלאי',
      );
    });
  });
}
