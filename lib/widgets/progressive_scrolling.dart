import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';

import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class ProgressiveScroll extends StatefulWidget {
  final Widget child;
  final ScrollOffsetController scrollController;
  final double maxSpeed;
  final double accelerationFactor;
  final double curve;
  final FocusNode? focusNode;

  const ProgressiveScroll({
    super.key,
    required this.child,
    required this.scrollController,
    this.maxSpeed = 5000.0,
    this.accelerationFactor = 0.1,
    this.curve = 2.0,
    this.focusNode,
  });

  @override
  State<ProgressiveScroll> createState() => _ProgressiveScrollState();
}

class _ProgressiveScrollState extends State<ProgressiveScroll> {
  double _scrollSpeed = 0;
  bool _isKeyPressed = false;
  int _scrollDirection = 0; // 1 for down, -1 for up, 0 for no scroll
  double _timePressedInSeconds = 0;
  late final FocusNode _focusNode;
  bool _isLocalFocusNode = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _focusNode = FocusNode();
      _isLocalFocusNode = true;
    } else {
      _focusNode = widget.focusNode!;
    }
    _startScrolling();
  }

  @override
  void dispose() {
    if (_isLocalFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _startScrolling() {
    Future.delayed(const Duration(milliseconds: 16), () {
      if (_isKeyPressed) {
        _timePressedInSeconds += 0.016; // 16 milliseconds in seconds
        double t = _timePressedInSeconds;
        double curvedT = exp(widget.curve * t);
        _scrollSpeed = (curvedT * widget.accelerationFactor * _scrollDirection)
            .clamp(-widget.maxSpeed, widget.maxSpeed);
        //debugPrint('scroll speed: $_scrollSpeed');
      } else {
        _scrollSpeed = 0;
        _timePressedInSeconds = 0;
      }

      if (_scrollSpeed != 0) {
        widget.scrollController.animateScroll(
          offset: _scrollSpeed,
          duration: const Duration(milliseconds: 16),
        );
      }

      if (mounted) {
        _startScrolling();
      }
    });
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _isKeyPressed = true;
        _scrollDirection = 1;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _isKeyPressed = true;
        _scrollDirection = -1;
      }
    } else if (event is KeyUpEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
          event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _isKeyPressed = false;
        widget.scrollController.animateScroll(
          offset: 100.0 * _scrollDirection,
          duration: const Duration(milliseconds: 150),
        );
        _scrollDirection = 0;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: widget.child,
    );
  }
}
