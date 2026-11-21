import 'dart:ui' show Color;

enum HabitType { yesNo, target, limit, text }

/// One colour per habit (red is left out: it marks "over the limit").
const habitPalette = <Color>[
  Color(0xFF2E7D32), // green
  Color(0xFF1565C0), // blue
  Color(0xFFEF6C00), // orange
  Color(0xFF6A1B9A), // purple
  Color(0xFF00838F), // teal
  Color(0xFFAD1457), // pink
  Color(0xFF3949AB), // indigo
  Color(0xFFF9A825), // amber
  Color(0xFF6D4C41), // brown
  Color(0xFF827717), // olive
];

enum Frequency { daily, weekdays, monthDays, weekly, monthly, quarterly, yearly }

enum ReminderType { none, daily, weekly, monthly, interval }

const reminderNames = {
  ReminderType.none: 'Off',
  ReminderType.daily: 'Every day at a time',
  ReminderType.weekly: 'Selected days of week at a time',
  ReminderType.monthly: 'Monthly on a day',
  ReminderType.interval: 'Repeat every N minutes (between two times)',
};

const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

const typeNames = {
  HabitType.yesNo: 'Yes / No',
  HabitType.target: 'Number target (more is better)',
  HabitType.limit: 'Number limit (less is better)',
  HabitType.text: 'Text note',
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

  /// Reminder settings. remDays = weekdays (weekly) or [day of month] (monthly).
  final ReminderType remType;
  final int remHour;
  final int remMinute;
  final int remInterval; // minutes, for interval reminders
  final List<int> remDays;
  final int remEndHour; // interval reminders run from remHour:remMinute until this time
  final int remEndMinute;

  /// Index into habitPalette; -1 means pick one automatically from the id.
  final int colorIndex;

  /// Category (maps to the habit's colour) and optional custom notification text.
  final int categoryId;
  final String customText;

  Habit({
    this.id,
    required this.name,
    required this.type,
    required this.frequency,
    required this.target,
    required this.unit,
    required this.days,
    this.remType = ReminderType.none,
    this.remHour = 8,
    this.remMinute = 0,
    this.remInterval = 25,
    this.remDays = const [],
    this.remEndHour = 22,
    this.remEndMinute = 0,
    this.colorIndex = -1,
    this.categoryId = 1,
    this.customText = '',
  });

  Habit withId(int newId) => Habit(
        id: newId,
        name: name,
        type: type,
        frequency: frequency,
        target: target,
        unit: unit,
        days: days,
        remType: remType,
        remHour: remHour,
        remMinute: remMinute,
        remInterval: remInterval,
        remDays: remDays,
        remEndHour: remEndHour,
        remEndMinute: remEndMinute,
        colorIndex: colorIndex,
        categoryId: categoryId,
        customText: customText,
      );

  String get reminderText {
    final hh = remHour.toString().padLeft(2, '0');
    final mm = remMinute.toString().padLeft(2, '0');
    final eh = remEndHour.toString().padLeft(2, '0');
    final em = remEndMinute.toString().padLeft(2, '0');
    switch (remType) {
      case ReminderType.none:
        return '';
      case ReminderType.daily:
        return 'Daily at $hh:$mm';
      case ReminderType.weekly:
        final names = remDays.map((d) => weekdayNames[d - 1]).join(', ');
        return '$names at $hh:$mm';
      case ReminderType.monthly:
        final day = remDays.isEmpty ? '' : '${remDays.first}';
        return 'Day $day of month at $hh:$mm';
      case ReminderType.interval:
        return 'Every $remInterval min, $hh:$mm-$eh:$em';
    }
  }

  bool get isPeriod => isPeriodFreq(frequency);

  Color get color => categoryRegistry[categoryId]?.color ?? habitPalette[0];

  String get categoryName => categoryRegistry[categoryId]?.name ?? '';

  bool get isNumeric => type == HabitType.target || type == HabitType.limit;

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'name': name,
        'type': type.index,
        'frequency': frequency.index,
        'target': target,
        'unit': unit,
        'days': days.join(','),
        'rem_type': remType.index,
        'rem_hour': remHour,
        'rem_minute': remMinute,
        'rem_interval': remInterval,
        'rem_days': remDays.join(','),
        'rem_end_hour': remEndHour,
        'rem_end_minute': remEndMinute,
        'color_index': colorIndex,
        'category_id': categoryId,
        'custom_text': customText,
      };

  factory Habit.fromMap(Map<String, Object?> m) {
    final raw = m['days'] as String;
    final remRaw = (m['rem_days'] as String?) ?? '';
    return Habit(
      remType: ReminderType.values[(m['rem_type'] as int?) ?? 0],
      remHour: (m['rem_hour'] as int?) ?? 8,
      remMinute: (m['rem_minute'] as int?) ?? 0,
      remInterval: (m['rem_interval'] as int?) ?? 25,
      remEndHour: (m['rem_end_hour'] as int?) ?? 22,
      remEndMinute: (m['rem_end_minute'] as int?) ?? 0,
      colorIndex: (m['color_index'] as int?) ?? -1,
      categoryId: (m['category_id'] as int?) ?? 1,
      customText: (m['custom_text'] as String?) ?? '',
      remDays: remRaw.isEmpty ? <int>[] : remRaw.split(',').map(int.parse).toList(),
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
      case HabitType.text:
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
    if (type == HabitType.text) {
      what = isPeriod ? '${fmt(target)} days with a note' : 'Text note';
    } else if (type == HabitType.yesNo) {
      what = isPeriod ? '${fmt(target)} times' : 'Yes / No';
    } else if (type == HabitType.target) {
      what = 'at least ${fmt(target)} $unit';
    } else {
      what = 'at most ${fmt(target)} $unit';
    }
    return '$freqText · $what';
  }
}

/// A category has a name and a colour; every habit belongs to one category.
class Category {
  final int? id;
  final String name;
  final int colorIndex;

  Category({this.id, required this.name, required this.colorIndex});

  Color get color => habitPalette[colorIndex % habitPalette.length];

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'name': name,
        'color_index': colorIndex,
      };

  factory Category.fromMap(Map<String, Object?> m) => Category(
        id: m['id'] as int?,
        name: m['name'] as String,
        colorIndex: m['color_index'] as int,
      );
}

/// A group lives inside a category; a habit can be in several groups.
class HabitGroup {
  final int? id;
  final String name;
  final int categoryId;

  HabitGroup({this.id, required this.name, required this.categoryId});

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'name': name,
        'category_id': categoryId,
      };

  factory HabitGroup.fromMap(Map<String, Object?> m) => HabitGroup(
        id: m['id'] as int?,
        name: m['name'] as String,
        categoryId: m['category_id'] as int,
      );
}

/// Filled by Db.loadCategories(); lets Habit.color / Habit.categoryName look up
/// their category without a database call.
final Map<int, Category> categoryRegistry = <int, Category>{};
