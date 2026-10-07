import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

/// משווה את שדות הזהות שקובעים את מקור הספר. במסלול side-by-side ה-widget
/// אינו ממופתח לפי identity, ולכן מעבר לספר בעל אותה כותרת אך מקור שונה חייב
/// לזהות גם הבדל ב-categoryId/fileType/מקור כדי לרענן את הבאנר.
bool sameSourceIdentity(TextBook a, TextBook b) =>
    a.title == b.title &&
    a.categoryId == b.categoryId &&
    a.fileType == b.fileType &&
    a.source == b.source;

/// קטע בטקסט הבאנר: טקסט רגיל, או קישור כש-[url] אינו null.
typedef BannerSegment = ({String text, Uri? url});

/// הכתובת שמורה במסד מקודדת כבר, ולכן אין בה רווחים או סוגריים.
final _bannerLinkPattern = RegExp(r'\[([^\]\n]+)\]\(([^)\s]+)\)');

/// מפרק את טקסט הבאנר מהמסד לשורות של קטעים. הסימון היחיד הוא
/// `[תווית](כתובת)`; כתובת שאינה http/https/mailto נשארת טקסט.
/// `\n` (אמיתי או מילולי) מפריד שורות.
List<List<BannerSegment>> parseBannerText(String raw) => [
  for (final line in raw.replaceAll(r'\n', '\n').split('\n'))
    _parseBannerLine(line),
];

List<BannerSegment> _parseBannerLine(String line) {
  final segments = <BannerSegment>[];
  var position = 0;
  for (final match in _bannerLinkPattern.allMatches(line)) {
    if (match.start > position) {
      segments.add((text: line.substring(position, match.start), url: null));
    }
    final url = _parseBannerUrl(match.group(2)!);
    segments.add((
      text: url == null ? match.group(0)! : match.group(1)!,
      url: url,
    ));
    position = match.end;
  }
  if (position < line.length || segments.isEmpty) {
    segments.add((text: line.substring(position), url: null));
  }
  return segments;
}

Uri? _parseBannerUrl(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  const allowed = {'http', 'https', 'mailto'};
  return allowed.contains(uri.scheme.toLowerCase()) ? uri : null;
}

/// שורה נגללת המוצגת מעל השורה הראשונה בספרים שיש להם באנר במסד.
/// אינה חלק מתוכן הספר עצמו — לכן אינה משפיעה על אינדקסי שורות, קישורים או חיפוש.
class BookSourceBanner extends StatefulWidget {
  const BookSourceBanner({super.key, required this.text, this.fontSize});

  final String text;
  final double? fontSize;

  @override
  State<BookSourceBanner> createState() => _BookSourceBannerState();
}

class _BookSourceBannerState extends State<BookSourceBanner> {
  List<List<BannerSegment>> _lines = const [];
  final Map<BannerSegment, TapGestureRecognizer> _recognizers = {};

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(covariant BookSourceBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _parse();
  }

  void _parse() {
    _disposeRecognizers();
    _lines = parseBannerText(widget.text);
    for (final line in _lines) {
      for (final segment in line) {
        final uri = segment.url;
        if (uri == null) continue;
        _recognizers[segment] = TapGestureRecognizer()
          ..onTap = () async {
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
            }
          };
      }
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // גופן קטן ביחס לטקסט הספר — שורת קרדיט, לא חלק מהתוכן.
    final size = widget.fontSize == null ? null : widget.fontSize! * 0.6;
    final textStyle = TextStyle(
      fontSize: size,
      height: 1.3,
      color: cs.onSurfaceVariant,
    );
    final linkStyle = TextStyle(
      color: cs.primary,
      decoration: TextDecoration.underline,
    );
    final isOfflineMode = context.watch<SettingsBloc>().state.isOfflineMode;
    // במצב לא מקוון שורה עם קישור אינה מוצגת — ההנחיה שבה אינה ברת ביצוע.
    final lines = isOfflineMode
        ? _lines.where((line) => line.every((s) => s.url == null)).toList()
        : _lines;
    if (lines.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text.rich(
        TextSpan(
          style: textStyle,
          children: [
            for (var i = 0; i < lines.length; i++) ...[
              if (i > 0) const TextSpan(text: '\n'),
              for (final segment in lines[i])
                segment.url == null
                    ? TextSpan(text: segment.text)
                    : TextSpan(
                        text: segment.text,
                        style: linkStyle,
                        recognizer: _recognizers[segment],
                      ),
            ],
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
