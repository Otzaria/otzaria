// ignore_for_file: prefer_const_constructors

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

class PageNumberDisplay extends StatefulWidget {
  final PdfViewerController controller;

  /// מספר העמוד הנוכחי כפי שדווח ב-`PdfViewerParams.onPageChanged`. ה-controller
  /// מודיע רק על שינוי מטריצה, ו-`pageNumber` שלו מתעדכן רק ב-build שאחריו —
  /// בלי המאזין הזה המונה מפגר עמוד עד לאינטראקציה הבאה.
  final ValueListenable<int?>? pageNumberNotifier;

  /// ניווט של המסך (שומר זום ונעילת זוגות); בלעדיו goToPage מאפס את הזום.
  final Future<void> Function(int pageNumber)? onNavigateToPage;

  const PageNumberDisplay({
    super.key,
    required this.controller,
    this.pageNumberNotifier,
    this.onNavigateToPage,
  });

  @override
  State<PageNumberDisplay> createState() => _PageNumberDisplayState();
}

class _PageNumberDisplayState extends State<PageNumberDisplay> {
  late TextEditingController _textController;
  bool _isEditing = false;
  final FocusNode _focusNode = FocusNode();
  int? _lastPage;
  int? _lastCount;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    widget.controller.addListener(_handlePageChange);
    widget.pageNumberNotifier?.addListener(_handlePageChange);
    _captureControllerState();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isEditing) {
        setState(() {
          _isEditing = false;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant PageNumberDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller &&
        oldWidget.pageNumberNotifier == widget.pageNumberNotifier) {
      return;
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handlePageChange);
      widget.controller.addListener(_handlePageChange);
    }
    if (oldWidget.pageNumberNotifier != widget.pageNumberNotifier) {
      oldWidget.pageNumberNotifier?.removeListener(_handlePageChange);
      widget.pageNumberNotifier?.addListener(_handlePageChange);
    }
    _captureControllerState();
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    widget.controller.removeListener(_handlePageChange);
    widget.pageNumberNotifier?.removeListener(_handlePageChange);
    super.dispose();
  }

  void _handlePageChange() {
    if (!mounted) return;
    final ready = widget.controller.isReady;
    final page = ready ? _currentPage : null;
    final count = ready ? widget.controller.pageCount : null;
    if (page == _lastPage && count == _lastCount) return;
    _lastPage = page;
    _lastCount = count;
    setState(() {});
  }

  void _captureControllerState() {
    final ready = widget.controller.isReady;
    _lastPage = ready ? _currentPage : null;
    _lastCount = ready ? widget.controller.pageCount : null;
  }

  /// ה-notifier מדויק יותר מה-controller ולכן קודם לו; לפני העמוד הראשון שדווח
  /// עדיין אין לו ערך.
  int? get _currentPage =>
      widget.pageNumberNotifier?.value ?? widget.controller.pageNumber;

  void _handleSubmitted(String value) {
    final page = int.tryParse(value);
    if (page != null) {
      final target = page.clamp(1, widget.controller.pageCount);
      final navigate = widget.onNavigateToPage;
      if (navigate != null) {
        navigate(target);
      } else {
        widget.controller.goToPage(pageNumber: target);
      }
    }
    setState(() {
      _isEditing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.isReady) {
      return SizedBox.shrink();
    }

    final pageNumber = _currentPage ?? 1;
    final pageCount = widget.controller.pageCount;

    return Center(
      child: _isEditing
          ? SizedBox(
              width: 65,
              child: RtlTextField(
                controller: _textController,
                focusNode: _focusNode,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: AppTopBar.titleStyle(context),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 0,
                  ),
                  isDense: true,
                  hintText: '1-$pageCount',
                ),
                onSubmitted: _handleSubmitted,
              ),
            )
          : ActionButton.ghost(
              tooltip: 'הזן מספר דף',
              text: '$pageNumber/$pageCount',
              onPressed: () {
                setState(() {
                  _isEditing = true;
                  _textController.text = pageNumber.toString();
                });
                // Ensure the text is selected when editing starts
                Future.delayed(const Duration(milliseconds: 50), () {
                  _focusNode.requestFocus();
                  _textController.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: _textController.text.length,
                  );
                });
              },
            ),
    );
  }
}
