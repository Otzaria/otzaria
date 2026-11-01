import 'package:flutter/painting.dart';

TextPainter implicit(TextSpan text) => TextPainter(text: text); // LINT

TextPainter explicit(TextSpan text) =>
    // ignore: unnecessary_new
    new TextPainter(text: text, maxLines: 1); // LINT

TextPainter withDirection(TextSpan text) =>
    TextPainter(text: text, textDirection: TextDirection.rtl);

TextPainter assignedLater(TextSpan text) =>
    TextPainter(text: text) // LINT
      ..textDirection = TextDirection.ltr;
