import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/view/tab_visuals.dart';

const _title = 'משנה ברורה';
const _titleBox = ValueKey('title-box');

void main() {
  setUpAll(() async {
    for (final (family, asset) in [
      ('Rubik', 'fonts/Rubik-VariableFont_wght.ttf'),
      ('NotoSerifHebrew', 'fonts/NotoSerifHebrew-VariableFont_wdth,wght.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
    }
  });

  Future<RenderParagraph> pump(
    WidgetTester tester, {
    required TextStyle style,
    required TextDirection direction,
    required double scale,
    required bool bold,
    required double width,
    bool explicitWidth = false,
    bool reference = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: style.color == Colors.white
              ? Brightness.dark
              : Brightness.light,
        ),
        home: MediaQuery(
          data: MediaQueryData(
            boldText: bold,
            textScaler: TextScaler.linear(scale),
          ),
          child: Directionality(
            textDirection: direction,
            child: Center(
              child: DefaultTextStyle(
                style: explicitWidth ? const TextStyle(fontSize: 40) : style,
                child: Builder(
                  builder: (context) {
                    final title = DefaultTextStyle(
                      style: style,
                      child: SizedBox(
                        key: _titleBox,
                        width: width,
                        height: 50,
                        child: Builder(
                          builder: (context) => reference
                              ? OverflowBox(
                                  minWidth: 0,
                                  maxWidth: double.infinity,
                                  child: const Text(
                                    _title,
                                    maxLines: 1,
                                    softWrap: false,
                                  ),
                                )
                              : buildFadedTabTitle(context, _title),
                        ),
                      ),
                    );
                    return reference
                        ? title
                        : SizedBox(
                            width: explicitWidth ? width + 40 : width,
                            child: TabTitleTooltip(
                              title: _title,
                              message: _title,
                              titleWidth: explicitWidth ? width : null,
                              titleStyle: explicitWidth ? style : null,
                              child: explicitWidth
                                  ? Align(
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      child: title,
                                    )
                                  : title,
                            ),
                          );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    return tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byKey(_titleBox),
        matching: find.byType(RichText),
      ),
    );
  }

  Future<void> check(
    WidgetTester tester, {
    required TextStyle style,
    required TextDirection direction,
    required double scale,
    required bool bold,
    required double width,
    required bool explicitWidth,
  }) async {
    final paragraph = await pump(
      tester,
      style: style,
      direction: direction,
      scale: scale,
      bold: bold,
      width: width,
      explicitWidth: explicitWidth,
    );
    final box = tester.renderObject<RenderBox>(find.byKey(_titleBox));
    final clipped = paragraph.size.width > box.size.width + 0.5;
    expect(
      find.byType(ShaderMask),
      clipped ? findsOneWidget : findsNothing,
      reason: 'הדהייה צריכה להתאים לרוחב הטקסט המרונדר בפועל',
    );
    expect(
      find.byTooltip(_title),
      clipped ? findsOneWidget : findsNothing,
      reason: 'שם מלא בטולטיפ זמין רק כשהטקסט המרונדר נחתך',
    );
    expect(paragraph.text.style?.color, style.color);
    final actualStart = paragraph.localToGlobal(Offset.zero).dx;
    final boxStart = box.localToGlobal(Offset.zero).dx;
    expect(
      direction == TextDirection.ltr
          ? actualStart
          : actualStart + paragraph.size.width,
      closeTo(
        direction == TextDirection.ltr ? boxStart : boxStart + box.size.width,
        0.01,
      ),
    );
  }

  testWidgets('נגישות הדגשה הופכת כותרת נכנסת לחתוכה וחזרה, עם גופן אמיתי', (
    tester,
  ) async {
    const style = TextStyle(
      fontFamily: 'Rubik',
      fontSize: 14,
      color: Colors.black,
    );
    for (final direction in TextDirection.values) {
      final normal = await pump(
        tester,
        style: style,
        direction: direction,
        scale: 1,
        bold: false,
        width: 500,
        reference: true,
      );
      final normalWidth = normal.size.width;
      final bold = await pump(
        tester,
        style: style,
        direction: direction,
        scale: 1,
        bold: true,
        width: 500,
        reference: true,
      );
      expect(bold.size.width, greaterThan(normalWidth + 2));
      for (final explicitWidth in [false, true]) {
        for (final bold in [false, true, false]) {
          await check(
            tester,
            style: style,
            direction: direction,
            scale: 1,
            bold: bold,
            width: normalWidth + 1,
            explicitWidth: explicitWidth,
          );
        }
      }
    }
  });

  testWidgets(
    'הדהייה והטולטיפ עוקבים אחר פריסה, משקל, ירושה, קנה מידה ומטמון חם',
    (tester) async {
      for (final style in [
        const TextStyle(
          fontFamily: 'Rubik',
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: Colors.black,
        ),
        const TextStyle(
          inherit: false,
          fontFamily: 'Rubik',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        const TextStyle(
          fontFamily: 'NotoSerifHebrew',
          fontSize: 24,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.3,
          height: 1.5,
          color: Colors.black,
        ),
      ]) {
        for (final direction in TextDirection.values) {
          for (final scale in [1.0, 1.5]) {
            final normal = await pump(
              tester,
              style: style,
              direction: direction,
              scale: scale,
              bold: false,
              width: 500,
              reference: true,
            );
            final normalWidth = normal.size.width;
            final bold = await pump(
              tester,
              style: style,
              direction: direction,
              scale: scale,
              bold: true,
              width: 500,
              reference: true,
            );
            final boldWidth = bold.size.width;
            for (final width in [
              math.min(normalWidth, boldWidth) - 5,
              (normalWidth + boldWidth) / 2,
              math.max(normalWidth, boldWidth) + 5,
            ]) {
              for (final explicitWidth in [false, true]) {
                for (final bold in [false, true, false]) {
                  await check(
                    tester,
                    style: style,
                    direction: direction,
                    scale: scale,
                    bold: bold,
                    width: width,
                    explicitWidth: explicitWidth,
                  );
                }
              }
            }
          }
        }
      }
    },
  );
}
