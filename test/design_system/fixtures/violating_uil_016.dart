// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

Color faded(ColorScheme cs) => cs.primary.withValues(alpha: 0.3); // LINT
Color dim(ColorScheme cs) => cs.onSurface.withAlpha(128); // LINT
Color old(Color c) => c.withOpacity(0.5); // LINT
