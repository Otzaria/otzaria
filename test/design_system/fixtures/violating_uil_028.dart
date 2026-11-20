import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as m;

Widget _body(BuildContext context) => const SizedBox();

Future<void> a(BuildContext c) =>
    showDialog<void>(context: c, builder: _body); // LINT
Future<bool?> b(BuildContext context, WidgetBuilder builder) =>
    showDialog(context: context, builder: builder); // LINT
Future<void> prefixed(BuildContext c) =>
    m.showDialog<void>(context: c, builder: _body); // LINT
Future<void> adaptive(BuildContext c) =>
    showAdaptiveDialog<void>(context: c, builder: _body); // LINT
Future<void> cupertino(BuildContext c) =>
    showCupertinoDialog<void>(context: c, builder: _body); // LINT
Widget _page(BuildContext c, Animation<double> a, Animation<double> s) =>
    const SizedBox();
Future<void> general(BuildContext c) =>
    showGeneralDialog<void>(/* LINT */ context: c, pageBuilder: _page);
