import 'package:flutter/material.dart';
import 'package:otzaria/widgets/navigation/commentators_filter_header.dart';

class CommentatorsFilterScreen extends StatelessWidget {
  final VoidCallback onBack;
  final Widget child;
  final String title;

  const CommentatorsFilterScreen({
    super.key,
    required this.onBack,
    required this.child,
    this.title = 'בחירת מפרשים',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CommentatorsFilterHeader(
          onBack: onBack,
          title: title,
        ),
        Expanded(child: child),
      ],
    );
  }
}
