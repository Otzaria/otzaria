import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

Widget registered() =>
    const RtlIcon(FluentIcons.chevron_double_left_20_regular);
Widget variable(IconData icon) => RtlIcon(icon);
Widget otzaria() => const Icon(OtzariaIcons.book_24_regular);
Widget flippedText(Widget child) => Transform.flip(flipX: true, child: child);
Widget zoomed(Widget icon) =>
    Transform.scale(scale: 2, child: const Icon(FluentIcons.home_24_regular));
