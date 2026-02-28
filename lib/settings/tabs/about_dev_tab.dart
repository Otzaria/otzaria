import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:otzaria/widgets/custom_ui_components.dart';

/// טאב "חכמי לב" — אודות, קהילה, תורמים ומפתחים.
class AboutDevTab extends StatelessWidget {
  const AboutDevTab({super.key});

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
      'name': 'האדם החושב',
      'url':
          'https://forum.otzaria.org/user/%D7%94%D7%90%D7%93%D7%9D-%D7%94%D7%97%D7%95%D7%A9%D7%91',
    },
    {'name': 'ס. כב.', 'url': 'https://mitmachim.top/user/sivan22'},
    {
      'name': 'י. צ.',
      'url':
          'https://forum.otzaria.org/user/%D7%99%D7%94%D7%95%D7%93%D7%99-%D7%A6%D7%A2%D7%99%D7%A8',
    },
    {
      'name': 'קטנטן',
      'url': 'https://forum.otzaria.org/user/%D7%A7%D7%98%D7%A0%D7%98%D7%9F',
    },
    {'name': '333', 'url': 'https://forum.otzaria.org/user/333'},
  ];

  static const _regularEditors = <Map<String, String>>[
    {
      'name': 'מויטיו',
      'url': 'https://mitmachim.top/user/%D7%9E%D7%95%D7%99%D7%98%D7%99%D7%95',
    },
    {'name': 'ד. מ. א.', 'url': ''},
    {'name': 'א. צ. מ.', 'url': ''},
    {'name': 'ש. נ.', 'url': ''},
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      children: [
        _buildHeader(context),
        const SizedBox(height: 20),

        // ── תרומה ──
        _SectionCard(
          title: 'תרום לפרויקט',
          children: [_buildDonationContent(context)],
        ),
        const SizedBox(height: 16),

        // ── הצטרף ──
        _SectionCard(
          title: 'הצטרף',
          children: [
            _ActionTile(
              icon: FluentIcons.edit_24_regular,
              title: 'הצטרף לצוות העריכה',
              subtitle: 'עזור לנו להוסיף ספרים חדשים לספריית אוצריא',
              buttonLabel: 'הצטרף לעריכה',
              onTap: () => _openUrl('https://forum.otzaria.org'),
            ),
            const Divider(height: 1),
            _ActionTile(
              icon: FluentIcons.code_24_regular,
              title: 'הצטרף לפיתוח',
              subtitle: 'מפתחים מוזמנים לתרום לקהילה התורנית',
              buttonLabel: 'הצטרף עכשיו',
              onTap: () =>
                  _openUrl('https://github.com/Sivan22/otzaria'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── מפתחים ──
        _SectionCard(
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
        const SizedBox(height: 16),

        // ── אנשים חיוניים ── (שם חדש)
        _SectionCard(
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
        const SizedBox(height: 16),

        // ── מהדירי ספרים ──
        _SectionCard(
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
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
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
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDonationContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'תרומתך תעזור לנו להמשיך לפתח ולשפר את אוצריא עבור כלל הציבור.',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          // כפתור נדרים+ בלבד (הוסר 'אחר')
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _openUrl('https://nedar.im/ejco'),
              icon: const Icon(FluentIcons.payment_24_regular, size: 18),
              label: const Text('נדרים+'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editorCategory(
      String label, List<Map<String, String>> editors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'מהדירים שההדירו $label',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        _ContributorWrap(
          contributors: editors,
          icon: FluentIcons.book_24_regular,
        ),
      ],
    );
  }

  Widget _editorsNote(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(FluentIcons.info_24_regular, size: 18, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'באם שמכם אינו מופיע ברשימה או שאתם מעוניינים בשינוי, '
              'אנא פנו למייל המערכת.',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
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
    final hasUrl = url.isNotEmpty;
    final nameStyle = hasUrl
        ? const TextStyle(color: Colors.blue, fontSize: 14)
        : TextStyle(color: Colors.grey[700], fontSize: 14);

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: Colors.grey[500]),
        const SizedBox(width: 6),
        Text(name, style: nameStyle),
        if (description != null && description!.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text('(${description!})',
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
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

// ── _ActionTile ───────────────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontSize: 16)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 13)),
      trailing: RecommendedActionButton(
        text: buttonLabel,
        onPressed: onTap,
      ),
    );
  }
}

// ── _SectionCard ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
              const EdgeInsets.only(right: 4, left: 4, bottom: 8, top: 4),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
              letterSpacing: 0.3,
            ),
          ),
        ),
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}

// ── _MemorialCard (used in advanced_settings_tab — reexported here) ────────────

/// כרטיס תרומה לזיכרון — עם כפתור נדרים+ במקום טקסט קישור
class MemorialDonationCard extends StatelessWidget {
  final VoidCallback onTap;

  const MemorialDonationCard({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_fire_department,
                color: Colors.orange[300], size: 20),
            const SizedBox(height: 6),
            const Text(
              'מקום זה יכול להיות מונצח לע"נ יקירך',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // כפתור במקום הטקסט "לחץ כאן לפרטים"
            FilledButton.tonal(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 28),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(FluentIcons.payment_24_regular, size: 13),
                  SizedBox(width: 4),
                  Text('נדרים+', style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
