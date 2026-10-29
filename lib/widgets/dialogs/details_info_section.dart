import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';

/// כותרת בראש דיאלוג מידע: שם הפריט בגדול, ומתחתיו שורת משנה עמומה.
class DetailsHeading extends StatelessWidget {
  const DetailsHeading({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = subtitle?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: AppTokens.fontXL,
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
        if (sub.isNotEmpty) ...[
          const SizedBox(height: AppTokens.spaceXS),
          Text(
            sub,
            style: TextStyle(
              fontSize: AppTokens.fontMD,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// כרטיס מקטע בדיאלוג מידע: רקע כרטיס ומסגרת עדינה, כותרת אופציונלית, ובין
/// השורות קו חוצץ. בכרטיס שמחזיק [DetailsInfoSection] או טקסט חופשי.
class DetailsCard extends StatelessWidget {
  const DetailsCard({
    super.key,
    required this.children,
    this.title,
    this.icon,
  });

  final List<Widget> children;
  final String? title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final divider = Divider(
      height: 1,
      color: cs.outlineVariant.withValues(alpha: 0.5),
    );
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppSurfaces.card(context),
        borderRadius: AppTokens.borderRadiusAll,
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMD,
        vertical: 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.only(
                top: AppTokens.spaceSM + 2,
                bottom: AppTokens.spaceSM,
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: AppTokens.fontLG, color: cs.primary),
                    const SizedBox(width: AppTokens.spaceSM),
                  ],
                  Text(
                    title!,
                    style: TextStyle(
                      fontSize: AppTokens.fontMD + 1,
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
            ),
            if (children.isNotEmpty) divider,
          ],
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) divider,
            children[i],
          ],
        ],
      ),
    );
  }
}

/// מקטע תווית־וערך אחיד לדיאלוגי מידע: התווית (עם אייקון) בתחילת השורה
/// והערך בסופה. עם [block] התווית בשורה משלה והערך מתחתיה ברוחב מלא — לערכים
/// ארוכים כמו נתיב או תיאור. מיועד לשימוש בתוך [DetailsCard].
class DetailsInfoSection extends StatelessWidget {
  const DetailsInfoSection({
    super.key,
    required this.title,
    required this.value,
    this.icon,
    this.valueDirection,
    this.block = false,
  });

  /// התווית שמופיעה לפני הערך.
  final String title;

  /// הערך המלא. הבחירה וההעתקה מסופקות ע"י AppSelectionArea שעוטף את הדיאלוג.
  final String value;

  /// אייקון שמזהה את סוג הפרט, מוצג לפני התווית.
  final IconData? icon;

  /// כיוון הערך, כאשר הוא שונה מכיוון הממשק.
  final TextDirection? valueDirection;

  final bool block;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: AppTokens.fontLG, color: cs.onSurfaceVariant),
          const SizedBox(width: AppTokens.spaceSM),
        ],
        Flexible(
          child: Text(
            // הנקודתיים נשארו בטקסטים הקיימים; בתוך הכרטיס הן מיותרות.
            title.endsWith(':') ? title.substring(0, title.length - 1) : title,
            style: TextStyle(
              fontSize: AppTokens.fontMD,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
    final valueText = Text(
      value,
      textDirection: valueDirection,
      style: TextStyle(
        fontSize: AppTokens.fontMD,
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSM + 1),
      // ברוחב טלפון שתי עמודות היו שוברות את הערך באמצע מילה.
      child: block || MediaQuery.sizeOf(context).width < 520
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                label,
                const SizedBox(height: AppTokens.spaceXS),
                valueText,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: label),
                const SizedBox(width: AppTokens.spaceMD),
                Expanded(flex: 6, child: valueText),
              ],
            ),
    );
  }
}

/// פסקת טקסט חופשית בתוך [DetailsCard], למשל תיאור. [bold] להדגשת פתיחה קצרה.
class DetailsText extends StatelessWidget {
  const DetailsText(this.text, {super.key, this.bold = false});

  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSM + 1),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppTokens.fontMD,
          height: 1.4,
          fontWeight: bold ? FontWeight.bold : null,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}
