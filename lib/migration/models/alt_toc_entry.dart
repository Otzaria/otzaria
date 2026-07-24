import 'package:equatable/equatable.dart';
import 'types_helper.dart';

class AltTocEntry extends Equatable {
  final int id;
  final int structureId;
  final int? parentId;
  final int textId;
  final int level;
  final int? lineId;
  final bool isLastChild;
  final bool hasChildren;

  // Additional fields useful for UI but not directly in the main table
  // (Assuming query joins with tocText)
  final String? text;

  const AltTocEntry({
    required this.id,
    required this.structureId,
    this.parentId,
    required this.textId,
    required this.level,
    this.lineId,
    this.isLastChild = false,
    this.hasChildren = false,
    this.text,
  });

  factory AltTocEntry.fromJson(Map<String, dynamic> json) {
    return AltTocEntry(
      id: json['id'] as int,
      structureId: json['structureId'] as int,
      parentId: json['parentId'] as int?,
      textId: json['textId'] as int,
      level: json['level'] as int,
      lineId: json['lineId'] as int?,
      isLastChild: safeBoolFromJson(json['isLastChild'], false),
      hasChildren: safeBoolFromJson(json['hasChildren'], false),
      text: json['text'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'structureId': structureId,
      'parentId': parentId,
      'textId': textId,
      'level': level,
      'lineId': lineId,
      'isLastChild': isLastChild,
      'hasChildren': hasChildren,
      if (text != null) 'text': text,
    };
  }

  @override
  List<Object?> get props => [
    id,
    structureId,
    parentId,
    textId,
    level,
    lineId,
    isLastChild,
    hasChildren,
    text,
  ];
}
