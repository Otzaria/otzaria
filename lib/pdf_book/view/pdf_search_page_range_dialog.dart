import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/pdf_book/models/pdf_search_page_range.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// דיאלוג "מעמוד / עד עמוד". מחזיר `(range: null)` כששני השדות נשארו ריקים
/// (חיפוש בכל הספר) ו-`null` כשהמשתמש ביטל.
Future<({PdfSearchPageRange? range})?> showPdfSearchPageRangeDialog({
  required BuildContext context,
  required int totalPages,
  PdfSearchPageRange? current,
}) async {
  final input = _PageRangeInput(
    from: current?.firstPage.toString() ?? '',
    to: current?.lastPage.toString() ?? '',
  );

  final confirmed = await showTwoActionsDialog(
    context: context,
    title: 'טווח החיפוש',
    content: '',
    confirmText: 'חפש בטווח',
    customContent: _PageRangeFields(input: input, totalPages: totalPages),
  );
  if (confirmed != true) return null;

  return (
    range: PdfSearchPageRange.parse(
      from: input.from,
      to: input.to,
      totalPages: totalPages,
    ),
  );
}

/// הערכים שהוקלדו — נקראים אחרי סגירת הדיאלוג, כשהבקרים שלו כבר שוחררו.
class _PageRangeInput {
  String from;
  String to;

  _PageRangeInput({required this.from, required this.to});
}

class _PageRangeFields extends StatefulWidget {
  final _PageRangeInput input;
  final int totalPages;

  const _PageRangeFields({required this.input, required this.totalPages});

  @override
  State<_PageRangeFields> createState() => _PageRangeFieldsState();
}

class _PageRangeFieldsState extends State<_PageRangeFields> {
  late final TextEditingController _fromController = TextEditingController(
    text: widget.input.from,
  );
  late final TextEditingController _toController = TextEditingController(
    text: widget.input.to,
  );

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  Widget _field(
    TextEditingController controller,
    String label,
    ValueChanged<String> onChanged,
  ) {
    return Expanded(
      child: RtlTextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintText: '1-${widget.totalPages}',
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'שדה ריק מתפרש כתחילת הספר או סופו. '
            'בספר ${widget.totalPages} עמודים.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _field(
                _fromController,
                'מעמוד',
                (value) => widget.input.from = value,
              ),
              const SizedBox(width: 12),
              _field(
                _toController,
                'עד עמוד',
                (value) => widget.input.to = value,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
