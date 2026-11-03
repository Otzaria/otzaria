import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/utils/ui/fullscreen_helper.dart';

/// לחצן צף ליציאה ממסך מלא — למסכים ללא סרגל עליון (תוספים).
/// במסכים עם AppTopBar הלחצן משולב בסרגל עצמו ולא כלחצן צף.
class ExitFullscreenButton extends StatelessWidget {
  const ExitFullscreenButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'צא ממסך מלא',
      icon: const Icon(FluentIcons.full_screen_minimize_24_regular),
      onPressed: () async {
        await FullscreenHelper.toggleFullscreen(context, false);
      },
      style: IconButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        shape: AppTokens.roundedShape,
      ),
    );
  }
}
