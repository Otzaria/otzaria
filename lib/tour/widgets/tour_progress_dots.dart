// לתחזוקת התקדמות הסיור המודרך ראו: docs/guided_tour_developer_guide.md

import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/theme/app_motion.dart';

class TourProgressDots extends StatelessWidget {
  final int currentIndex;
  final int total;
  final ValueChanged<int>? onDotTap;

  const TourProgressDots({
    super.key,
    required this.currentIndex,
    required this.total,
    this.onDotTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        for (var i = 0; i < total; i++)
          GestureDetector(
            onTap: onDotTap != null ? () => onDotTap!(i) : null,
            child: AnimatedContainer(
              duration: AppMotion.duration(
                context,
                const Duration(milliseconds: 180),
              ),
              width: i == currentIndex ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == currentIndex
                    ? colorScheme.primary
                    : colorScheme.outlineVariant,
                borderRadius: AppTokens.borderRadiusAll,
              ),
            ),
          ),
      ],
    );
  }
}
