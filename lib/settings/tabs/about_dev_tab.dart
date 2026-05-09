import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/settings/search/settings_anchor.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/settings_card.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/dialogs/ad_popup_dialog.dart';

/// טאב "חכמי לב" — אודות, קהילה, תורמים ומפתחים.
class AboutDevTab extends StatelessWidget {
  const AboutDevTab({super.key});

  /// פריטי חיפוש בהגדרות. נסרק על-ידי tool/generate_search_index.dart.
  static const List<SettingsSearchEntry> searchEntries = [
    SettingsSearchEntry(
      id: 'about.team',
      title: 'אודות הצוות',
      subtitle: 'מידע על מפתחי אוצריא',
      tab: SettingsTab.about,
      cardId: 'about.main',
      keywords: ['אודות', 'מפתחים', 'צוות'],
    ),
  ];

  static const _developers = <Map<String, String>>[
    {'name': 'sivan22', 'url': 'https://github.com/Sivan22'},
    {
      'name': 'ר. נבון',
      'url': 'https://github.com/rachelGrayover',
      'description': 'השקעה עצומה במעבר ל-SQLite',
    },
    {'name': 'Y.PL.', 'url': 'https://github.com/Y-PLONI'},
    {'name': 'YOSEFTT', 'url': 'https://github.com/YOSEFTT'},
    {'name': 'zevisvei', 'url': 'https://github.com/zevisvei'},
    {'name': 'evel-avalim', 'url': 'https://github.com/evel-avalim'},
    {'name': 'userbot', 'url': 'https://github.com/userbot000'},
    {'name': 'mosh-dvd', 'url': 'https://github.com/mosh-dvd'},
    {
      'name': 'NHLOCAL',
      'url': 'https://github.com/NHLOCAL/Shamor-Zachor',
      'description': "מפתח 'שמור וזכור'",
    },
  ];

  static const _essentialPeople = <Map<String, String>>[
    {'name': 'דוד אריאל', 'url': ''},
    {'name': 'יעקב מ. פינס', 'url': 'https://github.com/ymp112'},
    {'name': 'רפאל א.', 'url': ''},
  ];

  static const _topEditors = <Map<String, String>>[
    {
      'name': 'י. פל',
      'url': 'https://forum.otzaria.org/user/%D7%99.-%D7%A4%D7%9C.',
    },
    {
      'name': 'האדם החושב', // האדם החושב
      'url':
          'https://forum.otzaria.org/user/%D7%94%D7%90%D7%93%D7%9D-%D7%94%D7%97%D7%95%D7%A9%D7%91',
    },
    {
      'name': 'י. ח. מ.', // יום חדש מתחיל
      'url':
          'https://forum.otzaria.org/user/%D7%99%D7%95%D7%9D-%D7%97%D%93%D7%A9-%D7%9E%D7%AA%D7%97%D7%99%D7%9C',
    },
    {
      'name': 'ס. כב.', // sivan22
      'url': 'https://mitmachim.top/user/sivan22'
    },
    {
      'name': 'י. צ.', // יהודי צעיר
      'url':
          'https://forum.otzaria.org/user/%D7%99%D7%94%D7%95%D7%93%D7%99-%D7%A6%D7%A2%D7%99%D7%A8',
    },
    // {
    //   'name': 'דורש טוב',  // כרגע לא רוצה
    //   'url':
    //       'https://forum.otzaria.org/user/%D7%93%D7%95%D7%A8%D7%A9-%D7%98%D7%95%D7%91',
    // },
    // {
    //   'name': 'מ. פינק', // כרגע לא רוצה
    // },
    // {
    //   'name': 'זקצ',
    // },
    {
      'name': 'קטנטן', // ד. בנדל
      'url': 'https://forum.otzaria.org/user/%D7%A7%D7%98%D7%A0%D7%98%D7%9F',
    },
    {
      'name': 'ד.', // דאנציג
      'url':
          'https://forum.otzaria.org/user/%D7%93%D7%90%D7%A0%D7%A6%D7%99%D7%92',
    },
    {
      'name': 'י. א.', // ישי אשכנזי
    },
    {
      'name': '333',
      'url': 'https://forum.otzaria.org/user/333',
    },
    {
      'name': "ט. ג.", // "טכנולוגי גו'ניור", // י. אייזנשטיין
      'url':
          'https://forum.otzaria.org/user/%D7%98%D7%9B%D7%A0%D7%95%D7%9C%D7%95%D7%92%D7%99-%D7%92%D7%95-%D7%A0%D7%99%D7%95%D7%A8',
    },
    {
      'name': 'ה. ה.', // גאון גדול - הבל הבלים
      'url':
          'https://forum.otzaria.org/user/%D7%94%D7%91%D7%9C-%D7%94%D7%91%D7%9C%D7%99%D7%9D',
    },
    {
      'name': 'י. א. ח.', // U88
      'url': 'https://otzaria.org/forum/user/u88',
    },
  ];

  // מהדירים שההדירו בין 5 ל-10 ספרים
  static const _regularEditors = <Map<String, String>>[
    {
      'name': 'מויטיו',
      'url': 'https://mitmachim.top/user/%D7%9E%D7%95%D7%99%D7%98%D7%99%D7%95',
    },
    {
      'name': 'ד. מ. א.', // דוד משה 1
      'url':
          'https://forum.otzaria.org/user/%D7%93%D7%95%D7%93-%D7%9E%D7%A9%D7%94-1',
    },
    {
      'name': 'א. צ. מ.', // איש צדיק מידי
      'url':
          'https://forum.otzaria.org/user/%D7%90%D7%99%D7%A9-%D7%A6%D7%93%D7%99%D7%A7-%D7%9E%D7%99%D7%93%D7%99',
    },
    {
      'name': 'שני אנשים',
      'url':
          'https://forum.otzaria.org/user/%D7%A9%D7%A0%D7%99-%D7%90%D7%A0%D7%A9%D7%99%D7%9D',
    },
    {
      'name': 'י. ד.', // יאיר דניאל
      'url':
          'https://forum.otzaria.org/user/%D7%99%D7%90%D7%99%D7%A8-%D7%93%D7%A0%D7%99%D7%90%D7%9C',
    },
    {
      'name': 'ש. נ.', // שילה נוי
    },
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
            SettingsAnchor(
              cardId: 'about.main',
              child: _buildHeader(context),
            ),

            // ── תרומה ומידע ──
            SettingsCard(
              title: 'תרומה ומידע',
              children: [
                _ActionTile(
                  icon: FluentIcons.payment_24_regular,
                  title: 'תרום לפרויקט',
                  subtitle:
                      'תרומתך תעזור לנו להמשיך לפתח ולשפר את אוצריא עבור כלל הציבור.',
                  buttonLabel: 'נדרים+',
                  buttonIcon: FluentIcons.payment_24_regular,
                  onTap: () => _openUrl('https://nedar.im/ezOd'),
                ),
                _ActionTile(
                  icon: FluentIcons.shield_task_24_filled,
                  title: 'אוצריא מתגייסת לעזרת לומדי התורה',
                  subtitle: 'מרכז המידע על ארגוני סיוע ללומדי התורה',
                  buttonLabel: 'למידע נוסף',
                  onTap: () => _openAdPopup(context),
                ),
              ],
            ),

            // ── הצטרף ──
            SettingsCard(
              title: 'הצטרף',
              children: [
                _ActionTile(
                  icon: FluentIcons.edit_24_regular,
                  title: 'הצטרף לצוות העריכה',
                  subtitle: 'עזור לנו להוסיף ספרים חדשים לספריית אוצריא',
                  buttonLabel: 'הצטרף לעריכה',
                  onTap: () => _openUrl('https://www.otzaria.org/library'),
                ),
                _ActionTile(
                  icon: FluentIcons.code_24_regular,
                  title: 'הצטרף לפיתוח',
                  subtitle: 'מפתחים מוזמנים לתרום לקהילה התורנית',
                  buttonLabel: 'הצטרף עכשיו',
                  onTap: () => _openUrl('https://github.com/otzaria/otzaria'),
                ),
              ],
            ),

            // ── תורמים ──
            SettingsCard(
              title: 'תורמים',
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _MemorialCardsGrid(
                    onDonationTap: () => _openUrl('https://nedar.im/ezOd'),
                  ),
                ),
              ],
            ),

            // ── מפתחים ──
            SettingsCard(
              title: 'מפתחים',
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _ContributorWrap(
                    contributors: _developers,
                    icon: FluentIcons.person_24_regular,
                  ),
                ),
              ],
            ),

            // ── אנשים חיוניים ──
            SettingsCard(
              title: 'התוכנה נעזרה רבות ב:',
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _ContributorWrap(
                    contributors: _essentialPeople,
                    icon: FluentIcons.people_24_regular,
                  ),
                ),
              ],
            ),

            // ── מהדירי ספרים ──
            SettingsCard(
              title: 'מהדירי ספרים',
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _editorCategory('10 ספרים ומעלה', _topEditors),
                      const SizedBox(height: 20),
                      _editorCategory('בין 5 ל-10 ספרים', _regularEditors),
                      const SizedBox(height: 12),
                      _editorsNote(context),
                    ],
                  ),
                ),
              ],
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
            errorBuilder: (_, __, ___) =>
                const Icon(FluentIcons.library_24_regular, size: 60),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'אוצריא',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
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

  Widget _editorCategory(String label, List<Map<String, String>> editors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('מהדירים שההדירו $label', style: kSettingsSubtitleStyle),
        const SizedBox(height: 8),
        _ContributorWrap(
          contributors: editors,
          icon: FluentIcons.book_24_regular,
        ),
      ],
    );
  }

  Widget _editorsNote(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppTokens.radiusSM),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(FluentIcons.info_24_regular,
              size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'באם שמכם אינו מופיע ברשימה או שאתם מעוניינים בשינוי, '
              'אנא פנו למייל המערכת.',
              style: kSettingsSubtitleStyle,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

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

// ── _ContributorWrap ──────────────────────────────────────────────────────────

class _ContributorWrap extends StatelessWidget {
  final List<Map<String, String>> contributors;
  final IconData icon;

  const _ContributorWrap({required this.contributors, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 10,
      children: contributors
          .map((c) => _ContributorChip(
                name: c['name']!,
                url: c['url'] ?? '',
                description: c['description'],
                icon: icon,
              ))
          .toList(),
    );
  }
}

class _ContributorChip extends StatelessWidget {
  final String name;
  final String url;
  final String? description;
  final IconData icon;

  const _ContributorChip({
    required this.name,
    required this.url,
    this.description,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasUrl = url.isNotEmpty;
    final nameStyle = hasUrl
        ? kSettingsTitleStyle.copyWith(color: colorScheme.primary)
        : kSettingsTitleStyle;

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(name, style: nameStyle),
        if (description != null && description!.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text('(${description!})', style: kSettingsSubtitleStyle),
        ],
      ],
    );

    if (hasUrl) {
      return InkWell(
        onTap: () async {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) await launchUrl(uri);
        },
        borderRadius: BorderRadius.circular(4),
        child: content,
      );
    }
    return content;
  }
}

// ── _MemorialCardsGrid ────────────────────────────────────────────────────────

class _MemorialCardsGrid extends StatelessWidget {
  final VoidCallback onDonationTap;
  const _MemorialCardsGrid({required this.onDonationTap});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 400) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MemorialCard(
              name: "לע\"נ ר' משה בן יהודה ראה ז\"ל",
              description: 'סכום משמעותי לפיתוח התוכנה',
            ),
            const SizedBox(height: 12),
            _DonationMemorialCard(onTap: onDonationTap),
            const SizedBox(height: 12),
            _DonationMemorialCard(onTap: onDonationTap),
          ],
        );
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _MemorialCard(
                name: "לע\"נ ר' משה בן יהודה ראה ז\"ל",
                description: 'סכום משמעותי לפיתוח התוכנה',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _DonationMemorialCard(onTap: onDonationTap)),
            const SizedBox(width: 12),
            Expanded(child: _DonationMemorialCard(onTap: onDonationTap)),
          ],
        ),
      );
    });
  }
}

class _MemorialCard extends StatelessWidget {
  final String name;
  final String description;
  const _MemorialCard({required this.name, required this.description});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(FluentIcons.heart_24_filled,
                color: colorScheme.primary, size: 24),
            const SizedBox(height: 6),
            Text(name,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface)),
            const SizedBox(height: 4),
            Text(description,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                    fontSize: 11, color: colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _DonationMemorialCard extends StatelessWidget {
  final VoidCallback onTap;
  const _DonationMemorialCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(FluentIcons.heart_24_regular,
                color: colorScheme.primary.withValues(alpha: 0.6), size: 24),
            const SizedBox(height: 6),
            Text(
              'מקום זה יכול להיות מונצח לע"נ יקירך',
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface),
            ),
            const SizedBox(height: 8),
            RecommendedActionButton(
              icon: FluentIcons.payment_24_regular,
              text: 'נדרים+',
              onPressed: onTap,
            ),
          ],
        ),
      ),
    );
  }
}

// ── _ActionTile ───────────────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final IconData? buttonIcon;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    this.buttonIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      hoverColor: Colors.transparent,
      leading: Icon(icon),
      title: Text(title, style: kSettingsTitleStyle),
      subtitle: Text(subtitle, style: kSettingsSubtitleStyle),
      trailing: RecommendedActionButton(
        text: buttonLabel,
        icon: buttonIcon,
        onPressed: onTap,
      ),
    );
  }
}
