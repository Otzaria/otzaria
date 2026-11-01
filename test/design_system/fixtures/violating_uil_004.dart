import 'package:flutter/material.dart';

Color fromContext(BuildContext context) =>
    Theme.of(context).primaryColor; // LINT

Color fromVariable(BuildContext context) {
  final theme = Theme.of(context);
  return theme.primaryColor; // LINT
}
