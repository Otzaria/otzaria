// core/src/commonMain/dart/io/github/kdroidfilter/seforimlibrary/core/models/link.dart

/// Types of connections between texts
enum ConnectionType {
  commentary,
  targum,
  reference,
  source,
  other;

  /// Creates a ConnectionType from a string value.
  ///
  /// The string is compared in a case-insensitive manner.
  /// Returns [ConnectionType.other] if the value is not recognized.
  static ConnectionType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'COMMENTARY':
        return ConnectionType.commentary;
      case 'TARGUM':
        return ConnectionType.targum;
      case 'REFERENCE':
        return ConnectionType.reference;
      case 'SOURCE':
        return ConnectionType.source;
      default:
        return ConnectionType.other;
    }
  }

  /// Converts the enum to its JSON string representation.
  String toJson() => name;
}

/// Link between two texts (commentary, reference, etc.)
class Link {
  /// The unique identifier of the link.
  final int id;

  /// The identifier of the source book.
  final int sourceBookId;

  /// The identifier of the target book.
  final int targetBookId;

  /// The identifier of the source line.
  final int sourceLineId;

  /// The identifier of the target line.
  final int targetLineId;

  /// The type of connection between the texts.
  final ConnectionType connectionType;

  const Link({
    this.id = 0,
    required this.sourceBookId,
    required this.targetBookId,
    required this.sourceLineId,
    required this.targetLineId,
    required this.connectionType,
  });

  /// Creates a [Link] instance from a JSON map.
  factory Link.fromJson(Map<String, dynamic> json) {
    return Link(
      id: json['id'] as int? ?? 0,
      sourceBookId: json['sourceBookId'] as int,
      targetBookId: json['targetBookId'] as int,
      sourceLineId: json['sourceLineId'] as int,
      targetLineId: json['targetLineId'] as int,
      connectionType:
          ConnectionType.fromString(json['connectionType'] as String),
    );
  }

  /// Converts the [Link] instance to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourceBookId': sourceBookId,
      'targetBookId': targetBookId,
      'sourceLineId': sourceLineId,
      'targetLineId': targetLineId,
      'connectionType': connectionType.toJson(),
    };
  }

  /// Creates a copy of this Link but with the given fields replaced with the new values.
  Link copyWith({
    int? id,
    int? sourceBookId,
    int? targetBookId,
    int? sourceLineId,
    int? targetLineId,
    ConnectionType? connectionType,
  }) {
    return Link(
      id: id ?? this.id,
      sourceBookId: sourceBookId ?? this.sourceBookId,
      targetBookId: targetBookId ?? this.targetBookId,
      sourceLineId: sourceLineId ?? this.sourceLineId,
      targetLineId: targetLineId ?? this.targetLineId,
      connectionType: connectionType ?? this.connectionType,
    );
  }

  @override
  String toString() {
    return 'Link(id: $id, sourceBookId: $sourceBookId, targetBookId: $targetBookId, sourceLineId: $sourceLineId, targetLineId: $targetLineId, connectionType: $connectionType)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Link &&
        other.id == id &&
        other.sourceBookId == sourceBookId &&
        other.targetBookId == targetBookId &&
        other.sourceLineId == sourceLineId &&
        other.targetLineId == targetLineId &&
        other.connectionType == connectionType;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        sourceBookId.hashCode ^
        targetBookId.hashCode ^
        sourceLineId.hashCode ^
        targetLineId.hashCode ^
        connectionType.hashCode;
  }
}
