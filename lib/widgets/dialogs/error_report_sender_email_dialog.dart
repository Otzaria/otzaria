import 'package:flutter/material.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// סיומות מייל נפוצות להצגה כהשלמה אוטומטית בעת הקלדת @.
const List<String> commonEmailDomains = [
  'gmail.com',
  'outlook.com',
  'hotmail.com',
  'yahoo.com',
  'icloud.com',
  'walla.co.il',
  'walla.com',
  '012.net.il',
  'bezeqint.net',
  'netvision.net.il',
  '9900.co.il',
];

Future<String?> showErrorReportSenderEmailDialog({
  required BuildContext context,
  String initialValue = '',
  String title = 'כתובת מייל לזיהוי',
  String subtitle =
      'כתובת זו תצורף לדיווח כדי שצוות אוצריא יוכל לחזור אליכם במקרה הצורך.',
}) async {
  String capturedValue = initialValue;

  final confirmed = await showSingleActionDialog(
    context: context,
    title: title,
    confirmText: 'שמור',
    customContent: EmailFieldWithAutocomplete(
      initialValue: initialValue,
      subtitle: subtitle,
      onValueChanged: (v) => capturedValue = v,
    ),
  );

  if (confirmed != true) return null;
  return capturedValue.trim();
}

class EmailFieldWithAutocomplete extends StatefulWidget {
  final String initialValue;
  final String subtitle;
  final ValueChanged<String>? onValueChanged;

  const EmailFieldWithAutocomplete({
    super.key,
    required this.initialValue,
    required this.subtitle,
    this.onValueChanged,
  });

  @override
  State<EmailFieldWithAutocomplete> createState() =>
      _EmailFieldWithAutocompleteState();
}

class _EmailFieldWithAutocompleteState
    extends State<EmailFieldWithAutocomplete> {
  late final TextEditingController _controller;
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();
  final FocusNode _focusNode = FocusNode();
  OverlayEntry? _overlay;
  List<String> _filteredDomains = const [];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _hideOverlay();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      // השהייה קלה כדי לאפשר לחיצה על הצעה לפני שהאוברליי מתבטל
      Future<void>.delayed(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        if (!_focusNode.hasFocus) _hideOverlay();
      });
    } else {
      _onTextChanged();
    }
  }

  void _onTextChanged() {
    if (!mounted) return;
    widget.onValueChanged?.call(_controller.text);
    final text = _controller.text;
    final selection = _controller.selection;

    if (!selection.isValid || !selection.isCollapsed) {
      _hideOverlay();
      return;
    }

    final cursorPos = selection.baseOffset.clamp(0, text.length);
    final beforeCursor = text.substring(0, cursorPos);
    final atIdx = beforeCursor.lastIndexOf('@');
    if (atIdx < 0) {
      _hideOverlay();
      return;
    }

    final typed = beforeCursor.substring(atIdx + 1).toLowerCase();
    final filtered = commonEmailDomains
        .where((d) => d.startsWith(typed) && d != typed)
        .toList();

    if (filtered.isEmpty) {
      _hideOverlay();
      return;
    }

    _filteredDomains = filtered;
    _showOrUpdateOverlay();
  }

  void _showOrUpdateOverlay() {
    if (_overlay == null) {
      _overlay = OverlayEntry(builder: _buildOverlay);
      Overlay.of(context, rootOverlay: true).insert(_overlay!);
    } else {
      _overlay!.markNeedsBuild();
    }
  }

  void _hideOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _applySuggestion(String domain) {
    final text = _controller.text;
    final selection = _controller.selection;
    final cursorPos = selection.isValid && selection.isCollapsed
        ? selection.baseOffset.clamp(0, text.length)
        : text.length;

    final beforeCursor = text.substring(0, cursorPos);
    final atIdx = beforeCursor.lastIndexOf('@');
    if (atIdx < 0) return;

    // קצה הדומיין הקיים מתחיל אחרי ה-@ ונגמר בתו שאינו תקין לדומיין
    // (רווח, פסיק, וכו'). כך אם הסמן באמצע הדומיין לא נשאיר זנב כפול.
    final afterAt = text.substring(atIdx + 1);
    final delimMatch = RegExp(r'[^A-Za-z0-9.\-_]').firstMatch(afterAt);
    final endOfDomain =
        delimMatch == null ? text.length : atIdx + 1 + delimMatch.start;

    final base = text.substring(0, atIdx + 1);
    final after = text.substring(endOfDomain);
    final newText = '$base$domain$after';
    final newCursorPos = atIdx + 1 + domain.length;

    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursorPos),
    );
    _hideOverlay();
    _focusNode.requestFocus();
  }

  double _resolveFieldWidth() {
    final renderObject = _fieldKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      return renderObject.size.width;
    }
    return 280;
  }

  Widget _buildOverlay(BuildContext context) {
    final theme = Theme.of(context);
    final fieldWidth = _resolveFieldWidth();

    return Positioned(
      width: fieldWidth,
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(0, 4),
        child: Material(
          elevation: 4,
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _filteredDomains.length,
              itemBuilder: (context, index) {
                final domain = _filteredDomains[index];
                return InkWell(
                  onTap: () => _applySuggestion(domain),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Text(
                      '@$domain',
                      style: theme.textTheme.bodyMedium,
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.subtitle,
          textDirection: TextDirection.rtl,
        ),
        const SizedBox(height: 12),
        CompositedTransformTarget(
          link: _layerLink,
          child: KeyedSubtree(
            key: _fieldKey,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: RtlTextField(
                controller: _controller,
                focusNode: _focusNode,
                keyboardType: TextInputType.emailAddress,
                textAlign: TextAlign.left,
                decoration: const InputDecoration(
                  labelText: 'כתובת דוא"ל',
                  hintText: 'name@example.com',
                ),
                autofocus: true,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
