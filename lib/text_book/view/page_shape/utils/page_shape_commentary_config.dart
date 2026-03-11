enum PageShapeCommentaryMode {
  single,
  multiple,
}

class PageShapeSlotConfiguration {
  final PageShapeCommentaryMode mode;
  final List<String> commentators;

  const PageShapeSlotConfiguration({
    required this.mode,
    required this.commentators,
  });

  const PageShapeSlotConfiguration.empty()
      : mode = PageShapeCommentaryMode.single,
        commentators = const [];

  bool get isEmpty => commentators.isEmpty;

  String? get primaryCommentator =>
      commentators.isEmpty ? null : commentators.first;

  PageShapeSlotConfiguration copyWith({
    PageShapeCommentaryMode? mode,
    List<String>? commentators,
  }) {
    return PageShapeSlotConfiguration(
      mode: mode ?? this.mode,
      commentators: commentators ?? this.commentators,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mode': mode.name,
      'commentators': commentators,
    };
  }

  factory PageShapeSlotConfiguration.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const PageShapeSlotConfiguration.empty();
    }

    final rawCommentators = json['commentators'];
    final commentators = rawCommentators is List
        ? rawCommentators
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .toList()
        : <String>[];
    final modeName = json['mode'] as String?;
    final mode = modeName == PageShapeCommentaryMode.multiple.name
        ? PageShapeCommentaryMode.multiple
        : PageShapeCommentaryMode.single;

    final effectiveMode = commentators.length > 1
        ? PageShapeCommentaryMode.multiple
        : (commentators.isEmpty ? PageShapeCommentaryMode.single : mode);

    return PageShapeSlotConfiguration(
      mode: effectiveMode,
      commentators: commentators,
    );
  }

  factory PageShapeSlotConfiguration.fromLegacyValue(String? commentator) {
    if (commentator == null || commentator.isEmpty) {
      return const PageShapeSlotConfiguration.empty();
    }

    return PageShapeSlotConfiguration(
      mode: PageShapeCommentaryMode.single,
      commentators: [commentator],
    );
  }
}

class PageShapeConfiguration {
  final PageShapeSlotConfiguration left;
  final PageShapeSlotConfiguration right;
  final PageShapeSlotConfiguration bottom;
  final PageShapeSlotConfiguration bottomRight;

  const PageShapeConfiguration({
    required this.left,
    required this.right,
    required this.bottom,
    required this.bottomRight,
  });

  const PageShapeConfiguration.empty()
      : left = const PageShapeSlotConfiguration.empty(),
        right = const PageShapeSlotConfiguration.empty(),
        bottom = const PageShapeSlotConfiguration.empty(),
        bottomRight = const PageShapeSlotConfiguration.empty();

  PageShapeSlotConfiguration slotFor(String key) {
    switch (key) {
      case 'left':
        return left;
      case 'right':
        return right;
      case 'bottom':
        return bottom;
      case 'bottomRight':
        return bottomRight;
      default:
        return const PageShapeSlotConfiguration.empty();
    }
  }

  String? operator [](String key) => slotFor(key).primaryCommentator;

  Iterable<MapEntry<String, String?>> get entries => {
        'left': left.primaryCommentator,
        'right': right.primaryCommentator,
        'bottom': bottom.primaryCommentator,
        'bottomRight': bottomRight.primaryCommentator,
      }.entries;

  Map<String, String?> toLegacyMap() {
    return {
      'left': left.primaryCommentator,
      'right': right.primaryCommentator,
      'bottom': bottom.primaryCommentator,
      'bottomRight': bottomRight.primaryCommentator,
    };
  }

  PageShapeConfiguration copyWith({
    PageShapeSlotConfiguration? left,
    PageShapeSlotConfiguration? right,
    PageShapeSlotConfiguration? bottom,
    PageShapeSlotConfiguration? bottomRight,
  }) {
    return PageShapeConfiguration(
      left: left ?? this.left,
      right: right ?? this.right,
      bottom: bottom ?? this.bottom,
      bottomRight: bottomRight ?? this.bottomRight,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': 2,
      'left': left.toJson(),
      'right': right.toJson(),
      'bottom': bottom.toJson(),
      'bottomRight': bottomRight.toJson(),
    };
  }

  factory PageShapeConfiguration.fromJson(Map<String, dynamic> json) {
    return PageShapeConfiguration(
      left: PageShapeSlotConfiguration.fromJson(
        json['left'] as Map<String, dynamic>?,
      ),
      right: PageShapeSlotConfiguration.fromJson(
        json['right'] as Map<String, dynamic>?,
      ),
      bottom: PageShapeSlotConfiguration.fromJson(
        json['bottom'] as Map<String, dynamic>?,
      ),
      bottomRight: PageShapeSlotConfiguration.fromJson(
        json['bottomRight'] as Map<String, dynamic>?,
      ),
    );
  }

  factory PageShapeConfiguration.fromLegacyMap(Map<String, String?> legacy) {
    return PageShapeConfiguration(
      left: PageShapeSlotConfiguration.fromLegacyValue(legacy['left']),
      right: PageShapeSlotConfiguration.fromLegacyValue(legacy['right']),
      bottom: PageShapeSlotConfiguration.fromLegacyValue(legacy['bottom']),
      bottomRight:
          PageShapeSlotConfiguration.fromLegacyValue(legacy['bottomRight']),
    );
  }
}
