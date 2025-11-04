import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/data_collection_service.dart';

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
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  Widget _buildDevelopersList() {
    final developers = [
      {
        'name': 'sivan22',
        'url': 'https://github.com/Sivan22',
        'description': 'יוצר התוכנה'
      },
      {'name': 'Y.PL.', 'url': 'https://github.com/Y-PLONI'},
      {'name': 'YOSEFTT', 'url': 'https://github.com/YOSEFTT'},
      {'name': 'zevisvei', 'url': 'https://github.com/zevisvei'},
      {
        'name': 'NHLOCAL',
        'url': 'https://github.com/NHLOCAL/Shamor-Zachor',
        'description': 'פיתוח "זכור ושמור"'
      },
      {
        'name': 'evel-avalim',
        'url': 'https://github.com/evel-avalim',
        'description': 'פיתוח הגימטריות'
      },
      {
        'name': 'userbot',
        'url': 'https://github.com/userbot000',
      },
    ];

    return Wrap(
      spacing: 40,
      runSpacing: 8,
      children: developers
          .map((dev) => SizedBox(
                width: 250,
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

  Widget _buildTechnicalDetails() {
    return Wrap(
      spacing: 30,
      runSpacing: 8,
      children: [
        _buildCompactInfoItem('גרסת תוכנה', appVersion ?? 'לא ידוע'),
        _buildCompactInfoItem('גרסת ספרייה', libraryVersion ?? 'לא ידוע'),
        _buildCompactInfoItem('מספר ספרים', '${bookCount ?? 'לא ידוע'}'),
      ],
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
          onTap: () async {
            const url = 'https://forms.gle/Dq8bn7mw7he4wtTC9';
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
            }
          },
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

  Widget _buildDonationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FluentIcons.heart_24_regular,
                  color: Theme.of(context).primaryColor, size: 24),
              const SizedBox(width: 8),
              Text(
                'תרום לפרויקט',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
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
          Row(
            children: [
              // כפתור נדרים פלוס
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
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: Image.asset(
                    'assets/icon/logo_nedarim.png',
                    width: 18,
                    height: 18,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(FluentIcons.payment_24_regular, size: 18),
                  ),
                  label: const Text('נדרים+', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              // כפתור תרומה רגילה
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    const url = 'https://forms.gle/Dq8bn7mw7he4wtTC9';
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
                  icon: const Icon(FluentIcons.payment_24_regular, size: 18),
                  label: const Text('אחר', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
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
          LayoutBuilder(
            builder: (context, constraints) {
              final screenWidth = MediaQuery.of(context).size.width;

              final isSmallScreen = screenWidth < 800;

              return SizedBox(
                width: isSmallScreen ? screenWidth * 0.9 : 300,
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
                          // כארד הצטרפות למפתחים
                          _buildActionCard(
                            title: 'הצטרף לפיתוח!',
                            description:
                                'מפתחים מוזמנים להצטרף לפיתוח אוצריא ולתרום לקהילה התורנית.',
                            buttonText: 'הצטרף עכשיו',
                            icon: FluentIcons.code_24_regular,
                            color: Colors.grey[600]!,
                            showGitHubIcon: true,
                            onTap: () async {
                              const url = 'https://github.com/Sivan22/otzaria';
                              final uri = Uri.parse(url);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri);
                              }
                            },
                          ),

                          const SizedBox(height: 20),

                          // כארד הצטרפות לצוות העריכה
                          _buildActionCard(
                            title: 'הצטרף לצוות העריכה',
                            description:
                                'עזור לנו להוסיף ספרים חדשים לספריית אוצריא ולהרחיב את המאגר התורני.',
                            buttonText: 'הצטרף לעריכה',
                            icon: FluentIcons.edit_24_regular,
                            color: Colors.green[600]!,
                            onTap: () async {
                              const url = 'https://forms.gle/editing-form-url';
                              final uri = Uri.parse(url);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri);
                              }
                            },
                          ),

                          const SizedBox(height: 20),

                          // כארד תרומות
                          _buildDonationCard(),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
