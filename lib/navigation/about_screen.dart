import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:path/path.dart' as p;
import '../settings/bloc/settings_repository.dart';
import '../services/data_collection_service.dart';
import '../data/repository/data_repository.dart';
import 'dart:io';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

Future<String?> _getOtzariaSitePath() async {
  final libraryPath = Settings.getValue(SettingsRepository.keyLibraryPath);
  if (libraryPath == null || libraryPath.isEmpty) return null;

  // התיקייה otzaria-site נמצאת באותה תיקייה שבה נמצא "גירסת ספריה.txt"
  final otzariaSitePath = Directory(
      '$libraryPath${Platform.pathSeparator}אוצריא${Platform.pathSeparator}אודות התוכנה${Platform.pathSeparator}otzaria-site');
  if (await otzariaSitePath.exists()) {
    return otzariaSitePath.path;
  }
  return null;
}

Future<void> openLocalHtmlFile(BuildContext context, String fileName) async {
  final sitePath = await _getOtzariaSitePath();
  if (!context.mounted) return;
  if (sitePath == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('לא נמצאה תיקיית otzaria-site')),
    );
    return;
  }

  final htmlFile = File('$sitePath/$fileName');
  final exists = await htmlFile.exists();
  if (!context.mounted) return;
  if (!exists) {
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

// קבועים לגדלים ומרווחים
const double _kIconSize = 16.0;
const double _kIconTextSpacing = 8.0;

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
        maxLines: 1,
        softWrap: false,
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
        maxLines: 1,
        softWrap: false,
        style: const TextStyle(
          color: Colors.blue,
        ),
      ),
    );
  }

  /// חישוב רוחב פריט לפי השם הכי ארוך ברשימה
  double _calculateItemWidth(List<Map<String, String?>> items,
      {double extraPadding = 24}) {
    if (items.isEmpty) return 0;

    final longestName = items
        .map((item) => item['name'] ?? '')
        .reduce((a, b) => a.length > b.length ? a : b);

    final textPainter = TextPainter(
      text: TextSpan(
        text: longestName,
        style: const TextStyle(fontSize: 14),
      ),
      textDirection: TextDirection.rtl,
    )..layout();

    // רוחב = רוחב טקסט + אייקון + רווח + מרווח בטחון
    return textPainter.width + _kIconSize + _kIconTextSpacing + extraPadding;
  }

  Widget _buildDevelopersList() {
    final developers = [
      {
        'name': 'sivan22',
        'url': 'https://github.com/Sivan22',
      },
      {
        'name': 'ר. נבון',
        'url': 'https://github.com/rachelGrayover',
        'description': 'השקעה עצומה במעבר ל-SQLite'
      },
      {'name': 'Y.PL.', 'url': 'https://github.com/Y-PLONI'},
      {'name': 'YOSEFTT', 'url': 'https://github.com/YOSEFTT'},
      {'name': 'zevisvei', 'url': 'https://github.com/zevisvei'},
      {'name': 'evel-avalim', 'url': 'https://github.com/evel-avalim'},
      {'name': 'userbot', 'url': 'https://github.com/userbot000'},
      {
        'name': 'mosh-dvd',
        'url': 'https://github.com/mosh-dvd',
      },
      {
        'name': 'NHLOCAL',
        'url': 'https://github.com/NHLOCAL/Shamor-Zachor',
        'description': "מפתח 'שמור וזכור'"
      },
    ];

    return _buildContributorsList(developers, FluentIcons.person_24_regular);
  }

  Widget _buildContributorsList(
      List<Map<String, String?>> contributors, IconData icon) {
    final itemWidth = _calculateItemWidth(contributors);

    return LayoutBuilder(
      builder: (context, constraints) {
        // במסכים קטנים, הצג בעמודה
        if (constraints.maxWidth < 500) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: contributors
                .map((contributor) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(icon, size: _kIconSize, color: Colors.grey),
                              SizedBox(width: _kIconTextSpacing),
                              Expanded(
                                child: _buildContributor(contributor['name']!,
                                    contributor['url'] ?? ''),
                              ),
                            ],
                          ),
                          if (contributor['description'] != null)
                            Padding(
                              padding: EdgeInsets.only(
                                  left: _kIconSize + _kIconTextSpacing, top: 2),
                              child: Text(
                                '(${contributor['description']})',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
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
          spacing: 16,
          runSpacing: 12,
          children: contributors
              .map((contributor) => SizedBox(
                    width: itemWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(icon, size: _kIconSize, color: Colors.grey),
                            SizedBox(width: _kIconTextSpacing),
                            Expanded(
                              child: _buildContributor(contributor['name']!,
                                  contributor['url'] ?? ''),
                            ),
                          ],
                        ),
                        if (contributor['description'] != null)
                          Padding(
                            padding: EdgeInsets.only(
                                left: _kIconSize + _kIconTextSpacing, top: 2),
                            child: Text(
                              '(${contributor['description']})',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
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

  Widget _buildEssentialPeopleList() {
    const essentialPeople = [
      {
        'name': 'דוד אריאל',
        'url': '',
      },
      {
        'name': 'יעקב מ. פינס',
        'url': 'https://github.com/ymp112',
      },
      {
        'name': 'רפאל א.',
        'url': '',
      },
      // ניתן להוסיף עוד אנשים כאן
    ];

    return _buildContributorsList(
        essentialPeople, FluentIcons.people_24_regular);
  }

  Widget _buildBookEditorsList() {
    // מהדירים שההדירו 10 ספרים ומעלה
    final topEditors = [
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
        'url': 'https://mitmachim.top/user/sivan22',
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
      // {
      //   'name': 'י. אשכנזי', // כרגע לא רוצה
      // },
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
    final regularEditors = [
      {
        'name': 'מויטיו',
        'url':
            'https://mitmachim.top/user/%D7%9E%D7%95%D7%99%D7%98%D7%99%D7%95',
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
        _buildContributorsList(topEditors, FluentIcons.book_24_regular),
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
        _buildContributorsList(regularEditors, FluentIcons.book_24_regular),
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

  Widget _buildMemorialCardsRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardHeight = 140.0;
        final totalSpacing = 32.0;
        final itemWidth =
            (constraints.maxWidth - totalSpacing).clamp(1, double.infinity) / 3;
        final aspectRatio = itemWidth / cardHeight;

        return GridView.count(
          crossAxisCount: 3,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: aspectRatio,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildMemorialCard(
              'לע"נ ר\' משה בן יהודה ראה ז"ל',
              'סכום משמעותי לפיתוח התוכנה',
            ),
            _buildDonationMemorialCard(
              'מקום זה יכול להיות מונצח לע"נ יקירך',
            ),
            _buildDonationMemorialCard(
              'מקום זה יכול להיות מונצח לע"נ יקירך',
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
    return _buildGenericMemorialCard(name, description);
  }

  Widget _buildDonationMemorialCard(String name) {
    return _buildGenericMemorialCard(name, 'לחץ כאן',
        onTap: () => _openLocalHtmlFile('donate.html'));
  }

  Widget _buildGenericMemorialCard(String name, String description,
      {VoidCallback? onTap}) {
    return SizedBox(
      height: 140, // גודל קבוע לכל הכארדים
      child: Card(
        elevation: 2,
        child: onTap != null
            ? InkWell(
                onTap: onTap,
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
              )
            : Padding(
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

    // Load book count (excluding external library books)
    try {
      final library = await DataRepository.instance.library;
      final allBooks = library.getAllBooks();
      // Count only books without externalLibraryId (non-external books)
      bookCount =
          allBooks.where((book) => book.externalLibraryId == null).length;
    } catch (e) {
      debugPrint('Error counting books: $e');
      bookCount = 0;
    }
  }

  Future<void> _openLocalHtmlFile(String fileName) async {
    await openLocalHtmlFile(context, fileName);
  }

  Future<void> _showChangelogDialog(BuildContext context) async {
    final changelog = await rootBundle.loadString('assets/יומן שינויים.md');

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('יומן שינויים בתוכנה'),
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

  Future<void> _showLibraryChangelogDialog(BuildContext context) async {
    final libraryPath =
        Settings.getValue<String>(SettingsRepository.keyLibraryPath) ?? '';
    if (libraryPath.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('נתיב הספרייה לא מוגדר')),
      );
      return;
    }

    final changelogPath =
        p.join(libraryPath, 'אוצריא', 'אודות התוכנה', 'עדכוני ספריה.md');
    final file = File(changelogPath);

    String changelog;
    if (await file.exists()) {
      changelog = await file.readAsString();
    } else {
      changelog = 'קובץ יומן השינויים לא נמצא';
    }

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('יומן שינויים בספרייה'),
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
        color: Colors.grey[600]!.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[600]!.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FluentIcons.heart_24_regular,
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
      child: Column(
        children: [
          Expanded(
            child: isSmallScreen
                ? _buildSmallScreenLayout(context)
                : _buildWideScreenLayout(context),
          ),
          _buildTechnicalFooter(context),
        ],
      ),
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
                      'assets/icon/iconnew.png',
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

                // כארדים לתורמים
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

                // אנשים שהתוכנה לא יכולה בלעדיהם
                const Text(
                  'התוכנה נעזרה רבות ב:',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildEssentialPeopleList(),
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
                const SizedBox(height: 8),
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
                    _buildDonationCard(),
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
          _buildDonationCard(),
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
          const SizedBox(height: 24),

          // תורמים
          const Text(
            'תורמים',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildMemorialCardsRow(),
          const SizedBox(height: 24),

          // מפתחים
          const Text(
            'מפתחים',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildDevelopersList(),
          const SizedBox(height: 24),

          // אנשים שהתוכנה לא יכולה בלעדיהם
          const Text(
            'התוכנה נעזרה רבות ב:',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildEssentialPeopleList(),
          const SizedBox(height: 24),

          // מהדירי ספרים
          const Text(
            'מהדירי ספרים',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildBookEditorsList(),
          const SizedBox(height: 24),

          const SizedBox(height: 8),
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
              'assets/icon/iconnew.png',
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

  Widget _buildTechnicalFooter(BuildContext context) {
    final footerItems = [
      _buildFooterInfoItem(
        label: 'גרסת תוכנה',
        value: appVersion ?? 'לא ידוע',
        onHistoryTap: () => _showChangelogDialog(context),
      ),
      _buildFooterInfoItem(
        label: 'גרסת ספרייה',
        value: libraryVersion ?? 'לא ידוע',
        onHistoryTap: () => _showLibraryChangelogDialog(context),
      ),
      _buildFooterInfoItem(
        label: 'מספר ספרים',
        value: '${bookCount ?? 'לא ידוע'}',
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 600) {
            return Wrap(
              spacing: 16,
              runSpacing: 8,
              children: footerItems,
            );
          }

          return Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: footerItems[0],
                ),
              ),
              Expanded(
                child: Center(
                  child: footerItems[1],
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: footerItems[2],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFooterInfoItem({
    required String label,
    required String value,
    VoidCallback? onHistoryTap,
  }) {
    final bool isButton = onHistoryTap != null;

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
        Flexible(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );

    if (isButton) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onHistoryTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.3),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Tooltip(
              message: 'הצג יומן שינויים',
              child: content,
            ),
          ),
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: content,
      );
    }
  }
}
