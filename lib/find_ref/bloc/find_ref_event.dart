import 'package:equatable/equatable.dart';

abstract class FindRefEvent extends Equatable {
  const FindRefEvent();

  @override
  List<Object> get props => [];
}

class SearchRefRequested extends FindRefEvent {
  final String refText;

  /// null = לפי ההגדרה השמורה של מתג הדיאלוג (הבלוק מכריע).
  final bool? includePersonalBooks;

  /// true רק מדיאלוג האיתור: הדירוג משתמש בהעדפות האישיות. קישור וסיור
  /// נשארים בסדר שאינו תלוי במשתמש.
  final bool personalized;

  const SearchRefRequested(
    this.refText, {
    this.includePersonalBooks,
    this.personalized = false,
  });

  @override
  List<Object> get props => [refText, ?includePersonalBooks, personalized];
}

class ClearSearchRequested extends FindRefEvent {}
