import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

Widget otzaria() => const RtlIcon(OtzariaIcons.book_24_regular); // LINT
Widget unregistered() => RtlIcon(FluentIcons.home_24_regular, size: 16); // LINT
Widget mirrorsItself() => RtlIcon(FluentIcons.arrow_left_24_regular); // LINT
Widget flipped() => Transform.flip /* LINT */ (
  flipX: true,
  child: const Icon(FluentIcons.home_24_regular),
);
Widget scaled() => Transform.scale /* LINT */ (
  scaleX: -1,
  child: const Icon(FluentIcons.home_24_regular),
);
