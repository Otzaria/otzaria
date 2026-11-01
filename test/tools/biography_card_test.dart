import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/biographies/models/biography.dart';
import 'package:otzaria/tools/biographies/widgets/biography_card.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';

class _UrlLauncher extends UrlLauncherPlatform {
  String? opened;
  @override
  LinkDelegate? get linkDelegate => null;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened = url;
    return true;
  }
}

void main() {
  const name = 'רבי בעל שם ארוך מאוד עם כינויים רבים ושם משפחה ארוך במיוחד';
  const relation = 'קרוב משפחה בעל תיאור קשר משפחתי ארוך מאוד';
  const description = 'תיאור מלא של החיבור שאסור לקצר או להסתיר בשום רוחב';
  const biography = Biography(
    id: 'test',
    name: 'רבי ישראל',
    summary: 'תקציר הביוגרפיה',
    family: [RelatedPerson(name: name, relation: relation, ref: 'related')],
    works: [BiographyWork(title: 'ספר לדוגמה', description: description)],
    sources: [
      BiographySource(
        credit: 'wikipedia',
        title: 'מקור מפורט עם שם ארוך במיוחד לבדיקת גלישת טקסט במסך צר',
        url: 'https://he.wikipedia.org/wiki/Test',
      ),
    ],
  );

  for (final width in [320.0, 360.0, 800.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('full linked details fit RTL width $width at scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? opened;
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      BiographyCard(
                        biography: biography,
                        initiallyExpanded: true,
                        canOpen: (_) => true,
                        onOpen: (id) => opened = id,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final paragraphs = tester.renderObjectList<RenderParagraph>(
          find.byType(RichText),
        );
        for (final paragraph in paragraphs) {
          final text = paragraph.text.toPlainText();
          if (text.contains(name) ||
              text.contains(relation) ||
              text.contains(description) ||
              text.startsWith('מקור מפורט')) {
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(paragraph.maxLines, isNull);
            final rect = paragraph.localToGlobal(Offset.zero) & paragraph.size;
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
          }
        }
        await tester.ensureVisible(find.text(name));
        await tester.tap(find.text(name));
        await tester.pumpAndSettle();
        expect(opened, 'related');
        final launcher = _UrlLauncher();
        final original = UrlLauncherPlatform.instance;
        UrlLauncherPlatform.instance = launcher;
        addTearDown(() => UrlLauncherPlatform.instance = original);
        final source = find.text(biography.sources.single.title!);
        await tester.ensureVisible(source);
        await tester.tap(source);
        await tester.pumpAndSettle();
        expect(launcher.opened, biography.sources.single.url);
      });
    }
  }

  testWidgets('נפטר מוצג בשורה נפרדת מתחת ל"נולד"', (tester) async {
    const withDates = Biography(
      id: 'dates',
      name: 'רבי ישראל',
      born: LifeEvent(hebrew: 'תתצ"ח'),
      died: LifeEvent(hebrew: 'תתקס"ה'),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: BiographyCard(biography: withDates)),
        ),
      ),
    );

    final born = tester.getTopLeft(find.textContaining('נולד'));
    final died = tester.getTopLeft(find.textContaining('נפטר'));

    expect(died.dy, greaterThan(born.dy));
  });
}
