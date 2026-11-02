import 'package:flutter/material.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

Widget field(TextEditingController controller) =>
    RtlTextField(controller: controller);

Widget region(Widget child) => TextFieldTapRegion(child: child);

const int unlimited = TextField.noMaxLength;
