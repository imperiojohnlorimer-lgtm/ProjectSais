import 'package:flutter/material.dart';

/// A single schedule/calendar entry belonging to a user.
///
/// Kept deliberately flat and JSON-friendly so it can be persisted to
/// a real backend later without changing the shape the UI works with.
class ScheduleEvent {
  final String id;
  final String ownerName; // Name of the user this event belongs to
  final String title;
  final String details; // e.g. "Room 201 · 9:00 AM"
  final DateTime
  date; // Day the event falls on (time-of-day lives in `details` for now)
  final Color color;
  final IconData icon;
  final String? academicYear;

  const ScheduleEvent({
    required this.id,
    required this.ownerName,
    required this.title,
    required this.details,
    required this.date,
    required this.color,
    required this.icon,
    this.academicYear,
  });

  /// Normalized UTC day key (strips time), used for calendar lookups.
  DateTime get dayKey => DateTime.utc(date.year, date.month, date.day);

  ScheduleEvent copyWith({
    String? title,
    String? details,
    DateTime? date,
    Color? color,
    IconData? icon,
    String? academicYear,
  }) {
    return ScheduleEvent(
      id: id,
      ownerName: ownerName,
      title: title ?? this.title,
      details: details ?? this.details,
      date: date ?? this.date,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      academicYear: academicYear ?? this.academicYear,
    );
  }

  factory ScheduleEvent.fromJson(Map<String, dynamic> json) => ScheduleEvent(
    id: json['id'] as String,
    ownerName: json['ownerName'] as String,
    title: json['title'] as String,
    details: json['details'] as String,
    date: DateTime.parse(json['date'] as String),
    color: Color(json['colorValue'] as int),
    icon: _iconFromCodePoint(json['iconCodePoint'] as int),
    academicYear: json['academicYear'] as String?,
  );

  static IconData _iconFromCodePoint(int codePoint) {
    switch (codePoint) {
      case 0xe8b6:
        return Icons.search;
      case 0xe8b8:
        return Icons.settings;
      case 0xe88a:
        return Icons.home;
      case 0xe7fd:
        return Icons.person;
      case 0xe8b5:
        return Icons.add;
      case 0xe3a8:
        return Icons.event;
      default:
        return Icons.event;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'ownerName': ownerName,
    'title': title,
    'details': details,
    'date': date.toIso8601String(),
    'colorValue': color.toARGB32(),
    'iconCodePoint': icon.codePoint,
    'academicYear': academicYear,
  };
}
