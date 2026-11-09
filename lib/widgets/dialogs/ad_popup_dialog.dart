import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/models/support_organization.dart';
import 'package:otzaria/services/ad_popup_service.dart';
import 'package:otzaria/services/support_organizations_service.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/utils/ui/image_decode_size.dart';
import 'package:otzaria/widgets/feedback/app_future_builder.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

const _organizationsLoadError = 'לא ניתן לטעון את פרטי הארגונים';

/// פופאפ פרסומת עם אנימציה מתקדמת
class AdPopupDialog extends StatefulWidget {
  final String title;

  const AdPopupDialog({
    super.key,
    required this.title,
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
      builder: (context) =>
          const AdPopupDialog(title: 'אוצריא מתגייסת לעזרת לומדי התורה'),
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

  late final Future<SupportOrganizations> _organizations;

  @override
  void initState() {
    super.initState();

    _organizations = SupportOrganizationsService.load();

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

    // שהייה קצרה לקריאת הכותרת
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    // הכותרת מתכווצת למעלה והרשימה מופיעה ברציפות
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
                    Flexible(child: _buildAnimatedContent()),
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
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.08),
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant,
                      shape: AppTokens.roundedShape,
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
      // הרשימה נבנית פעם אחת ועוברת דרך child: בלעדיו כל 10 הכרטיסים
      // נבנים מחדש בכל פריים של האנימציה.
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: AppFutureBuilder<SupportOrganizations>(
          future: _organizations,
          loadingWidget: const SizedBox.shrink(),
          errorBuilder: (context, error) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _organizationsLoadError,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          builder: (context, organizations) =>
              _OrganizationsList(organizations: organizations),
        ),
      ),
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
                      'assets/icon/icon_256.png',
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
                                color: Theme.of(context).colorScheme.onSurface,
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
                  child: Opacity(opacity: c, child: child),
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
            // הכפתור שבתוכו פותח את התפריט; עטיפת ה-InkWell של התפריט כבויה,
            // כדי שלא יהיו שתי שכבות ריחוף ושני יעדי פוקוס.
            enabled: false,
            tooltip: '',
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
                    Icon(OtzariaIcons.calendar_24_regular, size: 20),
                    SizedBox(width: 12),
                    Text('למשך שבוע'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'month',
                child: Row(
                  children: [
                    RtlIcon(FluentIcons.calendar_month_24_regular, size: 20),
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
            child: Builder(
              builder: (menuContext) => ActionButton.neutral(
                text: 'אל תציג שוב',
                icon: FluentIcons.dismiss_24_regular,
                onPressed: () => menuContext
                    .findAncestorStateOfType<PopupMenuButtonState<String>>()
                    ?.showButtonMenu(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// רשימת ארגונים
class _OrganizationsList extends StatelessWidget {
  final SupportOrganizations organizations;

  const _OrganizationsList({required this.organizations});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // קווי חירום
        _buildSectionTitle(context, 'קווי חירום', cs.error),
        ...organizations.emergencyLines.map(
          (org) => _ExpandableOrgCard(org: org, isEmergency: true),
        ),
        const SizedBox(height: 20),
        // ארגוני סיוע
        _buildSectionTitle(context, 'ארגוני סיוע', cs.primary),
        ...organizations.supportOrgs.map(
          (org) => _ExpandableOrgCard(org: org, isEmergency: false),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      margin: const EdgeInsets.only(bottom: 12, top: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.08),
            color.withValues(alpha: 0.02),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: AppTokens.borderRadiusAll,
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: color.withValues(alpha: 0.85),
          letterSpacing: 0.5,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// כרטיס ארגון מתרחב
class _ExpandableOrgCard extends StatefulWidget {
  final SupportOrganization org;
  final bool isEmergency;

  const _ExpandableOrgCard({required this.org, required this.isEmergency});

  @override
  State<_ExpandableOrgCard> createState() => _ExpandableOrgCardState();
}

class _ExpandableOrgCardState extends State<_ExpandableOrgCard> {
  bool _isExpanded = false;

  static final _detailsRegex = RegExp(r'\*\*(.*?)\*\*');

  Widget _buildDetailsText(String details) {
    final cs = Theme.of(context).colorScheme;
    final defaultStyle = TextStyle(
      fontSize: 13,
      height: 1.6,
      color: cs.onSurface,
    );
    final boldStyle = defaultStyle.copyWith(
      color: cs.error,
      fontWeight: FontWeight.bold,
    );
    final spans = <TextSpan>[];
    int lastIndex = 0;

    for (final match in _detailsRegex.allMatches(details)) {
      // טקסט רגיל לפני ההדגשה
      if (match.start > lastIndex) {
        spans.add(
          TextSpan(
            text: details.substring(lastIndex, match.start),
            style: defaultStyle,
          ),
        );
      }

      // טקסט מודגש (ללא הכוכביות)
      spans.add(TextSpan(text: match.group(1), style: boldStyle));

      lastIndex = match.end;
    }

    // שאר הטקסט
    if (lastIndex < details.length) {
      spans.add(
        TextSpan(
          text: details.substring(lastIndex),
          style: defaultStyle,
        ),
      );
    }

    return Text.rich(TextSpan(children: spans));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      // צבע הכרטיס מערכת הנושא (במקום לבן קשיח) כדי שיתאים לרקע הפופאפ
      color: colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: AppTokens.borderRadiusAll,
        side: BorderSide(
          color: (widget.isEmergency ? colorScheme.error : colorScheme.primary)
              .withValues(alpha: 0.15),
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
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: AppTokens.borderRadiusAll,
                    ),
                    child: ClipRRect(
                      borderRadius: AppTokens.borderRadiusAll,
                      child: Image(
                        image: coverResizeAsset(
                          context,
                          widget.org.logo,
                          logicalSize: 50,
                          maxSourceAspectRatio:
                              SupportOrganizationsService.maxLogoAspectRatio,
                        ),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(
                            FluentIcons.building_24_regular,
                            size: 30,
                          );
                        },
                      ),
                    ),
                  );
                  final name = Text(
                    widget.org.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  );
                  final phone = Text(
                    widget.org.phone,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color:
                          (widget.isEmergency
                                  ? colorScheme.error
                                  : colorScheme.primary)
                              .withValues(alpha: 0.8),
                      letterSpacing: 1.2,
                    ),
                    textDirection: TextDirection.ltr,
                  );
                  final arrow = Icon(
                    _isExpanded
                        ? FluentIcons.chevron_up_24_regular
                        : FluentIcons.chevron_down_24_regular,
                    color: colorScheme.onSurfaceVariant,
                  );

                  // הסף 400 הוא הרוחב המינימלי לפריסה השורתית בלי שהשם
                  // יתקפל לתו-לשורה: 50 (לוגו) + 16 + ~150 (טלפון מלא) +
                  // 8 + 24 (חץ) = ~250 קבועים, פלוס ~150 מינימום ל-שם.
                  const rowMinWidth = 400.0;
                  final isNarrow = constraints.maxWidth < rowMinWidth;
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
                  if (widget.org.phones.isNotEmpty) ...[
                    const Text(
                      'מספרי טלפון:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...widget.org.phones.map(
                      (phone) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(FluentIcons.phone_24_regular, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              phone,
                              style: const TextStyle(fontSize: 14),
                              textDirection: TextDirection.ltr,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // פרטים
                  if (widget.org.details.isNotEmpty) ...[
                    const Text(
                      'אפשרויות הקו:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildDetailsText(widget.org.details),
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
