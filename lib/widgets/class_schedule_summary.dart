import 'package:flutter/material.dart';

import '../models/recurring_schedule.dart';
import '../theme/app_theme.dart';

const _short = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// A class schedule's subjects, one line each with the days and times it
/// meets: "Systems Analysis 1 · 3 units" over "Mon 8:00 AM - 11:00 AM ·
/// Online". Used wherever a schedule is shown to be read or compared.
class ClassScheduleSummary extends StatelessWidget {
  final List<RecurringScheduleRule> subjects;

  /// Subjects to mark as new or changed, by name (lowercase), when
  /// comparing with the schedule before.
  final Set<String> highlight;

  const ClassScheduleSummary({
    super.key,
    required this.subjects,
    this.highlight = const {},
  });

  /// The subjects, grouped by name, each group's meetings by day and time.
  static List<
    ({String title, String units, List<RecurringScheduleRule> meetings})
  >
  grouped(List<RecurringScheduleRule> subjects) {
    final groups =
        <
          String,
          ({String title, String units, List<RecurringScheduleRule> meetings})
        >{};
    for (final s in subjects) {
      final key = s.label.trim().toLowerCase();
      final group = groups.putIfAbsent(
        key,
        () => (title: s.label.trim(), units: s.units, meetings: []),
      );
      group.meetings.add(s);
      if (group.units.isEmpty && s.units.isNotEmpty) {
        groups[key] = (
          title: group.title,
          units: s.units,
          meetings: group.meetings,
        );
      }
    }
    for (final g in groups.values) {
      g.meetings.sort(
        (a, b) => a.weekday != b.weekday
            ? a.weekday.compareTo(b.weekday)
            : (a.startTime.hour * 60 + a.startTime.minute).compareTo(
                b.startTime.hour * 60 + b.startTime.minute,
              ),
      );
    }
    final list = groups.values.toList()
      ..sort((a, b) {
        final x = a.meetings.first;
        final y = b.meetings.first;
        return x.weekday != y.weekday
            ? x.weekday.compareTo(y.weekday)
            : (x.startTime.hour * 60 + x.startTime.minute).compareTo(
                y.startTime.hour * 60 + y.startTime.minute,
              );
      });
    return list;
  }

  /// "Mon 8:00 AM - 11:00 AM · Online" / "Thu 1:30 PM - 3:30 PM · CL5".
  static String meetingText(RecurringScheduleRule m) => [
    '${_short[m.weekday - 1]} ${m.timeRange}',
    if (m.mode == 'Online') 'Online',
    if (m.room.isNotEmpty) m.room,
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    if (subjects.isEmpty) {
      return const Text(
        'No classes.',
        style: TextStyle(fontSize: 12, color: AppTheme.slate500),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in grouped(subjects))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 34,
                  margin: const EdgeInsets.only(top: 2, right: 10),
                  decoration: BoxDecoration(
                    color: g.meetings.first.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: g.title),
                            if (g.units.isNotEmpty)
                              TextSpan(
                                text: ' · ${g.units} units',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.slate500,
                                ),
                              ),
                            if (highlight.contains(g.title.toLowerCase()))
                              const TextSpan(
                                text: '  New or changed',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.blue500,
                                ),
                              ),
                          ],
                        ),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slate800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      for (final m in g.meetings)
                        Text(
                          meetingText(m),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.slate600,
                            height: 1.4,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Names (lowercase) of subjects in [next] that are new or meet at other
  /// times than in [before].
  static Set<String> changedSubjects(
    List<RecurringScheduleRule> before,
    List<RecurringScheduleRule> next,
  ) {
    String sig(RecurringScheduleRule m) =>
        '${m.weekday}|${m.timeRange}|${m.mode}';
    Map<String, Set<String>> index(List<RecurringScheduleRule> list) {
      final out = <String, Set<String>>{};
      for (final m in list) {
        (out[m.label.trim().toLowerCase()] ??= {}).add(sig(m));
      }
      return out;
    }

    final a = index(before);
    final b = index(next);
    return {
      for (final e in b.entries)
        if (a[e.key] == null ||
            a[e.key]!.length != e.value.length ||
            !a[e.key]!.containsAll(e.value))
          e.key,
    };
  }
}
