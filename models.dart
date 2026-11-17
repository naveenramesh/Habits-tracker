enum HabitType { yesNo, target, limit }

enum Frequency { daily, weekdays, monthDays, weekly, monthly, quarterly, yearly }

const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

const typeNames = {
  HabitType.yesNo: 'Yes / No',
  HabitType.target: 'Target (more is better)',
  HabitType.limit: 'Limit (less is better)',
};

const freqNames = {
  Frequency.daily: 'Daily',
  Frequency.weekdays: 'Selected days of week',
  Frequency.monthDays: 'Selected days of month',
  Frequency.weekly: 'Weekly',
  Frequency.monthly: 'Monthly',
  Frequency.quarterly: 'Quarterly',
  Frequency.yearly: 'Yearly',
};

bool isPeriodFreq(Frequency f) =>
    f == Frequency.weekly ||
    f == Frequency.monthly ||
    f == Frequency.quarterly ||
    f == Frequency.yearly;

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

class Habit {
  final int? id;
  final String name;
  final HabitType type;
  final Frequency frequency;

  /// Daily-type habits: goal (target) or cap (limit) per day. Yes/No: 1.
  /// Period habits: total goal / cap for the whole period (Yes/No = times).
  final double target;
  final String unit;

  /// Weekdays (Mon=1..Sun=7) or month days (1..31), depending on frequency.
  final List<int> days;

  Habit({
    this.id,
    required this.name,
    required this.type,
    required this.frequency,
    required this.target,
    required this.unit,
    required this.days,
  });

  bool get isPeriod => isPeriodFreq(frequency);

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'name': name,
        'type': type.index,
        'frequency': frequency.index,
        'target': target,
        'unit': unit,
        'days': days.join(','),
      };

  factory Habit.fromMap(Map<String, Object?> m) {
    final raw = m['days'] as String;
    return Habit(
      id: m['id'] as int?,
      name: m['name'] as String,
      type: HabitType.values[m['type'] as int],
      frequency: Frequency.values[m['frequency'] as int],
      target: (m['target'] as num).toDouble(),
      unit: m['unit'] as String,
      days: raw.isEmpty ? <int>[] : raw.split(',').map(int.parse).toList(),
    );
  }

  bool isScheduled(DateTime d) {
    switch (frequency) {
      case Frequency.weekdays:
        return days.contains(d.weekday);
      case Frequency.monthDays:
        return days.contains(d.day);
      default:
        return true;
    }
  }

  /// Score in percent for a single day (daily-type habits).
  /// Returns null when the day is not scheduled or has no data to judge.
  double? dayScore(DateTime d, double? value) {
    if (!isScheduled(d)) return null;
    switch (type) {
      case HabitType.yesNo:
        return (value ?? 0) >= 1 ? 100 : 0;
      case HabitType.target:
        return target <= 0 ? null : (value ?? 0) / target * 100;
      case HabitType.limit:
        if (value == null) return null;
        return value <= target ? 100 : 0;
    }
  }

  DateTime periodStart(DateTime d) {
    switch (frequency) {
      case Frequency.weekly:
        return DateTime(d.year, d.month, d.day - (d.weekday - 1));
      case Frequency.monthly:
        return DateTime(d.year, d.month, 1);
      case Frequency.quarterly:
        return DateTime(d.year, ((d.month - 1) ~/ 3) * 3 + 1, 1);
      case Frequency.yearly:
        return DateTime(d.year, 1, 1);
      default:
        return dateOnly(d);
    }
  }

  DateTime periodEnd(DateTime d) {
    switch (frequency) {
      case Frequency.weekly:
        return DateTime(d.year, d.month, d.day + (7 - d.weekday));
      case Frequency.monthly:
        return DateTime(d.year, d.month + 1, 0);
      case Frequency.quarterly:
        return DateTime(d.year, ((d.month - 1) ~/ 3) * 3 + 4, 0);
      case Frequency.yearly:
        return DateTime(d.year, 12, 31);
      default:
        return dateOnly(d);
    }
  }

  String get periodLabel {
    switch (frequency) {
      case Frequency.weekly:
        return 'this week';
      case Frequency.monthly:
        return 'this month';
      case Frequency.quarterly:
        return 'this quarter';
      case Frequency.yearly:
        return 'this year';
      default:
        return '';
    }
  }

  String get freqText {
    switch (frequency) {
      case Frequency.daily:
        return 'Daily';
      case Frequency.weekdays:
        return days.map((d) => weekdayNames[d - 1]).join(', ');
      case Frequency.monthDays:
        return 'Days ${days.join(', ')} of month';
      case Frequency.weekly:
        return 'Weekly';
      case Frequency.monthly:
        return 'Monthly';
      case Frequency.quarterly:
        return 'Quarterly';
      case Frequency.yearly:
        return 'Yearly';
    }
  }

  String get summary {
    String what;
    if (type == HabitType.yesNo) {
      what = isPeriod ? '${fmt(target)} times' : 'Yes / No';
    } else if (type == HabitType.target) {
      what = 'at least ${fmt(target)} $unit';
    } else {
      what = 'at most ${fmt(target)} $unit';
    }
    return '$freqText · $what';
  }
}
