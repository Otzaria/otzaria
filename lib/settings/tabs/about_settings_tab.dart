import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:otzaria/widgets/layout/adaptive_row.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/tabs/about_settings_data.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/widgets/dialogs/ad_popup_dialog.dart';

/// פותח כתובת URL בדפדפן החיצוני.
/// בלי canLaunchUrl — באנדרואיד 11+ הוא מחזיר false ל-https ומשתיק את הפתיחה.
Future<void> _launchUrl(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('Could not launch $url: $e');
  }
}

/// טאב "חכמי לב" — אודות, קהילה, תורמים ומפתחים.
class AboutSettingsTab extends StatelessWidget {
  const AboutSettingsTab({super.key});

  /// פריטי חיפוש בהגדרות. נסרק על-ידי tool/generate_search_index.dart.
  static const List<SettingsSearchEntry> searchEntries = [
    SettingsSearchEntry(
      id: 'about.team',
      title: 'אודות',
      subtitle: 'וצדקתו עומדת לעד — זה הכותב ספרים ומשאילן לאחרים',
      tab: SettingsTab.about,
      cardId: 'about.main',
      keywords: ['אודות', 'ציטוט', 'about'],
    ),
    SettingsSearchEntry(
      id: 'about.donate',
      title: 'תרום לפרויקט',
      subtitle:
          'תרומתך תעזור לנו להמשיך לפתח ולשפר את אוצריא עבור כלל ציבור הלומדים',
      tab: SettingsTab.about,
      cardId: 'about.donors',
      keywords: ['תרומה', 'נדרים', 'תרום', 'donate'],
    ),
    SettingsSearchEntry(
      id: 'about.aid',
      title: 'אוצריא מתגייסת לעזרת לומדי התורה',
      subtitle: 'מרכז המידע על ארגוני סיוע ללומדי התורה',
      tab: SettingsTab.about,
      cardId: 'about.aid',
      keywords: ['סיוע', 'תורה', 'לומדי תורה', 'עזרה'],
    ),
    SettingsSearchEntry(
      id: 'about.editing',
      title: 'הצטרף לצוות העריכה ומהדירי הספרים',
      subtitle: 'עזור לנו להוסיף ספרים חדשים לספריית אוצריא',
      tab: SettingsTab.about,
      cardId: 'about.library',
      keywords: ['עריכה', 'הצטרף', 'הוספת ספרים'],
    ),
    SettingsSearchEntry(
      id: 'about.dev',
      title: 'אודות פיתוח התוכנה',
      subtitle: 'מידע על מפתחי אוצריא ופיתוח התוכנה',
      tab: SettingsTab.about,
      cardId: 'about.dev',
      keywords: ['פיתוח', 'מפתחים', 'developers', 'אודות'],
    ),
    SettingsSearchEntry(
      id: 'about.donors',
      title: 'תורמים',
      subtitle: 'רשימת תורמי אוצריא',
      tab: SettingsTab.about,
      cardId: 'about.donors',
      keywords: ['תורמים', 'donors'],
    ),
    SettingsSearchEntry(
      id: 'about.developers',
      title: 'מפתחים',
      subtitle: 'רשימת מפתחי אוצריא',
      tab: SettingsTab.about,
      cardId: 'about.dev',
      keywords: ['מפתחים', 'צוות פיתוח', 'developers'],
    ),
    SettingsSearchEntry(
      id: 'about.contributors',
      title: 'תרמו מהונם ומזמנם',
      subtitle: 'אנשים שתרמו מהונם ומזמנם לפיתוח אוצריא',
      tab: SettingsTab.about,
      cardId: 'about.donors',
      keywords: ['תורמים', 'מתנדבים', 'עזרה', 'זמן'],
    ),
    SettingsSearchEntry(
      id: 'about.editors',
      title: 'מהדירי ספרים',
      subtitle: 'רשימת מהדירי הספרים בספריית אוצריא',
      tab: SettingsTab.about,
      cardId: 'about.library',
      keywords: ['מהדירים', 'עורכים'],
    ),
    SettingsSearchEntry(
      id: 'about.feedback',
      title: 'משוב ותמיכה',
      subtitle: 'נתקלת בבאג? פורום התמיכה והמשוב של אוצריא',
      tab: SettingsTab.about,
      cardId: 'about.dev',
      keywords: ['משוב', 'תמיכה', 'פורום', 'באג', 'שאלה'],
    ),
    SettingsSearchEntry(
      id: 'about.sources',
      title: 'מקור הספרים',
      subtitle: 'ספריא, דיקטה, אורייתא ועוד',
      tab: SettingsTab.about,
      cardId: 'about.library',
      keywords: ['מקור', 'ספריא', 'דיקטה', 'sefaria', 'אורייתא'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      primary: true,
      padding: const EdgeInsets.all(16.0),
      child: ToolPanelWrapper(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),

            // ── סיוע ──
            SettingsCard(
              cardId: 'about.aid',
              title: 'סיוע ללומדי תורה',
              children: [
                SettingsActionTile.text(
                  icon: FluentIcons.shield_task_24_filled,
                  title: 'אוצריא מתגייסת לעזרת לומדי התורה',
                  subtitle: 'מרכז המידע על ארגוני סיוע ללומדי התורה',
                  actions: [
                    ActionButton.recommended(
                      text: 'למידע נוסף',
                      onPressed: () => _openAdPopup(context),
                    ),
                  ],
                ),
              ],
            ),

            kSettingsCardSpacing,

            // ── ציטוט סיום ──
            SettingsCard(
              cardId: 'about.main',
              children: [_ClosingQuote()],
            ),

            kSettingsCardSpacing,

            // ── תורמים ──
            SettingsCard(
              cardId: 'about.donors',
              title: 'תורמים',
              children: [
                _padded(
                  _MemorialCardsGrid(
                    onDonationTap: () => _openUrl('https://nedar.im/ezOd'),
                  ),
                ),
                SettingsActionTile(
                  title: Text(
                    'תרמו מהונם ומזמנם',
                    style: SettingsCard.titleStyleOf(context),
                  ),
                  actions: [
                    _InfoChipWrap(
                      items: aboutEssentialPeople,
                      icon: FluentIcons.person_24_regular,
                    ),
                  ],
                ),
              ],
            ),

            kSettingsCardSpacing,

            // ── מפתחים ──
            SettingsCard(
              cardId: 'about.dev',
              title: 'אודות פיתוח התוכנה',
              children: [
                _cardTitle(context, 'מפתחים'),
                _padded(
                  _InfoChipSection(
                    items: aboutDevelopers,
                    icon: FluentIcons.person_24_regular,
                  ),
                ),
                SettingsActionTile.text(
                  icon: FluentIcons.chat_24_regular,
                  title: 'נתקלת בבאג? יש לך שאלה או משוב?',
                  subtitle: 'מוזמנים לבקר בפורום התמיכה והמשוב של אוצריא',
                  actions: [
                    ActionButton.recommended(
                      text: 'כניסה לפורום',
                      onPressed: () => _openUrl('https://otzaria.org/forum'),
                    ),
                  ],
                ),
              ],
            ),

            kSettingsCardSpacing,

            // ── אודות ספריית אוצריא ──
            SettingsCard(
              cardId: 'about.library',
              title: 'אודות ספריית אוצריא',
              children: [
                _cardTitle(
                  context,
                  'מקור הספרים',
                  subtitle:
                      'הספרים הותאמו במיוחד עבור אוצריא, וכן נוספו ספרים רבים '
                      'נוספים בזכות עבודתם המסורה של מהדירי הספרים.',
                ),
                _padded(_BookSourcesSection()),
                _cardTitle(context, 'מהדירי ספרים'),
                _padded(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InfoChipSection(
                        label: aboutTopEditorsLabel,
                        items: aboutTopEditors,
                        icon: FluentIcons.person_24_regular,
                      ),
                      const SizedBox(height: 20),
                      _InfoChipSection(
                        label: aboutRegularEditorsLabel,
                        items: aboutRegularEditors,
                        icon: FluentIcons.person_24_regular,
                      ),
                      const SizedBox(height: 16),
                      const _SubtitleText(
                        'באם שמכם אינו מופיע ברשימה או שאתם מעוניינים בשינוי, '
                        'אנא פנו למייל המערכת.',
                      ),
                    ],
                  ),
                ),
                SettingsActionTile.text(
                  icon: FluentIcons.edit_24_regular,
                  title: 'הצטרף לצוות העריכה ומהדירי הספרים',
                  subtitle: 'עזור לנו להוסיף ספרים חדשים לספריית אוצריא',
                  actions: [
                    ActionButton.recommended(
                      text: 'הצטרף לעריכה',
                      onPressed: () =>
                          _openUrl('https://www.otzaria.org/library'),
                    ),
                  ],
                ),
              ],
            ),

            kSettingsCardSpacing,

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: _ZayitCredit(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Image.asset(
            'assets/icon/iconnew.png',
            width: 60,
            height: 60,
            errorBuilder: (_, _, _) =>
                const Icon(FluentIcons.library_24_regular, size: 60),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'אוצריא',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'מאגר תורני חינמי, רחב ומהיר לשימוש בכל מקום.',
                  style: kSettingsSubtitleStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// כותרת כרטיס המוצגת בתוך ה-children — ממורכזת, צבע primary, מעט גדולה יותר.
  /// [subtitle] אופציונלי — מוצג ממורכז מתחת לכותרת בעיצוב תת-כותרת רגיל.
  Widget _cardTitle(BuildContext context, String text, {String? subtitle}) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: kSettingsSubtitleStyle,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// עוטף widget ב-padding אחיד של 16, החוזר בכל מקטעי הכרטיסים.
  Widget _padded(Widget child) =>
      Padding(padding: const EdgeInsets.all(16), child: child);

  Future<void> _openUrl(String url) => _launchUrl(url);

  void _openAdPopup(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const AdPopupDialog(
        title: 'אוצריא מתגייסת לעזרת לומדי התורה',
      ),
    );
  }
}

// ── _InfoChip ─────────────────────────────────────────────────────────────────

/// צ'יפ מידע אחיד לכל סוגי הנתונים בטאב — אייקון אפור + שם (primary כשיש קישור),
/// תיאור אופציונלי בסוגריים, ולחיץ (InkWell) כשקיים url. מאוחד לכל הסקציות.
class _InfoChipWrap extends StatelessWidget {
  final List<Map<String, String>> items;
  final IconData icon;

  const _InfoChipWrap({required this.items, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: items
          .map(
            (c) => _InfoChip(
              name: c['name']!,
              url: c['url'] ?? '',
              description: c['description'],
              logo: c['logo'],
              logoOriginalColor: c['logoOriginalColor'] == 'true',
              icon: icon,
            ),
          )
          .toList(),
    );
  }
}

/// טקסט בעיצוב תת-כותרת, ממורכז — לתוויות ולהערות במקטעי הכרטיסים.
class _SubtitleText extends StatelessWidget {
  final String text;

  const _SubtitleText(this.text);

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: kSettingsSubtitleStyle,
    ),
  );
}

/// מקטע צ'יפים ברוחב מלא, עם כותרת/תיאור אופציונלי מעליו.
/// מאחד את עיצוב סקציות הצ'יפים (מפתחים, מקור הספרים, מהדירים).
class _InfoChipSection extends StatelessWidget {
  final String? label;
  final List<Map<String, String>> items;
  final IconData icon;

  const _InfoChipSection({this.label, required this.items, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) ...[
          _SubtitleText(label!),
          const SizedBox(height: 10),
        ],
        _InfoChipWrap(items: items, icon: icon),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String name;
  final String url;
  final String? description;
  final String? logo;
  final bool logoOriginalColor;
  final IconData icon;

  const _InfoChip({
    required this.name,
    required this.url,
    this.description,
    this.logo,
    this.logoOriginalColor = false,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasUrl = url.isNotEmpty;
    final contentColor = hasUrl
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    // סגנון מפורש התואם למראה בכרטיס 'תרמו מהונם' — labelSmall (w500) של
    // ListTile.trailing עם גודל הכותרת — כך אחיד בכל מיקום ולא תלוי בהקשר.
    final nameStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontSize: kSettingsTitleStyle.fontSize,
      color: contentColor,
    );

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (logo != null)
            // לוגו צבעוני מעומעם כדי שלא יבלוט מול שאר הפריטים החד-צבעוניים.
            Opacity(
              opacity: logoOriginalColor ? 0.6 : 1,
              child: SvgPicture.asset(
                logo!,
                height: 16,
                colorFilter: logoOriginalColor
                    ? null
                    : ColorFilter.mode(contentColor, BlendMode.srcIn),
              ),
            )
          else
            Icon(icon, size: 15, color: contentColor),
          const SizedBox(width: 6),
          Text(name, style: nameStyle),
          if (description != null && description!.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text('(${description!})', style: kSettingsSubtitleStyle),
          ],
        ],
      ),
    );

    if (!hasUrl) return content;
    return InkWell(
      onTap: () => _launchUrl(url),
      borderRadius: AppTokens.borderRadiusAll,
      child: content,
    );
  }
}

// ── _BookSourcesSection ───────────────────────────────────────────────────────

class _BookSourcesSection extends StatelessWidget {
  const _BookSourcesSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoChipSection(
          label: aboutMainSourcesLabel,
          items: aboutMainSources,
          icon: FluentIcons.library_24_regular,
        ),
        const SizedBox(height: 16),
        _InfoChipSection(
          label: aboutAdditionalSourcesLabel,
          items: aboutAdditionalSources,
          icon: FluentIcons.library_24_regular,
        ),
      ],
    );
  }
}

// ── _ClosingQuote ─────────────────────────────────────────────────────────────

class _ClosingQuote extends StatelessWidget {
  const _ClosingQuote();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: _SurfaceCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              Icon(
                FluentIcons.book_open_24_regular,
                size: 32,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'וְצִדְקָתוֹ עֹמֶדֶת לָעַד',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '(תהילים קיב, ג)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Divider(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Icon(
                        FluentIcons.sparkle_24_regular,
                        size: 14,
                        color: colorScheme.primary.withValues(alpha: 0.6),
                      ),
                    ),
                    Expanded(
                      child: Divider(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'זֶה הַכּוֹתֵב סְפָרִים וּמַשְׁאִילָן לַאֲחֵרִים',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '(כתובות נ.)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _ZayitCredit ──────────────────────────────────────────────────────────────

/// קרדיט Zayit עם קישור לחיץ inline לאתר, מיושר לתחילת השורה.
class _ZayitCredit extends StatefulWidget {
  const _ZayitCredit();

  @override
  State<_ZayitCredit> createState() => _ZayitCreditState();
}

class _ZayitCreditState extends State<_ZayitCredit> {
  static const _url = 'https://zayitapp.com/';
  final _recognizer = TapGestureRecognizer();

  @override
  void initState() {
    super.initState();
    _recognizer.onTap = () => _launchUrl(_url);
  }

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        style: kSettingsSubtitleStyle,
        children: [
          const TextSpan(
            text:
                'Sefaria book conversion, the fuzzy search, and the library '
                'updates are powered by the technologies that drive Zayit — ',
          ),
          TextSpan(
            text: _url,
            style: TextStyle(color: colorScheme.primary),
            recognizer: _recognizer,
          ),
          const TextSpan(text: ' (licensed under GNU AGPL v3).'),
        ],
      ),
      textAlign: TextAlign.start,
      textDirection: TextDirection.ltr,
    );
  }
}

// ── _MemorialCardsGrid ────────────────────────────────────────────────────────

class _MemorialCardsGrid extends StatelessWidget {
  final VoidCallback onDonationTap;
  const _MemorialCardsGrid({required this.onDonationTap});

  @override
  Widget build(BuildContext context) {
    return AdaptiveRow(
      breakpoint: 400,
      spacing: 12,
      equalHeight: true,
      children: [
        _MemorialCard.donor(
          title: "לע\"נ ר' משה בן יהודה ראה ז\"ל",
          description: 'סכום משמעותי לפיתוח התוכנה',
        ),
        _MemorialCard.donor(
          title:
              "לע\"נ ר' משה ב\"ר פרץ ובנו ר' יצחק ב\"ר משה, והאשה הכשרה מרת רחל יהודית בת אליעזר",
          description:
              "ולהצלחת דוד ב\"ר יחזקאל ומשפחתו בתורה וביראת שמים\nתרומה גדולה ורבה לפיתוח התוכנה",
        ),
        _MemorialCard.donation(onDonate: onDonationTap),
      ],
    );
  }
}

/// כרטיס משטח אחיד — רקע surfaceContainerHigh, פינות מעוגלות, ללא מסגרת.
class _SurfaceCard extends StatelessWidget {
  final Widget child;
  const _SurfaceCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: child,
    );
  }
}

/// כרטיס הנצחה — `donor` למנציח קיים, `donation` למקום פנוי עם כפתור תרומה.
class _MemorialCard extends StatelessWidget {
  final IconData icon;
  final bool dimIcon;
  final String title;
  final double titleFontSize;
  final String? description;
  final VoidCallback? onDonate;

  const _MemorialCard.donor({required this.title, required this.description})
    : icon = FluentIcons.fire_24_filled,
      dimIcon = false,
      titleFontSize = 14,
      onDonate = null;

  const _MemorialCard.donation({required this.onDonate})
    : icon = FluentIcons.heart_24_regular,
      dimIcon = true,
      title = 'מקום זה יכול להיות מונצח לע"נ יקירך',
      titleFontSize = 13,
      description = null;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = dimIcon
        ? colorScheme.primary.withValues(alpha: 0.6)
        : colorScheme.primary;
    return _SurfaceCard(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: titleFontSize,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            if (description != null) ...[
              const SizedBox(height: 4),
              Text(
                description!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (onDonate != null) ...[
              const SizedBox(height: 8),
              ActionButton.recommended(
                icon: FluentIcons.payment_24_regular,
                text: 'נדרים+',
                onPressed: onDonate!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
