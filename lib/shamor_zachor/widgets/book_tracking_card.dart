import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../models/book_model.dart';

class BookTrackingCard extends StatelessWidget {
  final String bookName;
  final BookDetails bookDetails;
  final String categoryName;
  final VoidCallback onTap;

  const BookTrackingCard({
    super.key,
    required this.bookName,
    required this.bookDetails,
    required this.categoryName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Simple card design for now, can be enhanced
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon & Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withAlpha(50),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(FluentIcons.book_24_regular,
                        color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      bookName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Progress Info (if any)
              Text(categoryName,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
