import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox();
}

Widget slider(double v) => Slider(value: v, onChanged: (_) {});
Widget top() => const AppTopBar();
Widget dialog() => const CupertinoAlertDialog();
Widget scrollbar() => const CupertinoScrollbar(child: SizedBox());
Widget icon() => const Icon(CupertinoIcons.back);
ThemeData theme() => ThemeData(sliderTheme: const SliderThemeData());
Widget tabs() => const TabBar(tabs: []);
