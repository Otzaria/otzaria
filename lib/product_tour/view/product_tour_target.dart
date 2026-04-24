import 'package:flutter/material.dart';
import 'package:otzaria/product_tour/models/product_tour_models.dart';
import 'package:otzaria/product_tour/services/product_tour_registry.dart';

/// עוגן ויזואלי שמאפשר לסיור להיצמד לאלמנט ספציפי.
class ProductTourTarget extends StatelessWidget {
  final TourTargetId targetId;
  final Widget child;

  const ProductTourTarget({
    super.key,
    required this.targetId,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ProductTourRegistry.instance.keyFor(targetId),
      child: child,
    );
  }
}
