import 'dart:async';

import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_motion.dart';

/// הערה שמופיעה רק כשהכנת התצוגה המקדימה מתארכת, כדי שהמתנה ארוכה לא תיראה כתקיעה.
class SlowPreviewHint extends StatefulWidget {
  const SlowPreviewHint({super.key});

  static const Duration delay = Duration(seconds: 3);

  @override
  State<SlowPreviewHint> createState() => SlowPreviewHintState();
}

class SlowPreviewHintState extends State<SlowPreviewHint> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(SlowPreviewHint.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: AppMotion.duration(context, const Duration(milliseconds: 400)),
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'בייצוא של עמודים רבים ההכנה עשויה להימשך עוד מעט...',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.tertiary,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}
