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

  const SearchRefRequested(this.refText, {this.includePersonalBooks});

  @override
  List<Object> get props => [refText, ?includePersonalBooks];
}

class ClearSearchRequested extends FindRefEvent {}
