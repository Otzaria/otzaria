import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

enum RecurrenceType {
  none,
  weekly,
  monthlyHebrew,
  monthlyGregorian,
  annualHebrew,
  annualGregorian,
}

class CustomEvent extends Equatable {
  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  final DateTime baseGregorianDate;
  final int baseJewishYear;
  final int baseJewishMonth;
  final int baseJewishDay;
  final RecurrenceType recurrenceType;
  final int? recurringYears;
  final String? googleEventId;
  final TimeOfDay? eventTime;

  bool get recurring => recurrenceType != RecurrenceType.none;
  bool get recurOnHebrew =>
      recurrenceType == RecurrenceType.annualHebrew ||
      recurrenceType == RecurrenceType.monthlyHebrew;

  const CustomEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.baseGregorianDate,
    required this.baseJewishYear,
    required this.baseJewishMonth,
    required this.baseJewishDay,
    required this.recurrenceType,
    this.recurringYears,
    this.googleEventId,
    this.eventTime,
  });

  CustomEvent copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? createdAt,
    DateTime? baseGregorianDate,
    int? baseJewishYear,
    int? baseJewishMonth,
    int? baseJewishDay,
    RecurrenceType? recurrenceType,
    int? recurringYears,
    String? googleEventId,
    TimeOfDay? eventTime,
  }) {
    return CustomEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      baseGregorianDate: baseGregorianDate ?? this.baseGregorianDate,
      baseJewishYear: baseJewishYear ?? this.baseJewishYear,
      baseJewishMonth: baseJewishMonth ?? this.baseJewishMonth,
      baseJewishDay: baseJewishDay ?? this.baseJewishDay,
      recurrenceType: recurrenceType ?? this.recurrenceType,
      recurringYears: recurringYears ?? this.recurringYears,
      googleEventId: googleEventId ?? this.googleEventId,
      eventTime: eventTime ?? this.eventTime,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'baseGregorianDate': baseGregorianDate.millisecondsSinceEpoch,
      'baseJewishYear': baseJewishYear,
      'baseJewishMonth': baseJewishMonth,
      'baseJewishDay': baseJewishDay,
      'recurrenceType': recurrenceType.index,
      'recurringYears': recurringYears,
      'googleEventId': googleEventId,
      'eventTime': eventTime != null
          ? {'hour': eventTime!.hour, 'minute': eventTime!.minute}
          : null,
    };
  }

  factory CustomEvent.fromJson(Map<String, dynamic> json) {
    RecurrenceType type;
    if (json.containsKey('recurrenceType')) {
      type = RecurrenceType.values[json['recurrenceType'] as int];
    } else {
      // Backward compatibility
      final bool recurring = json['recurring'] as bool? ?? false;
      final bool recurOnHebrew = json['recurOnHebrew'] as bool? ?? true;
      if (!recurring) {
        type = RecurrenceType.none;
      } else {
        type = recurOnHebrew
            ? RecurrenceType.annualHebrew
            : RecurrenceType.annualGregorian;
      }
    }

    TimeOfDay? eventTime;
    if (json.containsKey('eventTime') && json['eventTime'] != null) {
      final timeMap = json['eventTime'] as Map<String, dynamic>;
      eventTime = TimeOfDay(
        hour: timeMap['hour'] as int,
        minute: timeMap['minute'] as int,
      );
    }

    return CustomEvent(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      baseGregorianDate:
          DateTime.fromMillisecondsSinceEpoch(json['baseGregorianDate'] as int),
      baseJewishYear: json['baseJewishYear'] as int,
      baseJewishMonth: json['baseJewishMonth'] as int,
      baseJewishDay: json['baseJewishDay'] as int,
      recurrenceType: type,
      recurringYears: json['recurringYears'] as int?,
      googleEventId: json['googleEventId'] as String?,
      eventTime: eventTime,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        createdAt,
        baseGregorianDate,
        baseJewishYear,
        baseJewishMonth,
        baseJewishDay,
        recurrenceType,
        recurringYears,
        googleEventId,
        eventTime,
      ];
}
