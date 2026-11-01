import 'package:flutter/material.dart';

const TextStyle small = TextStyle(fontSize: 13); // LINT
TextStyle copy(TextStyle base) => base.copyWith(fontSize: 12.5); // LINT
TextStyle plain(Color color) => TextStyle(color: color, fontSize: 14); // LINT
