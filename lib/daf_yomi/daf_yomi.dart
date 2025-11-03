import 'package:flutter/material.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/daf_yomi/calendar.dart';

class DafYomi extends StatelessWidget {
  final Function(String tractate, String daf) onDafYomiTap;
  final VoidCallback onCalendarTap;

  const DafYomi({
    super.key,
    required this.onDafYomiTap,
    required this.onCalendarTap,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        final Daf dafYomi = getDafYomi(DateTime.now());

        final tractate = dafYomi.getMasechta();
        final dafAmud = dafYomi.getDaf();
        
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surface
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // חלק הטקסטים - פותח את הדף היומי
              Tooltip(
                message: 'פתח דף יומי',
                child: InkWell(
                  onTap: () => onDafYomiTap(
                    tractate,
                    formatAmud(dafAmud),
                  ),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          getHebrewDateFormattedAsString(DateTime.now()),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.secondary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'דף היומי: $tractate ${formatAmud(dafAmud)}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.secondary,
                            fontSize: 11,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              // פס מפריד אפור - בגובה האייקון בדיוק
              Container(
                width: 1,
                height: 24,
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
              ),
              
              // אייקון לוח שנה - פותח את הלוח שנה
              Tooltip(
                message: 'פתח לוח שנה',
                child: InkWell(
                  onTap: onCalendarTap,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomLeft: Radius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Icon(
                      Icons.calendar_month_outlined,
                      color: Theme.of(context).colorScheme.secondary,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
