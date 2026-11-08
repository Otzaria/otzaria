import 'package:flutter/material.dart';

class AppSurfaces {
  static Color hoverRow(ColorScheme cs) => cs.onSurface;
}

Widget row(ColorScheme cs, VoidCallback onTap) =>
    InkWell(onTap: onTap, hoverColor: AppSurfaces.hoverRow(cs));

Widget selectable(ColorScheme cs, VoidCallback onTap, bool selecting) =>
    InkWell(
      onTap: onTap,
      hoverColor: selecting ? AppSurfaces.hoverRow(cs) : null,
    );

Widget withActions(VoidCallback onTap, bool showButton) => ListTile(
  onTap: onTap,
  hoverColor: showButton ? Colors.transparent : null,
  trailing: const Icon(null),
);
