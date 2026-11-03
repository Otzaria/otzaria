import 'package:flutter/material.dart';

class Host {
  void showMenu() {}
}

void use(Host host) => host.showMenu();

Widget item() => const PopupMenuItem(value: 1, child: Text('א'));
