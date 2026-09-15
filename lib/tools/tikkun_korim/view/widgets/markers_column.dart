/// עמודת המסמנים האמצעית: פרק:פסוק בגימטריה, שם העליה ושם העליה המחוברת.
library;

import 'package:flutter/material.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_render_metrics.dart';
import 'package:otzaria/utils/text/numeral_formats.dart';

class MarkersColumn extends StatelessWidget {
  final TikkunRenderMetrics metrics;
  final String? aliyaName;
  final String? combinedAliyaName;

  /// המפטיר — שם נפרד, שכן הוא עשוי להתחיל באותה שורה כמו עליה ז'.
  final String? maftirName;

  /// הפסקת שני וחמישי בתוך העליה הראשונה — סימן משני.
  final String? weekdayAliyaName;

  /// חלופת חלוקה מקובלת לעליה — מוצגת כ-tooltip על שם העליה.
  final String? aliyaAlternative;

  /// "ספר תורה שני" / "שלישי" בקריאה שנקראת מכמה ספרים.
  final String? torahScrollLabel;

  /// מספר הפרק — מוצג רק כשהוא חדש ביחס לשורה הקודמת.
  final int? chapterNum;
  final int? verseNum;

  const MarkersColumn({
    super.key,
    required this.metrics,
    this.aliyaName,
    this.combinedAliyaName,
    this.maftirName,
    this.weekdayAliyaName,
    this.aliyaAlternative,
    this.torahScrollLabel,
    this.chapterNum,
    this.verseNum,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = TextStyle(
      fontFamily: metrics.nikudFontFamily,
      fontSize: metrics.rowFontSize,
      height: 1.15,
      color: cs.onSurface,
    );
    final children = <Widget>[];

    if (torahScrollLabel != null) {
      children.add(
        Text(
          torahScrollLabel!,
          style: base.copyWith(
            fontSize: metrics.em(0.75),
            fontWeight: FontWeight.bold,
            color: cs.tertiary,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (aliyaName != null) {
      Widget label = Text(
        aliyaName!,
        style: base.copyWith(
          fontSize: metrics.em(0.85),
          fontWeight: FontWeight.bold,
          color: cs.primary,
        ),
        textAlign: TextAlign.center,
      );
      if (aliyaAlternative != null) {
        label = Tooltip(message: 'יש גורסים $aliyaAlternative', child: label);
      }
      children.add(label);
    }
    if (maftirName != null) {
      // המפטיר אינו עליה מן המניין — מובחן בקו תחתון ובגוון משני.
      children.add(
        Text(
          maftirName!,
          style: base.copyWith(
            fontSize: metrics.em(0.85),
            fontWeight: FontWeight.bold,
            color: cs.secondary,
            decoration: TextDecoration.underline,
            decorationColor: cs.secondary,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (weekdayAliyaName != null) {
      children.add(
        Text(
          'ב׳ ה׳ $weekdayAliyaName',
          style: base.copyWith(
            fontSize: metrics.em(0.7),
            color: cs.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (combinedAliyaName != null) {
      children.add(
        Text(
          '$combinedAliyaName מחובר',
          style: base.copyWith(
            fontSize: metrics.em(0.75),
            fontStyle: FontStyle.italic,
            color: cs.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (chapterNum != null) {
      children.add(
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${toHebrewNumeral(chapterNum!)} ',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              TextSpan(
                text: toHebrewNumeral(verseNum ?? 1),
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          style: base.copyWith(fontSize: metrics.em(0.85)),
          textAlign: TextAlign.center,
        ),
      );
    } else if (verseNum != null) {
      children.add(
        Text(
          toHebrewNumeral(verseNum!),
          style: base.copyWith(
            fontSize: metrics.em(0.85),
            color: cs.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}
