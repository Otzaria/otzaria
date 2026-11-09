import 'package:flutter/material.dart';

final Widget menu = PopupMenuButton<int>(itemBuilder: (_) => const []); // LINT

final Widget anchor = MenuAnchor(menuChildren: const []); // LINT

Future<int?> open(BuildContext c) => // keep
    showMenu<int>(context: c, position: RelativeRect.fill, items: []); // LINT
