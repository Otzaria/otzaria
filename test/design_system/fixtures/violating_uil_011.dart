import 'package:flutter/material.dart';

Widget field() => TextField(); // LINT
Widget constField() => const TextField(); // LINT
Widget form(String? value) => TextFormField(initialValue: value); // LINT
Widget editable(TextEditingController controller, FocusNode node) =>
    EditableText /* LINT */ (
      controller: controller,
      focusNode: node,
      style: const TextStyle(),
      cursorColor: Colors.transparent,
      backgroundCursorColor: Colors.transparent,
    );
