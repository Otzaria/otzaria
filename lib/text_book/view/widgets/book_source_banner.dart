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
/// `[תווית](כתובת)`; כתובת שאינה http/https/mailto נשארת טקסט. שבירת שורה
/// אמיתית מפרידה שורות.
List<List<BannerSegment>> parseBannerText(String raw) => [
  for (final line in raw.split('\n')) _parseBannerLine(line),
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

  /// מקביל ל-[_lines]; null לקטע שאינו קישור.
  List<List<TapGestureRecognizer?>> _recognizers = const [];

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
    _recognizers = [
      for (final line in _lines)
        [for (final segment in line) _recognizerFor(segment.url)],
    ];
  }

  static TapGestureRecognizer? _recognizerFor(Uri? uri) {
    if (uri == null) return null;
    return TapGestureRecognizer()
      ..onTap = () async {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
      };
  }

  void _disposeRecognizers() {
    for (final line in _recognizers) {
      for (final recognizer in line) {
        recognizer?.dispose();
      }
    }
    _recognizers = const [];
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
    final lineIndices = [
      for (var i = 0; i < _lines.length; i++)
        if (!isOfflineMode || _lines[i].every((s) => s.url == null)) i,
    ];
    if (lineIndices.isEmpty) return const SizedBox.shrink();
    // אינו חלק מהספר: בחירה והעתקה של הטקסט אינן כוללות אותו.
    return SelectionContainer.disabled(
      child: Container(
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
              for (final (n, i) in lineIndices.indexed) ...[
                if (n > 0) const TextSpan(text: '\n'),
                for (var j = 0; j < _lines[i].length; j++)
                  _lines[i][j].url == null
                      ? TextSpan(text: _lines[i][j].text)
                      : TextSpan(
                          text: _lines[i][j].text,
                          style: linkStyle,
                          recognizer: _recognizers[i][j],
                        ),
              ],
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
