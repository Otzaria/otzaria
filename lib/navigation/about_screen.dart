import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import '../services/data_collection_service.dart';
import '../widgets/ad_popup_dialog.dart';
import 'dart:io';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String? appVersion;
  String? libraryVersion;
  int? bookCount;

  @override
  void initState() {
    super.initState();
    _loadVersions();
  }

  Widget _buildContributor(String name, String url) {
    final hasUrl = url.isNotEmpty;

    if (!hasUrl) {
      return Text(
        name,
        style: TextStyle(
          color: Colors.grey[700],
        ),
      );
    }

    return InkWell(
      onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
      },
      child: Text(
        name,
        style: const TextStyle(
          color: Colors.blue,
        ),
      ),
    );
  }

  Widget _buildDevelopersList() {
    final developers = [
      {'name': 'sivan22', 'url': 'https://github.com/Sivan22'},
      {'name': 'Y.PL.', 'url': 'https://github.com/Y-PLONI'},
      {'name': 'YOSEFTT', 'url': 'https://github.com/YOSEFTT'},
      {'name': 'zevisvei', 'url': 'https://github.com/zevisvei'},
      {'name': 'evel-avalim', 'url': 'https://github.com/evel-avalim'},
      {'name': 'userbot', 'url': 'https://github.com/userbot000'},
      {
        'name': 'mosh-dvd',
        'url': 'https://github.com/mosh-dvd',
        'description': 'ממפתחי ממשק צורת הדף'
      },
      {
        'name': 'NHLOCAL',
        'url': 'https://github.com/NHLOCAL/Shamor-Zachor',
        'description': "מפתח 'זכור ושמור'"
      },
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // במסכים קטנים, הצג בעמודה
        if (constraints.maxWidth < 500) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: developers
                .map((dev) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          const Icon(FluentIcons.person_24_regular,
                              size: 16, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildContributor(dev['name']!, dev['url']!),
                                if (dev['description'] != null)
                                  Text(
                                    '(${dev['description']})',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          );
        }
        // במסכים רחבים, השתמש ב-Wrap
        return Wrap(
          spacing: 40,
          runSpacing: 12,
          children: developers
              .map((dev) => SizedBox(
                    width: 220,
                    child: Row(
                      children: [
                        const Icon(FluentIcons.person_24_regular,
                            size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildContributor(dev['name']!, dev['url']!),
                              if (dev['description'] != null)
                                Text(
                                  '(${dev['description']})',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _buildBookEditorsList() {
    // מהדירים שההדירו 10 ספרים ומעלה
    final topEditors = [
      {
        'name': 'י. פל',
        'url': 'https://mitmachim.top/user/%D7%99.-%D7%A4%D7%9C',
      },
      {
        'name': 'sivan22',
        'url': 'https://mitmachim.top/user/sivan22',
      },
      {
        'name': 'יהודי צעיר',
        'url':
            'https://mitmachim.top/user/%D7%99%D7%94%D7%95%D7%93%D7%99-%D7%A6%D7%A2%D7%99%D7%A8',
      },
      // {
      //   'name': 'דורש טוב',
      //   'url':
      //       'https://mitmachim.top/user/%D7%93%D7%95%D7%A8%D7%A9-%D7%98%D7%95%D7%91',
      // },
      // {
      //   'name': 'מ. פינק', כרגע לא רוצה
      // },
      // {
      //   'name': 'זקצ',
      // },
      {
        'name': 'קטנטן', // ד. בנדל
        'url': 'https://mitmachim.top/user/%D7%A7%D7%98%D7%A0%D7%98%D7%9F',
      },
      {
        'name': 'דאנציג',
        'url':
            'https://mitmachim.top/user/%D7%93%D7%90%D7%A0%D7%A6%D7%99%D7%92',
      },
      // {
      //   'name': 'י. אשכנזי', כרגע לא רוצה
      // },
      {
        'name': '333',
        'url': 'https://mitmachim.top/user/333',
      },
      {
        'name': "טכנולוגי גו'ניור", // י. אייזנשטיין
        'url':
            'https://mitmachim.top/user/%D7%98%D7%9B%D7%A0%D7%95%D7%9C%D7%95%D7%92%D7%99-%D7%92%D7%95-%D7%A0%D7%99%D7%95%D7%A8',
      },
      {
        'name': 'הבל הבלים', // גאון גדול
        'url':
            'https://mitmachim.top/user/%D7%94%D7%91%D7%9C-%D7%94%D7%91%D7%9C%D7%99%D7%9D',
      },
    ];

    // מהדירים שההדירו בין 5 ל-10 ספרים
    final regularEditors = [
      {
        'name': 'מוטיו',
      },
      {
        'name': 'דוד משה 1',
        'url':
            'https://mitmachim.top/user/%D7%93%D7%95%D7%93-%D7%9E%D7%A9%D7%94-1',
      },
      {
        'name': 'איש צדיק מידי',
        'url':
            'https://mitmachim.top/user/%D7%90%D7%99%D7%A9-%D7%A6%D7%93%D7%99%D7%A7-%D7%9E%D7%99%D7%93%D7%99',
      },
      {
        'name': 'שני אנשים',
        'url':
            'https://mitmachim.top/user/%D7%A9%D7%A0%D7%99-%D7%90%D7%A0%D7%A9%D7%99%D7%9D',
      },
      {
        'name': 'יאיר דניאל',
        'url':
            'https://mitmachim.top/user/%D7%99%D7%90%D7%99%D7%A8-%D7%93%D7%A0%D7%99%D7%90%D7%9C',
      },
    ];

    Widget buildEditorsList(List<Map<String, String>> editors) {
      return LayoutBuilder(
        builder: (context, constraints) {
          // במסכים קטנים, הצג בעמודה
          if (constraints.maxWidth < 500) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: editors
                  .map((editor) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            const Icon(FluentIcons.book_24_regular,
                                size: 16, color: Colors.grey),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildContributor(
                                  editor['name']!, editor['url'] ?? ''),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            );
          }
          // במסכים רחבים, השתמש ב-Wrap
          return Wrap(
            spacing: 40,
            runSpacing: 12,
            children: editors
                .map((editor) => SizedBox(
                      width: 220,
                      child: Row(
                        children: [
                          const Icon(FluentIcons.book_24_regular,
                              size: 16, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildContributor(
                                editor['name']!, editor['url'] ?? ''),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // קטגוריה ראשונה: 10 ספרים ומעלה
        Text(
          'מהדירים שההדירו 10 ספרים ומעלה',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 12),
        buildEditorsList(topEditors),
        const SizedBox(height: 24),

        // קטגוריה שנייה: 5-10 ספרים
        Text(
          'מהדירים שההדירו בין 5 ל-10 ספרים',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 12),
        buildEditorsList(regularEditors),
        const SizedBox(height: 16),

        // הודעה בסוף הרשימה
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(FluentIcons.info_24_regular,
                  size: 18, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'באם גם אתם ערכתם ספרים ושמכם אינו מופיע ברשימה, וכן אם אתם מעוניינים בשינוי כלשהו,\nאנא פנו למייל המערכת',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTechnicalDetails() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // במסכים קטנים, הצג בעמודה
        if (constraints.maxWidth < 500) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCompactInfoItem('גרסת תוכנה', appVersion ?? 'לא ידוע'),
              const SizedBox(height: 8),
              _buildCompactInfoItem('גרסת ספרייה', libraryVersion ?? 'לא ידוע'),
              const SizedBox(height: 8),
              _buildCompactInfoItem('מספר ספרים', '${bookCount ?? 'לא ידוע'}'),
            ],
          );
        }
        // במסכים רחבים, השתמש ב-Wrap
        return Wrap(
          spacing: 30,
          runSpacing: 8,
          children: [
            _buildCompactInfoItem('גרסת תוכנה', appVersion ?? 'לא ידוע'),
            _buildCompactInfoItem('גרסת ספרייה', libraryVersion ?? 'לא ידוע'),
            _buildCompactInfoItem('מספר ספרים', '${bookCount ?? 'לא ידוע'}'),
          ],
        );
      },
    );
  }

  Widget _buildCompactInfoItem(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildMemorialCardsRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // אם הרוחב קטן מ-700, הצג בעמודה
        if (constraints.maxWidth < 700) {
          return _buildMemorialCardsColumn();
        }
        // אחרת, הצג בשורה
        return Row(
          children: [
            Expanded(
              child: _buildMemorialCard(
                'לע"נ ר\' משה בן יהודה ראה ז"ל',
                'סכום משמעותי לפיתוח התוכנה',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDonationMemorialCard(
                'מקום זה יכול להיות מונצח לע"נ יקירך',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDonationMemorialCard(
                'מקום זה יכול להיות מונצח לע"נ יקירך',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionCard({
    required String title,
    required String description,
    required String buttonText,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool showGitHubIcon = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
              ),
              icon: Icon(icon, size: 18),
              label: Text(buttonText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemorialCard(String name, String description) {
    return SizedBox(
      height: 140, // גודל קבוע לכל הכארדים
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.asset(
                    'assets/icon/memorial_candle.svg',
                    width: 20,
                    height: 20,
                    colorFilter: ColorFilter.mode(
                      Colors.orange[700]!,
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDonationMemorialCard(String name) {
    return SizedBox(
      height: 140, // גודל קבוע לכל הכארדים
      child: Card(
        elevation: 2,
        child: InkWell(
          onTap: () => _openLocalHtmlFile('donate.html'),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgPicture.asset(
                      'assets/icon/memorial_candle.svg',
                      width: 20,
                      height: 20,
                      colorFilter: ColorFilter.mode(
                        Colors.orange[700]!,
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'לחץ כאן',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadVersions() async {
    // Load app version
    final packageInfo = await PackageInfo.fromPlatform();
    appVersion = packageInfo.version;

    // Load library version from file
    await _loadLibraryVersion();

    setState(() {});
  }

  Future<void> _loadLibraryVersion() async {
    final dataService = DataCollectionService();
    libraryVersion = await dataService.readLibraryVersion();
    if (libraryVersion == 'unknown') {
      libraryVersion = 'לא ידוע';
    }

    // Load book count
    bookCount = await dataService.getTotalBookCount();
  }

  Future<String?> _getOtzariaSitePath() async {
    final libraryPath = Settings.getValue('key-library-path');
    if (libraryPath == null || libraryPath.isEmpty) return null;

    // התיקייה otzaria-site נמצאת באותה תיקייה שבה נמצא "גירסת ספריה.txt"
    final otzariaSitePath = Directory(
        '$libraryPath${Platform.pathSeparator}אוצריא${Platform.pathSeparator}אודות התוכנה${Platform.pathSeparator}otzaria-site');
    if (await otzariaSitePath.exists()) {
      return otzariaSitePath.path;
    }
    return null;
  }

  Future<void> _openLocalHtmlFile(String fileName) async {
    final sitePath = await _getOtzariaSitePath();
    if (sitePath == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('לא נמצאה תיקיית otzaria-site')),
      );
      return;
    }

    final htmlFile = File('$sitePath/$fileName');
    if (!await htmlFile.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('הקובץ $fileName לא נמצא')),
      );
      return;
    }

    final uri = Uri.file(htmlFile.path);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _showChangelogDialog(BuildContext context) async {
    final changelog = await rootBundle.loadString('assets/יומן שינויים.md');

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('יומן שינויים'),
          content: SizedBox(
            width: 600,
            height: 400,
            child: Markdown(
              data: changelog,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('סגור'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupportCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(FluentIcons.shield_task_24_filled,
                  color: Colors.blue, size: 24),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'אוצריא מתגייסת לעזרת לומדי התורה',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'קווי חירום וארגוני סיוע ללומדי תורה',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  barrierDismissible: true,
                  builder: (context) => const AdPopupDialog(
                    title: 'אוצריא מתגייסת לעזרת לומדי התורה',
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(FluentIcons.shield_task_24_filled, size: 18),
              label: const Text('לחץ לפרטים'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDonationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[600]!.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[600]!.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.volunteer_activism_outlined,
                  color: Colors.grey[600]!, size: 24),
              const SizedBox(width: 8),
              Text(
                'תרום לפרויקט',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600]!,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'תרומתך תעזור לנו להמשיך לפתח ולשפר את אוצריא עבור כלל הציבור.',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          // שורה עם שני כפתורים אחד לצד השני
          LayoutBuilder(
            builder: (context, constraints) {
              // במסכים קטנים מאוד, הצג בעמודה
              if (constraints.maxWidth < 300) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () async {
                        const url = 'https://nedar.im/ejco';
                        final uri = Uri.parse(url);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: Image.asset(
                        'assets/icon/logo_nedarim.png',
                        width: 18,
                        height: 18,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(FluentIcons.payment_24_regular,
                                size: 18),
                      ),
                      label:
                          const Text('נדרים+', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () => _openLocalHtmlFile('donate.html'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon:
                          const Icon(FluentIcons.payment_24_regular, size: 18),
                      label: const Text('אחר', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                );
              }
              // במסכים רגילים, הצג בשורה
              return Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        const url = 'https://nedar.im/ejco';
                        final uri = Uri.parse(url);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: Image.asset(
                        'assets/icon/logo_nedarim.png',
                        width: 18,
                        height: 18,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(FluentIcons.payment_24_regular,
                                size: 18),
                      ),
                      label:
                          const Text('נדרים+', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _openLocalHtmlFile('donate.html'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon:
                          const Icon(FluentIcons.payment_24_regular, size: 18),
                      label: const Text('אחר', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 900;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: isSmallScreen
          ? _buildSmallScreenLayout(context)
          : _buildWideScreenLayout(context),
    );
  }

  Widget _buildWideScreenLayout(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // תוכן ראשי - מצד ימין
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // סמל וכותרת משנה
                Row(
                  children: [
                    Image.asset(
                      'assets/icon/icon.png',
                      width: 80,
                      height: 80,
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'אוצריא',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'מאגר תורני חינמי',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // תיאור התוכנה
                const Text(
                  'מאגר תורני רחב עם ממשק מודרני ומהיר, לשימוש במחשב אישי או במכשיר הנייד, ללימוד תורה בקלות ובנוחות בכל מקום.',
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),

                // כארדים תורמים
                const Text(
                  'תורמים',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildMemorialCardsRow(),
                const SizedBox(height: 32),

                // רשימת מפתחים
                const Text(
                  'מפתחים',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildDevelopersList(),
                const SizedBox(height: 32),

                // רשימת מהדירי ספרים
                const Text(
                  'מהדירי ספרים',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildBookEditorsList(),
                const SizedBox(height: 32),

                // פרטים טכניים
                const Text(
                  'פרטים טכניים',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildTechnicalDetails(),
                const SizedBox(height: 16),

                // כפתור יומן שינויים
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: () => _showChangelogDialog(context),
                    icon: const Icon(FluentIcons.history_24_regular),
                    label: const Text('יומן שינויים'),
                  ),
                ),
              ],
            ),
          ),
        ),

        // כארד צדדי - מצד שמאל
        SizedBox(
          width: 300,
          child: SingleChildScrollView(
            child: Card(
              margin: const EdgeInsets.all(16),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSupportCard(context),
                    const SizedBox(height: 20),
                    _buildActionCard(
                      title: 'אודות התוכנה',
                      description:
                          'מידע נוסף על התוכנה, תכונות, ומדריכים לשימוש.',
                      buttonText: 'אודות התוכנה',
                      icon: FluentIcons.info_24_regular,
                      color: Colors.grey[600]!,
                      onTap: () => _openLocalHtmlFile('index.html'),
                    ),
                    const SizedBox(height: 20),
                    _buildActionCard(
                      title: 'הצטרף לפיתוח!',
                      description:
                          'מפתחים מוזמנים להצטרף לפיתוח אוצריא ולתרום לקהילה התורנית.',
                      buttonText: 'הצטרף עכשיו',
                      icon: FluentIcons.code_24_regular,
                      color: Colors.grey[600]!,
                      showGitHubIcon: true,
                      onTap: () =>
                          _openLocalHtmlFile('tutorial-development.html'),
                    ),
                    const SizedBox(height: 20),
                    _buildActionCard(
                      title: 'הצטרף לצוות העריכה',
                      description:
                          'עזור לנו להוסיף ספרים חדשים לספריית אוצריא ולהרחיב את המאגר התורני.',
                      buttonText: 'הצטרף לעריכה',
                      icon: FluentIcons.edit_24_regular,
                      color: Colors.grey[600]!,
                      onTap: () => _openLocalHtmlFile('tutorial-dicta.html'),
                    ),
                    const SizedBox(height: 20),
                    _buildDonationCard(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSmallScreenLayout(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // כרטיס אוצריא מתגייסת
          _buildSupportCard(context),
          const SizedBox(height: 24),
          // סמל וכותרת
          _buildHeader(),
          const SizedBox(height: 16),

          // תיאור
          const Text(
            'מאגר תורני רחב עם ממשק מודרני ומהיר, לשימוד תורה בקלות ובנוחות בכל מקום.',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),

          // כארדים של פעולות (למעלה במסכים קטנים)
          _buildActionCard(
            title: 'אודות התוכנה',
            description: 'מידע נוסף על התוכנה, תכונות, ומדריכים לשימוש.',
            buttonText: 'אודות התוכנה',
            icon: FluentIcons.info_24_regular,
            color: Colors.grey[600]!,
            onTap: () => _openLocalHtmlFile('index.html'),
          ),
          const SizedBox(height: 16),
          _buildActionCard(
            title: 'הצטרף לפיתוח!',
            description:
                'מפתחים מוזמנים להצטרף לפיתוח אוצריא ולתרום לקהילה התורנית.',
            buttonText: 'הצטרף עכשיו',
            icon: FluentIcons.code_24_regular,
            color: Colors.grey[600]!,
            showGitHubIcon: true,
            onTap: () => _openLocalHtmlFile('tutorial-development.html'),
          ),
          const SizedBox(height: 16),
          _buildActionCard(
            title: 'הצטרף לצוות העריכה',
            description:
                'עזור לנו להוסיף ספרים חדשים לספריית אוצריא ולהרחיב את המאגר התורני.',
            buttonText: 'הצטרף לעריכה',
            icon: FluentIcons.edit_24_regular,
            color: Colors.grey[600]!,
            onTap: () => _openLocalHtmlFile('tutorial-dicta.html'),
          ),
          const SizedBox(height: 16),
          _buildDonationCard(),
          const SizedBox(height: 24),

          // תורמים
          const Text(
            'תורמים',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildMemorialCardsColumn(),
          const SizedBox(height: 24),

          // מפתחים
          const Text(
            'מפתחים',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildDevelopersList(),
          const SizedBox(height: 24),

          // מהדירי ספרים
          const Text(
            'מהדירי ספרים',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildBookEditorsList(),
          const SizedBox(height: 24),

          // פרטים טכניים
          const Text(
            'פרטים טכניים',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildTechnicalDetails(),
          const SizedBox(height: 16),

          // כפתור יומן שינויים
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showChangelogDialog(context),
              icon: const Icon(FluentIcons.history_24_regular),
              label: const Text('יומן שינויים'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isVerySmall = constraints.maxWidth < 400;
        return Row(
          children: [
            Image.asset(
              'assets/icon/icon.png',
              width: isVerySmall ? 50 : 60,
              height: isVerySmall ? 50 : 60,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'אוצריא',
                    style: TextStyle(
                      fontSize: isVerySmall ? 20 : 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'מאגר תורני חינמי',
                    style: TextStyle(
                      fontSize: isVerySmall ? 12 : 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMemorialCardsColumn() {
    return Column(
      children: [
        _buildMemorialCard(
          'לע"נ ר\' משה בן יהודה ראה ז"ל',
          'סכום משמעותי לפיתוח התוכנה',
        ),
        const SizedBox(height: 12),
        _buildDonationMemorialCard(
          'מקום זה יכול להיות מונצח לע"נ יקירך',
        ),
        const SizedBox(height: 12),
        _buildDonationMemorialCard(
          'מקום זה יכול להיות מונצח לע"נ יקירך',
        ),
      ],
    );
  }
}
