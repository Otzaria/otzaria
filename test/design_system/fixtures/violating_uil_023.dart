import 'package:flutter/material.dart';

Widget a(Widget child) => AnimatedOpacity(
  opacity: 1,
  duration: const Duration(milliseconds: 200), // LINT
  child: child,
);
Widget b(Widget child) => AnimatedSwitcher(
  duration: Duration(milliseconds: 150), // LINT
  child: child,
);
Widget c() => TweenAnimationBuilder<double>(
  tween: Tween(begin: 0, end: 1),
  duration: const Duration(seconds: 1), // LINT
  builder: (context, v, _) => Opacity(opacity: v),
);
AnimationController d(TickerProvider vsync) => AnimationController(
  vsync: vsync,
  duration: const Duration(milliseconds: 300), // LINT
);
Future<void> e(ScrollController c) => c.animateTo(
  0,
  duration: const Duration(milliseconds: 250), // LINT
  curve: Curves.easeOut,
);
Future<void> f(PageController c) => c.nextPage(
  duration: const Duration(milliseconds: 300), // LINT
  curve: Curves.ease,
);
Future<void> g(PageController c) => c.previousPage(
  duration: const Duration(milliseconds: 300), // LINT
  curve: Curves.ease,
);
