import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/plugin_messages.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// עריכה מקומית בפסקת מקור, ללא היסטים או עוגנים של נוסח אחר.
class PluginCorrectionParagraph extends StatefulWidget {
  final String tabId;
  final int sectionIndex;
  final String sourceText;
  final RenderSettings settings;
  final Widget original;
  final PluginCorrectionSessionService? service;

  const PluginCorrectionParagraph({
    super.key,
    required this.tabId,
    required this.sectionIndex,
    required this.sourceText,
    required this.settings,
    required this.original,
    this.service,
  });

  @override
  State<PluginCorrectionParagraph> createState() =>
      _PluginCorrectionParagraphState();
}

class _PluginCorrectionParagraphState extends State<PluginCorrectionParagraph> {
  bool _editable = false;
  final _controller = TextEditingController();
  final _focus = FocusNode();
  PluginCorrectionSessionService get _registry =>
      widget.service ?? PluginCorrectionSessionService.instance;

  @override
  void initState() {
    super.initState();
    _registry.addListener(_changed);
    _syncText();
  }

  @override
  void didUpdateWidget(PluginCorrectionParagraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      (oldWidget.service ?? PluginCorrectionSessionService.instance)
          .removeListener(_changed);
      _registry.addListener(_changed);
    }
    _syncText();
  }

  bool _syncText() {
    final text = _registry.displayText(
      widget.tabId,
      widget.sectionIndex,
      widget.sourceText,
    );
    if (_controller.text == text) return false;
    final selection = _controller.selection;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: selection.isValid
            ? selection.extentOffset.clamp(0, text.length)
            : text.length,
      ),
    );
    return true;
  }

  void _changed() {
    if (!mounted) return;
    final textChanged = _syncText();
    final editable = _registry.canEditParagraph(
      widget.tabId,
      widget.sourceText,
    );
    if (!textChanged && editable == _editable) return;
    _editable = editable;
    setState(() {});
  }

  TextEditingValue _validate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    try {
      _registry.validateNativeEdit(
        widget.tabId,
        widget.sectionIndex,
        widget.sourceText,
        newValue.text,
      );
      return newValue;
    } on PluginCorrectionException catch (error) {
      UiSnack.showError(PluginMessages.correctionEditRejected(error.message));
      return oldValue;
    }
  }

  void _applyText(String text) {
    try {
      _registry.editParagraph(
        widget.tabId,
        widget.sectionIndex,
        widget.sourceText,
        text,
      );
    } on PluginCorrectionException catch (error) {
      UiSnack.showError(PluginMessages.correctionEditRejected(error.message));
      _syncText();
    }
  }

  @override
  Widget build(BuildContext context) {
    _editable = _registry.canEditParagraph(widget.tabId, widget.sourceText);
    if (!_editable) {
      return widget.original;
    }
    final settings = widget.settings;
    return RtlTextField(
      controller: _controller,
      focusNode: _focus,
      maxLines: null,
      minLines: 1,
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
      style: TextStyle(
        fontSize: settings.fontSize,
        fontFamily: settings.fontFamily,
        fontWeight: settings.fontWeight,
        height: settings.lineHeight,
      ),
      inputFormatters: [TextInputFormatter.withFunction(_validate)],
      onChanged: _applyText,
      onSubmitted: (_) => _focus.unfocus(),
    );
  }

  @override
  void dispose() {
    _registry.removeListener(_changed);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }
}
