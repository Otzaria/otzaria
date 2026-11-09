import 'package:flutter/material.dart';

Widget rich(InlineSpan span) => Text.rich(span);

Widget scaled(BuildContext context, InlineSpan span) =>
    RichText(text: span, textScaler: MediaQuery.textScalerOf(context));

Widget larger(Widget child) => MediaQuery.withClampedTextScaling(
  maxScaleFactor: 2,
  child: child,
);

TextScaler scaler(BuildContext context) => MediaQuery.textScalerOf(context);
