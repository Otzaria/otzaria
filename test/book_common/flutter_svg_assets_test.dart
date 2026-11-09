import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/view/book_source_dialog.dart';
import 'package:otzaria/settings/tabs/about_settings_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final assets = <String>{
    kYamHaHachmaLogoAsset,
    ...[...aboutMainSources, ...aboutAdditionalSources]
        .map((source) => source['logo'])
        .whereType<String>()
        .where((logo) => logo.toLowerCase().endsWith('.svg')),
  };

  setUp(() => svg.cache.clear());
  tearDown(() => svg.cache.clear());

  testWidgets('לוגו המקור שומר על גובהו בזמן טעינה ליד טקסט עברי', (
    tester,
  ) async {
    final pending = Completer<ByteData>();
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          kYamHaHachmaLogoAsset,
          bundle: _DeferredAssetBundle(pending.future),
          height: 36,
        ),
        const SizedBox(width: 8),
        const Text('ים החכמה'),
      ],
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 16),
          child: Center(child: row),
        ),
      ),
    );
    expect(tester.getSize(find.byWidget(row)).height, 36);
  });

  for (final asset in assets) {
    test('טעינה ופענוח של לוגו מקורות הספרים: $asset', () async {
      final picture = await vg.loadPicture(SvgAssetLoader(asset), null);
      try {
        expect(picture.size.width, greaterThan(0));
        expect(picture.size.height, greaterThan(0));
      } finally {
        picture.picture.dispose();
      }
    });
  }
}

class _DeferredAssetBundle extends CachingAssetBundle {
  _DeferredAssetBundle(this.pending);

  final Future<ByteData> pending;

  @override
  Future<ByteData> load(String key) => pending;
}
