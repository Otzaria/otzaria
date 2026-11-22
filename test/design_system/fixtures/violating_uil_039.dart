import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as m;

Widget a() =>
    const SliderTheme(data: SliderThemeData(), child: SizedBox()); // LINT
SliderThemeData b(BuildContext context) => SliderTheme.of(context); // LINT
PreferredSizeWidget c() => AppBar(title: const Text('x')); // LINT
Widget d() => const FloatingActionButton(onPressed: null); // LINT
Widget e() => DropdownButton<int>(items: const [], onChanged: null); // LINT
Widget f() =>
    SegmentedButton<int>(segments: const [], selected: const {}); // LINT
Widget g() => ToggleButtons(isSelected: const [], children: const []); // LINT
Widget h() => const CupertinoSwitch(value: true, onChanged: null); // LINT
Widget body(BuildContext _) => const SizedBox();
Future<void> i(BuildContext c) =>
    showModalBottomSheet<void>(context: c, builder: body); // LINT
Widget j() =>
    m.SegmentedButton<int>(segments: const [], selected: const {}); // LINT
Widget k() =>
    BottomSheet(onClosing: () {}, builder: (_) => const SizedBox()); // LINT
