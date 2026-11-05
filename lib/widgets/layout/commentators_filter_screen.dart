import 'package:flutter/material.dart';

import 'package:otzaria/widgets/navigation/commentators_filter_header.dart';

class CommentatorsFilterScreen extends StatelessWidget {
  final VoidCallback onBack;
  final Widget child;

  const CommentatorsFilterScreen({
    super.key,
    required this.onBack,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CommentatorsFilterHeader(onBack: onBack),
        Expanded(child: child),
      ],
    );
  }
}
