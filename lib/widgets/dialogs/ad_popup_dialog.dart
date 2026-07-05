import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/services/ad_popup_service.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:url_launcher/url_launcher.dart';

/// פופאפ פרסומת עם אנימציה מתקדמת
class AdPopupDialog extends StatefulWidget {
  final String title;
  final String? imageUrl;
  final VoidCallback? onAdTap;

  const AdPopupDialog({
    super.key,
    required this.title,
    this.imageUrl,
    this.onAdTap,
  });

  @override
  State<AdPopupDialog> createState() => _AdPopupDialogState();

  /// הצגת הפופאפ אם צריך
  static Future<void> showIfNeeded(
    BuildContext context, {
    bool Function()? shouldSkip,
  }) async {
    // במצב debug לא להציג את הפופאפ אוטומטית
    if (kDebugMode) return;

    if (shouldSkip?.call() ?? false) return;

    final shouldShow = await AdPopupService.shouldShowAd();
    if (!shouldShow) return;

    // המתנה של 5 שניות
    await Future.delayed(const Duration(seconds: 5));

    if (!context.mounted) return;
    if (shouldSkip?.call() ?? false) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const AdPopupDialog(
        title: 'אוצריא מתגייסת לעזרת לומדי התורה',
      ),
    );
  }
}

class _AdPopupDialogState extends State<AdPopupDialog>
    with TickerProviderStateMixin {
  // אנימציית כניסת הדיאלוג עצמו (scale + fade עדין)
  late final AnimationController _entryController;
  late final Animation<double> _entryScale;
  late final Animation<double> _entryFade;

  // אנימציה רציפה של הופעת הטקסט ליד הלוגו (0 -> 1)
  late final AnimationController _textController;
  late final Animation<double> _textReveal;

  // אנימציה רציפה של כיווץ הכותרת למעלה + הופעת הרשימה (0 -> 1)
  late final AnimationController _collapseController;
  late final Animation<double> _collapse;

  @override
  void initState() {
    super.initState();

    // כניסת הדיאלוג: scale עדין מ-0.92 ל-1 יחד עם fade
    _entryController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _entryScale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic),
    );
    _entryFade = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOut,
    );

    // הופעת הטקסט ליד הלוגו
    _textController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _textReveal = CurvedAnimation(
      parent: _textController,
      curve: Curves.easeOutCubic,
    );

    // כיווץ הכותרת למעלה והופעת הרשימה
    _collapseController = AnimationController(
      duration: const Duration(milliseconds: 650),
      vsync: this,
    );
    _collapse = CurvedAnimation(
      parent: _collapseController,
      curve: Curves.easeInOutCubic,
    );

    _entryController.forward();
    _startAnimationSequence();
  }

  void _startAnimationSequence() async {
    // הלוגו לבדו במרכז לרגע קצר
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    // הטקסט מופיע ליד הלוגו (ברציפות, בלי החלפת layout)
    await _textController.forward();
    if (!mounted) return;

    // הכותרת מתכווצת למעלה והרשימה מופיעה מיד, ללא שהייה
    await _collapseController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _textController.dispose();
    _collapseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _entryFade,
      child: ScaleTransition(
        scale: _entryScale,
        child: Dialog(
          backgroundColor: AppSurfaces.panelBackground(context),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: 600,
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // תוכן עם אנימציה רציפה (לוגו -> לוגו+טקסט -> כיווץ למעלה)
                    Flexible(
                      child: _buildAnimatedContent(),
                    ),
                    const Divider(height: 1),
                    // כפתורים תחתונים
                    _buildBottomButtons(),
                  ],
                ),
                // כפתור סגירה X
                Positioned(
                  top: 8,
                  left: 8,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(FluentIcons.dismiss_24_regular),
                    tooltip: 'סגור',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.1),
                      foregroundColor: Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// תוכן הפופאפ עם אנימציה רציפה אחת:
  /// הלוגו והטקסט נמצאים תמיד באותו עץ widget (אין החלפת layout שגורמת
  /// לקפיצות). הלוגו מתחיל גדול וממורכז, הטקסט מופיע לצידו ב-fade,
  /// ולבסוף הכל מתכווץ למעלה והרשימה נפתחת מלמטה ברציפות.
  Widget _buildAnimatedContent() {
    return AnimatedBuilder(
      animation: Listenable.merge([_textReveal, _collapse]),
      builder: (context, child) {
        final c = _collapse.value; // 0 -> 1: התקדמות הכיווץ למעלה
        final t = _textReveal.value; // 0 -> 1: הופעת הטקסט

        // הלוגו מתכווץ מ-120 (לבד במרכז) ל-50 (למעלה ליד הרשימה)
        final logoSize = 120.0 - (c * 70.0);
        final fontSize = 22.0 - (c * 4.0);
        final verticalPadding = 44.0 - (c * 28.0);
        final horizontalPadding = 40.0 - (c * 24.0);
        // הרווח בין לוגו לטקסט גדל כשהטקסט מופיע ומתכווץ מעט בכיווץ
        final gap = (20.0 * t) - (c * 8.0);

        // הכותרת ממורכזת אנכית כל עוד אין רשימה, וצמודה לראש כשהרשימה נפתחת
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // אזור הכותרת (לוגו + טקסט) — ממורכז עד שמתחילים להתכווץ
            Flexible(
              flex: 0,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/icon/iconnew.png',
                      width: logoSize,
                      height: logoSize,
                    ),
                    SizedBox(width: gap),
                    // הטקסט מופיע ב-fade ומתרחב מ-0 רוחב כדי שלא יקפוץ
                    Flexible(
                      child: ClipRect(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          widthFactor: t,
                          child: Opacity(
                            opacity: t,
                            child: Text(
                              widget.title,
                              style: TextStyle(
                                fontSize: fontSize,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                              textAlign: TextAlign.center,
                              softWrap: false,
                              overflow: TextOverflow.visible,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // הרשימה נפתחת מלמטה ברציפות לפי התקדמות הכיווץ
            Flexible(
              child: ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: c,
                  child: Opacity(
                    opacity: c,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      child: _OrganizationsList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBottomButtons() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Builder(
          builder: (builderContext) => PopupMenuButton<String>(
            onSelected: (value) async {
              final navigator = Navigator.of(builderContext);
              switch (value) {
                case 'week':
                  await AdPopupService.setRemindLater(days: 7);
                  break;
                case 'month':
                  await AdPopupService.setRemindLater(days: 30);
                  break;
                case 'forever':
                  await AdPopupService.setDontShowAgain();
                  break;
              }
              navigator.pop();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'week',
                child: Row(
                  children: [
                    Icon(FluentIcons.calendar_24_regular, size: 20),
                    SizedBox(width: 12),
                    Text('למשך שבוע'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'month',
                child: Row(
                  children: [
                    Icon(FluentIcons.calendar_month_24_regular, size: 20),
                    SizedBox(width: 12),
                    Text('למשך חודש'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'forever',
                child: Row(
                  children: [
                    Icon(FluentIcons.prohibited_24_regular, size: 20),
                    SizedBox(width: 12),
                    Text('לעולם'),
                  ],
                ),
              ),
            ],
            child: OutlinedButton.icon(
              onPressed: null, // הכפתור עצמו לא עושה כלום, רק פותח תפריט
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                side: BorderSide(color: Colors.grey.shade400),
              ),
              icon: const Icon(FluentIcons.dismiss_24_regular, size: 18),
              label: const Text('אל תציג שוב'),
            ),
          ),
        ),
      ),
    );
  }
}

/// רשימת ארגונים
class _OrganizationsList extends StatelessWidget {
  final List<Map<String, dynamic>> emergencyLines = [
    {
      'name': 'צבע שחור',
      'phone': '073-888-1234',
      'logo': 'assets/logos/tzeva_shahor.png',
      'matching': true,
      'phones': [
        '073-888-1250 (דיווח)',
        '073-888-1245 (הרשמה)',
        '073-888-1234 (הרשמה)'
      ],
      'details': '''**לדיווח בעת ניסיון מעצר הקש כוכבית**
0 - הרשמה לקבלת התרעות
1 - היסטוריית ההתרעות
2 - שלוחת הרכבים
5 - שלוחת רישום למקבלי הצווים
7 - כמות הנרשמים (מעל 102,631)
8 - דיווח על תקלות במערכת
9 - הסרה מרשימת התפוצה

לאחר לחיצה על 0:
1 - ירושלים
2 - בני ברק
3 - בית שמש
4 - מודיעין עילית
5 - אלעד
6 - לוד גני איילון אחיסמך וכפר חב"ד
7 - ביתר עילית
8 - אשדוד
9 - ערים נוספות

לאחר לחיצה על 9 (ערים נוספות):
1 - ערים בצפון
2 - ערים במרכז
3 - ערים בדרום

ערים בצפון (לחיצה על 1):
1 - חיפה
2 - זכרון יעקב
3 - טבריה
4 - גליל
5 - רכסים והקריות
6 - בית שאן
7 - חדרה והאזור
8 - עפולה, מגדל העמק, הר יונה
9 - יבניאל
10 - נהריה ומעלות תרשיחא

ערים במרכז (לחיצה על 2):
1 - תל אביב יפו
2 - פתח תקווה
3 - רמת גן
4 - אזור רחובות
5 - ערים שונות בגוש דן
6 - אזור השרון
7 - חולון ובת ים
8 - קרית מלאכי
9 - קרית יערים תלסטון
10 - עמנואל

מזרח גוש דן (לחיצה על 5 ואז 0):
0 - כל אזור מזרח גוש דן
1 - גבעת שמואל
2 - יהוד
3 - קרית אונו וגני תקווה
4 - אור יהודה

ערים בדרום (לחיצה על 3):
1 - באר שבע
2 - אשקלון
3 - ירוחם
4 - דימונה
5 - ערים נוספות
6 - ערד
7 - קרית גת

אופקים, נתיבות ותפרח (לחיצה על 5):
0 - אופקים, נתיבות ותפרח ביחד
1 - אופקים
2 - נתיבות
3 - תפרח''',
    },
    {
      'name': 'החוטפים הגיעו',
      'phone': '02-800-8080',
      'logo': 'assets/logos/hachotfim_higiu.jpg',
      'details': '''1 - לרישום
2 - להסרה מרשימת התפוצה
3 - להגבלת שעות כפי המידע שנמסר בהוראות
(לע"ע האפשרות להגבלת שעות היא רק על מבזקים ולא על צינתוקים)
4 - **לדיווח חירום בעת נסיון מעצר**
5 - לדיווח על מחסומים
6 - להשארת הודעות למערכת
7 - להוראות רישום ומידע מורחב על המערכת החדשה
8 - כמות הנרשמים (מעל 108,837)

לאחר לחיצה על 1 (לרישום):
1 - להרשמה לפי עיר
2 - להרשמה לפי אזור בארץ
3 - להרשמה לכל הארץ

לאחר לחיצה על 1 (להרשמה לפי עיר)
יושמע התקליט הבא:
בחר את העיר הרצויה, אם ידוע לך קוד העיר הקש אותו בכל שלב
רשימת הערים יוקראו ברצף -
לבחירת העיר הקש 0
למעבר מהיר לעיר הבאה הקש #
לעיר הקודמת הקש *

1 בני ברק
2 ירושלים
3 בית שמש 
4 מודיעין עילית
5 ביתר 
6 אשדוד 
7 אלעד
8 אופקים
9 אור יהודה
10 אשקלון
11 באר יעקב
12 באר שבע
13 בית חלקיה
14 בית שאן
15 בת ים
16 גני תקוה
17 דימונה
18 זכרון יעקב
19 חדרה
20 חולון
21 חיפה
22 חצור
23 חריש
24 טבריה
25 טלסטון
26 יבניאל
27 יהוד
28 יסודות
29 ירוחם
30 כרמיאל
31 לוד - אחיסמך
32 לוד כללי
33 מגדל העמק
34 מירון
35 מעלה אדומים
36 מעלות
37 נהריה
38 נצרת נוף הגליל
39 נתיבות 
40 נתניה
41 עמנואל
42 עפולה
43 ערד
44 פתח תקוה
45 צפת
46 קוממיות חזון יחזקאל
47 קרית אתא
48 קרית גת
49 קרית מלאכי
50 ראשון לציון
51 רחובות
52 רכסים
53 רמת גן
54 תל אביב יפו
55 תל ציון
56 תפרח
57 אילת
58 הרצליה
59 רמת השרון

לאחר בחירת עיר מסוימת, יושמע התקליט הבא:
לאישור הקש 1
להקשה מחודשת הקישו 2
(אחרי לחיצה על 1 לאישור)
להוספת מספרכם לרשימת הצינתוקים הקישו 1
להסרת מספרכם מרשימת הצינתוקים הקישו 2 
להוספת מספרכם לרשימת הצינתוקים לזמן מסוים הקישו 3
להשתקת קבלת צינתוקים עד לזמן מסוים הקישו 4 
ליציאה הקישו *

לאחר לחיצה על 2 (להרשמה לפי אזור)
יושמע התקליט הבא:
הקש את קוד האזור, ובסיום הקש סולמית
1 אזור המרכז
2 אזור ירושלים ובית שמש
3 אזור הדרום - אזור אשדוד
4 אזור הדרום - אזור הנגב
5 אזור הגליל והגולן
6 אזור הצפון - קו החוף''',
    },
  ];

  final List<Map<String, dynamic>> supportOrgs = [
    {
      'name': 'נותנים גב',
      'phone': '04-313-2000',
      'logo': 'assets/logos/notnim_gav.png',
      'details': '''לאנגלית הקש 4
1 - מוקד רישום לבחורים מקבלי הצווים
2 - אגף ייעוץ מקצועי
3 - אגף תמיכה לנשים ואמהות
5 - הדרכה מוקלטת למקבלי הצווים
8 - הרשמה להתנדבות בארגון
9 - השארת הודעה למנהלי הארגון
0 - תרומות במענה אנושי או אוטומטי
* - מוקד חרום בעת מעצר''',
    },
    {
      'name': 'עם קדוש',
      'phone': '*5172',
      'logo': 'assets/logos/am_kadosh.jpg',
      'details': '''גימטריא קטנה של "נאזר" בגבורה
1 - בחור מגיל 18 ומעלה שקיבל צו
2 - מגיל 16 וחצי עד 18
3 - השארת הודעה
4 - מענה בעת ניסיון מעצר או בשעת מעצר
5 - דיווח על מחסומים ברחבי הארץ
8 - תרומות''',
    },
    {
      'name': 'עזרם ומגינם',
      'phone': '02-500-0110',
      'logo': 'assets/logos/ezram_maginam.png',
      'details': '''1 - מידע והנחיות
2 - מענה אנושי
3 - פניה בעת מעצר
4 - מזכירות הארגון
9 - הרשמה לקבלת התרעות בעת מעצר''',
    },
    {
      'name': 'הפקדתי שומרים',
      'phone': '09-313-2142',
      'logo': 'assets/logos/ezram.jpg',
      'details': '''ארגון לתושבי ביתר
הפועל בצמוד ובתמיכת רבני העיר
* - מוקד החירום במקרי מעצר
1 - רישום למקבלי צווי הגיוס
2 - לייעוץ משפטי למקבלי הצווים
3 - מוקד התמיכה לאמהות ונשות מקבלי הצווים
4 - מענה מנציגים
9 - להנהלת הארגון
0 - לתרומות''',
    },
    {
      'name': 'אגודת בני הישיבות',
      'phone': '02-994-0030',
      'logo': 'assets/logos/agudat_bnei_yeshivot.png',
      'details': '''1 - לרישום
2 - מענה והכוונה משפטית
3 -מענה בשפות נוספות
7 - מוקד משפטי למנהלי הישיבות
9 - שלוחת החירום למקרי מעצר
קו תוכן שע"י האגודה: 077-226-2626
אפשרויות קו התוכן:
1 - עדכונים
5 - רישום, תמיכה וסיוע משפטי
6 - תרומות
9 - הרשמה והסרה מרשימות התפוצה''',
    },
    {
      'name': 'הצלה לאחים',
      'phone': '02-502-3231',
      'logo': 'assets/logos/hatzala_leachim.png',
      'details': '''1 - לפניות חדשות והמשך טיפול
2 - לפניות בנושא עיכוב יציאה מהארץ
3 - לפניות בנושא עצורים בכלא הצבאי
6 - לקבלת כתובת המייל והפקס
8 - לשמיעת הסטטוס בתיק שלכם
9 - לשמיעה חוזרת''',
    },
    {
      'name': 'אחים אנחנו',
      'phone': '02-579-5252',
      'logo': 'assets/logos/achim_anachnu.png',
      'details': '''1 - למקבלי צווי ההתיצבות והגיוס
2 - לבעיות מול הצבא
4 - להשארת הודעה
5 - לקבלת מספר הפקס ודואר אלקטרוני
6 - לכל נושא אחר''',
    },
    {
      'name': 'מגן ומושיע',
      'phone': '*9273',
      'logo': 'assets/logos/magen_umoshia.png',
      'details': '''ארגון סיוע ללומדי תורה''',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // קווי חירום
        _buildSectionTitle('קווי חירום', Colors.red),
        ...emergencyLines.map((org) => _buildOrgCard(context, org, true)),
        const SizedBox(height: 20),
        // ארגוני סיוע
        _buildSectionTitle('ארגוני סיוע', Colors.blue),
        ...supportOrgs.map((org) => _buildOrgCard(context, org, false)),
      ],
    );
  }

  Widget _buildSectionTitle(String title, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      margin: const EdgeInsets.only(bottom: 12, top: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.08),
            color.withValues(alpha: 0.02)
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: AppTokens.borderRadiusAll,
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: color.withValues(alpha: 0.85),
          letterSpacing: 0.5,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildOrgCard(
      BuildContext context, Map<String, dynamic> org, bool isEmergency) {
    return _ExpandableOrgCard(org: org, isEmergency: isEmergency);
  }
}

/// כרטיס ארגון מתרחב
class _ExpandableOrgCard extends StatefulWidget {
  final Map<String, dynamic> org;
  final bool isEmergency;

  const _ExpandableOrgCard({
    required this.org,
    required this.isEmergency,
  });

  @override
  State<_ExpandableOrgCard> createState() => _ExpandableOrgCardState();
}

class _ExpandableOrgCardState extends State<_ExpandableOrgCard> {
  bool _isExpanded = false;

  static final _defaultDetailsStyle = TextStyle(
    fontSize: 13,
    height: 1.6,
    color: Colors.grey[800],
  );

  static final _boldDetailsStyle = _defaultDetailsStyle.copyWith(
    color: Colors.red[700],
    fontWeight: FontWeight.bold,
  );

  static final _detailsRegex = RegExp(r'\*\*(.*?)\*\*');

  Widget _buildDetailsText(String details) {
    final spans = <TextSpan>[];
    int lastIndex = 0;

    for (final match in _detailsRegex.allMatches(details)) {
      // טקסט רגיל לפני ההדגשה
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: details.substring(lastIndex, match.start),
          style: _defaultDetailsStyle,
        ));
      }

      // טקסט מודגש (ללא הכוכביות)
      spans.add(TextSpan(
        text: match.group(1),
        style: _boldDetailsStyle,
      ));

      lastIndex = match.end;
    }

    // שאר הטקסט
    if (lastIndex < details.length) {
      spans.add(TextSpan(
        text: details.substring(lastIndex),
        style: _defaultDetailsStyle,
      ));
    }

    return Text.rich(
      TextSpan(children: spans),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      // צבע הכרטיס מערכת הנושא (במקום לבן קשיח) כדי שיתאים לרקע הפופאפ
      color: colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: AppTokens.borderRadiusAll,
        side: BorderSide(
          color: widget.isEmergency
              ? Colors.red.withValues(alpha: 0.15)
              : Colors.blue.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: AppTokens.borderRadiusAll,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final logo = Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: AppTokens.borderRadiusAll,
                    ),
                    child: ClipRRect(
                      borderRadius: AppTokens.borderRadiusAll,
                      child: Image.asset(
                        widget.org['logo'],
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(FluentIcons.building_24_regular,
                              size: 30);
                        },
                      ),
                    ),
                  );
                  final name = Text(
                    widget.org['name'],
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                  final phone = Text(
                    widget.org['phone'],
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: widget.isEmergency
                          ? Colors.red.withValues(alpha: 0.8)
                          : Colors.blue.withValues(alpha: 0.8),
                      letterSpacing: 1.2,
                    ),
                    textDirection: TextDirection.ltr,
                  );
                  final arrow = Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.grey[600],
                  );

                  // הסף 400 הוא הרוחב המינימלי לפריסה השורתית בלי שהשם
                  // יתקפל לתו-לשורה: 50 (לוגו) + 16 + ~150 (טלפון מלא) +
                  // 8 + 24 (חץ) = ~250 קבועים, פלוס ~150 מינימום ל-שם.
                  final isNarrow = constraints.maxWidth < 400;
                  if (isNarrow) {
                    return Row(
                      children: [
                        logo,
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              name,
                              const SizedBox(height: 4),
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: phone,
                              ),
                            ],
                          ),
                        ),
                        arrow,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      logo,
                      const SizedBox(width: 16),
                      Expanded(child: name),
                      phone,
                      const SizedBox(width: 8),
                      arrow,
                    ],
                  );
                },
              ),
            ),
          ),
          // שורת מצ'ינג — שייכת לכרטיס "צבע שחור", קטנה יותר משורת הארגון.
          // מוצגת רק בטווח ימי הקמפיין (ראה AdPopupService.isMatchingBannerActive)
          if (widget.org['matching'] == true &&
              AdPopupService.isMatchingBannerActive)
            _MatchingBanner(),
          // מידע מורחב
          if (_isExpanded) ...[
            const Divider(height: 1),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: colorScheme.surfaceContainer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // טלפונים נוספים
                  if (widget.org['phones'] != null) ...[
                    const Text(
                      'מספרי טלפון:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...((widget.org['phones'] as List).map((phone) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              const Icon(FluentIcons.phone_24_regular,
                                  size: 16),
                              const SizedBox(width: 8),
                              Text(
                                phone,
                                style: const TextStyle(fontSize: 14),
                                textDirection: TextDirection.ltr,
                              ),
                            ],
                          ),
                        ))),
                    const SizedBox(height: 12),
                  ],
                  // פרטים
                  if (widget.org['details'] != null) ...[
                    const Text(
                      'אפשרויות הקו:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildDetailsText(widget.org['details']),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// שורת "מצ'ינג" תחת "צבע שחור": טקסט שחור מהבהב, מוקף פס בצבעים מתחלפים.
/// בלחיצה נפתח דיאלוג הסבר על ההוצאות עם קישור לתרומה.
class _MatchingBanner extends StatefulWidget {
  @override
  State<_MatchingBanner> createState() => _MatchingBannerState();
}

class _MatchingBannerState extends State<_MatchingBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;
          // צבע המסגרת נע על גלגל הגוונים ומתחלף ברציפות (רוויה+בהירות מלאות)
          final borderColor =
              HSVColor.fromAHSV(1, (t * 360) % 360, 1.0, 1.0).toColor();
          // הבהוב הטקסט: אטימות נעה בין 0.45 ל-1
          final textOpacity = 0.45 + 0.55 * (0.5 + 0.5 * (t * 2 - 1).abs());
          // המסגרת "נושמת" — מתקרבת ומתרחקת (pulse); שתי פעימות במחזור
          final scale = 1.0 + 0.06 * (0.5 + 0.5 * math.sin(t * 4 * math.pi));
          return InkWell(
            onTap: () => _showMatchingDialog(context),
            borderRadius: BorderRadius.circular(10),
            child: Transform.scale(
              scale: scale,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor, width: 2),
                ),
                child: child != null
                    ? Opacity(opacity: textOpacity, child: child)
                    : const SizedBox.shrink(),
              ),
            ),
          );
        },
        child: const Text(
          "ימי התרמה ל'צבע שחור - נותנים גב', בימים שני-שלישי - תרום כעת!",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}

/// דיאלוג "הידעת?" — הסבר על הוצאות "צבע שחור" עם קישור לתרומה.
Future<void> _showMatchingDialog(BuildContext context) {
  const donateUrl = 'https://www.liveraiser.co.il/gav/88888';
  return showDialog(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: AppSurfaces.panelBackground(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'הידעת?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'מאחורי כל מקבל צו עומד מערך שלם ויקר:\n'
              '4 פעילים בלשכות הגיוס + הסעות מדי יום,\n'
              'מוקד חירום בכמה שפות הפועל 24 שעות, ומבזקים למאה אלף איש,\n'
              'מודעות רחוב בערים, ושלושה משרדים בתחזוקה מלאה,\n'
              'ליווי עצורים, חבילות לכלא ולמשפחות, וכינוסי הסברה בכל הארץ,\n'
              'וזו רק ההתחלה — פרויקטים רבים עוד ממתינים.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                height: 1.6,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            InkWell(
              onTap: () async {
                final uri = Uri.parse(donateUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: const Text(
                'ההוצאות עצומות - ומימון אין, עזרתך דרושה, לחץ כאן כעת!!!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
