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
