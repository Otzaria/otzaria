import 'package:flutter/material.dart';

Widget _body(BuildContext context) => const SizedBox();

Future<void> a(BuildContext c) =>
    showDialog<void>(context: c, builder: _body); // LINT
Future<bool?> b(BuildContext context, WidgetBuilder builder) =>
    showDialog(context: context, builder: builder); // LINT
