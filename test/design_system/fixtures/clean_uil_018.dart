import 'package:flutter/material.dart';

TextStyle content(String family) => TextStyle(fontFamily: family);

TextStyle? body(BuildContext context) => Theme.of(context).textTheme.bodySmall;

const String monospaceFamily = 'monospace';
const TextStyle mono = TextStyle(fontFamily: monospaceFamily);
