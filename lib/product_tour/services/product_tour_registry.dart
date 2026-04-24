import 'package:flutter/material.dart';
import 'package:otzaria/product_tour/models/product_tour_models.dart';

/// רישום מרכזי של יעדי הסיור על המסך.
class ProductTourRegistry {
  ProductTourRegistry._();

  static final ProductTourRegistry instance = ProductTourRegistry._();

  final Map<TourTargetId, GlobalKey> _targetKeys = <TourTargetId, GlobalKey>{};

  /// מחזיר מפתח יציב עבור יעד מסוים.
  GlobalKey keyFor(TourTargetId targetId) {
    return _targetKeys.putIfAbsent(targetId, GlobalKey.new);
  }

  /// מנסה לחשב את המיקום הגלובלי של יעד הסיור.
  Rect? rectFor(TourTargetId targetId) {
    final key = _targetKeys[targetId];
    final context = key?.currentContext;
    if (context == null) {
      return null;
    }

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) {
      return null;
    }

    final offset = renderObject.localToGlobal(Offset.zero);
    return offset & renderObject.size;
  }
}
