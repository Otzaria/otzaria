import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/sqlite/zip_lookup_repository.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// שדה חיפוש מיקום לפי מיקוד (ZIP ארה"ב או FSA קנדי) — מול מאגרי
/// SQLite מוטמעים (offline לגמרי). מוצג רק כאשר שפת התצוגה של ההגדרות
/// היא אנגלית. תוצאה שנמצאה נוצרת כמיקום מותאם אישית ונבחרת מיד.
class ZipCodeLookupField extends StatefulWidget {
  const ZipCodeLookupField({super.key});

  @override
  State<ZipCodeLookupField> createState() => _ZipCodeLookupFieldState();
}

class _ZipCodeLookupFieldState extends State<ZipCodeLookupField> {
  final _controller = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onSubmit(BuildContext context) async {
    final input = _controller.text.trim();
    if (input.isEmpty || _isLoading) return;

    setState(() => _isLoading = true);
    final cubit = context.read<CalendarCubit>();

    try {
      final result = await ZipLookupRepository.lookupZipOrPostalCode(input);
      if (!context.mounted) return;

      if (result == null) {
        UiSnack.show(
          context,
          'לא נמצא מיקום עבור מיקוד זה (ארה"ב/קנדה בלבד)',
        );
        return;
      }

      await cubit.addCustomLocation(
        name: result.name,
        lat: result.lat,
        lng: result.lng,
        timezone: result.timezone,
      );
      _controller.clear();
    } catch (_) {
      if (context.mounted) {
        UiSnack.show(context, 'שגיאה בחיפוש המיקוד — נסה שוב');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: RtlTextField(
        controller: _controller,
        textDirection: TextDirection.ltr,
        enabled: !_isLoading,
        decoration: InputDecoration(
          hintText: 'ZIP / Postal code',
          isDense: true,
          suffixIcon: _isLoading
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
        ),
        onSubmitted: (_) => _onSubmit(context),
      ),
    );
  }
}
