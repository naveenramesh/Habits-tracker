import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'db.dart';
import 'models.dart';

/// Bumped whenever a notification action changes data, so open screens reload.
final ValueNotifier<int> dataChanged = ValueNotifier<int>(0);

/// Total for today (daily habits) or for the current period (period habits).
Future<double> progressTotal(Habit h) async {
  final now = dateOnly(DateTime.now());
  if (h.isPeriod) {
    final e = await Db.instance.entries(h.id!, h.periodStart(now), h.periodEnd(now));
    return e.values.fold<double>(0, (a, b) => a + b);
  }
  return await Db.instance.entryValue(h.id!, now) ?? 0;
}

/// True when the habit's goal is already reached (limit habits never auto-stop).
Future<bool> isGoalMet(Habit h) async {
  if (h.type == HabitType.limit || h.target <= 0) return false;
  final total = await progressTotal(h);
  if (h.isPeriod || h.type == HabitType.target) return total >= h.target;
  return total >= 1; // yes/no and text, daily
}

/// First day reminders should run again after the goal is reached.
DateTime resumeDate(Habit h) {
  final now = dateOnly(DateTime.now());
  final end = h.isPeriod ? h.periodEnd(now) : now;
  return DateTime(end.year, end.month, end.day + 1);
}

/// Handles taps on notification action buttons.
Future<void> handleNotificationResponse(NotificationResponse r) async {
  final habitId = int.tryParse(r.payload ?? '');
  final action = r.actionId;
  if (habitId == null || action == null || action.isEmpty) return; // plain tap opens the app
  final h = await Db.instance.habit(habitId);
  if (h == null) return;

  final n = Notifier.instance;
  await n.init();
  final today = dateOnly(DateTime.now());
  final shownId = r.id ?? (habitId * 1000 + 999);
  final stop = action == 'stop';
  var msg = '';

  if (action == 'done') {
    await Db.instance.setEntry(habitId, today, 1);
    msg = 'Marked done.';
  } else if (action == 'add') {
    final raw = (r.input ?? '').trim();
    final v = double.tryParse(raw.replaceAll(',', '.'));
    if (v == null) {
      await n.repost(
          h, shownId, raw.isEmpty ? 'Enter a number to add.' : '"$raw" is not a number. Use digits only.');
      return;
    }
    await Db.instance.addToEntry(habitId, today, v);
    final total = await progressTotal(h);
    final scope = h.isPeriod ? h.periodLabel : 'today';
    final cmp = h.type == HabitType.limit ? 'limit' : 'goal';
    msg = 'Added ${fmt(v)}. Total $scope: ${fmt(total)} ($cmp ${fmt(h.target)} ${h.unit}).';
  } else if (action == 'note') {
    final text = (r.input ?? '').trim();
    if (text.isEmpty) {
      await n.repost(h, shownId, 'Type a note first.');
      return;
    }
    await Db.instance.appendNote(habitId, today, text);
    msg = 'Note saved.';
  } else if (!stop) {
    return;
  }

  final met = !stop && await isGoalMet(h);
  if (stop || met) {
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    await n.scheduleFor(h, resumeOn: stop ? tomorrow : resumeDate(h)); // also clears the shown reminder
    msg = stop ? 'Reminders paused until tomorrow.' : '$msg Goal reached - reminders paused.';
    await n.feedback(h, msg);
  } else {
    await n.feedback(h, msg, replaceId: shownId); // replaces the reminder, so no buttons linger
  }
  dataChanged.value++;
}

/// Runs in a background isolate when the app isn't in the foreground.
@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse r) async {
  DartPluginRegistrant.ensureInitialized();
  await handleNotificationResponse(r);
}

class Notifier {
  Notifier._();
  static final Notifier instance = Notifier._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const NotificationDetails _feedbackDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'habit_reminders',
      'Habit reminders',
      channelDescription: 'Reminders for your habits',
      importance: Importance.high,
      priority: Priority.high,
      timeoutAfter: 8000,
    ),
  );

  NotificationDetails _detailsFor(Habit h) {
    final actions = <AndroidNotificationAction>[];
    switch (h.type) {
      case HabitType.yesNo:
        actions.add(AndroidNotificationAction('done', 'Done', cancelNotification: false));
        break;
      case HabitType.target:
      case HabitType.limit:
        actions.add(AndroidNotificationAction(
          'add',
          'Add number',
          cancelNotification: false,
          inputs: <AndroidNotificationActionInput>[
            AndroidNotificationActionInput(label: 'Number to add (${h.unit})'),
          ],
        ));
        break;
      case HabitType.text:
        actions.add(AndroidNotificationAction(
          'note',
          'Add note',
          cancelNotification: false,
          inputs: <AndroidNotificationActionInput>[
            AndroidNotificationActionInput(label: 'Type a note (text)'),
          ],
        ));
        break;
    }
    actions.add(AndroidNotificationAction('stop', 'Stop today', cancelNotification: false));
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'habit_reminders',
        'Habit reminders',
        channelDescription: 'Reminders for your habits',
        importance: Importance.high,
        priority: Priority.high,
        actions: actions,
      ),
    );
  }

  Future<void> init() async {
    if (_ready) return;
    tz.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Falls back to UTC; reminder times may be off if this fails.
    }
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );
    _ready = true;
  }

  /// Asks for the Android 13+ notification permission. True if allowed.
  Future<bool> requestPermission() async {
    try {
      await init();
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Short confirmation that disappears by itself after a few seconds.
  Future<void> feedback(Habit h, String msg, {int? replaceId}) async {
    await init();
    await _plugin.show(replaceId ?? (h.id! * 1000 + 999), h.name, msg, _feedbackDetails,
        payload: '${h.id}');
  }

  /// Shows the reminder again (with buttons) with a hint, e.g. after bad input.
  Future<void> repost(Habit h, int id, String body) async {
    await init();
    await _plugin.show(id, h.name, body, _detailsFor(h), payload: '${h.id}');
  }

  // Notification ids: habitId * 1000 + slot. Slot 999 is the confirmation message.
  Future<void> cancelFor(int habitId) async {
    await init();
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      if (p.id ~/ 1000 == habitId) await _plugin.cancel(p.id);
    }
    await _plugin.cancel(habitId * 1000 + 999);
    if (habitId < 100) {
      // ids used by earlier app versions
      for (var s = 0; s <= 7; s++) {
        await _plugin.cancel(habitId * 10 + s);
      }
    }
  }

  /// Next time matching hour:minute (and weekday / day of month) that is in the
  /// future and not before [resumeOn].
  tz.TZDateTime _next(int hour, int minute, {int? weekday, int? day, DateTime? resumeOn}) {
    final now = tz.TZDateTime.now(tz.local);
    var from = now;
    if (resumeOn != null) {
      final r = tz.TZDateTime(tz.local, resumeOn.year, resumeOn.month, resumeOn.day);
      if (r.isAfter(from)) from = r;
    }
    var t = tz.TZDateTime(tz.local, from.year, from.month, from.day, hour, minute);
    for (var i = 0; i < 400; i++) {
      final okWeekday = weekday == null || t.weekday == weekday;
      final okDay = day == null || t.day == day;
      if (okWeekday && okDay && t.isAfter(now) && !t.isBefore(from)) return t;
      t = tz.TZDateTime(tz.local, t.year, t.month, t.day + 1, hour, minute);
    }
    return t;
  }

  /// Schedules the habit's reminders. Every reminder is a repeating "at this
  /// time of day" alarm, so nothing needs the app to be opened again.
  /// [resumeOn] delays the first reminder (used to pause after the goal is met).
  Future<void> scheduleFor(Habit h, {DateTime? resumeOn}) async {
    await init();
    final id = h.id!;
    await cancelFor(id);
    if (h.remType == ReminderType.none) return;

    const mode = AndroidScheduleMode.inexactAllowWhileIdle;
    final base = id * 1000;

    Future<void> put(int slot, int hour, int minute, DateTimeComponents match,
        {int? weekday, int? day}) {
      return _plugin.zonedSchedule(
        base + slot,
        h.name,
        'Time to check in',
        _next(hour, minute, weekday: weekday, day: day, resumeOn: resumeOn),
        _detailsFor(h),
        payload: '$id',
        androidScheduleMode: mode,
        matchDateTimeComponents: match,
      );
    }

    switch (h.remType) {
      case ReminderType.none:
        return;
      case ReminderType.daily:
        await put(0, h.remHour, h.remMinute, DateTimeComponents.time);
        break;
      case ReminderType.weekly:
        for (final d in h.remDays) {
          await put(d, h.remHour, h.remMinute, DateTimeComponents.dayOfWeekAndTime, weekday: d);
        }
        break;
      case ReminderType.monthly:
        if (h.remDays.isNotEmpty) {
          await put(0, h.remHour, h.remMinute, DateTimeComponents.dayOfMonthAndTime,
              day: h.remDays.first);
        }
        break;
      case ReminderType.interval:
        {
          final start = h.remHour * 60 + h.remMinute;
          final end = h.remEndHour * 60 + h.remEndMinute;
          var slot = 0;
          for (var m = start; m <= end && slot < 200; m += h.remInterval) {
            await put(slot, m ~/ 60, m % 60, DateTimeComponents.time);
            slot++;
          }
          break;
        }
    }
  }

  /// Re-schedules one habit, paused if its goal is already reached.
  Future<void> syncReminders(Habit h) async {
    if (h.remType == ReminderType.none) return;
    final met = await isGoalMet(h);
    await scheduleFor(h, resumeOn: met ? resumeDate(h) : null);
  }

  Future<void> syncAll(List<Habit> habits) async {
    for (final h in habits) {
      await syncReminders(h);
    }
  }
}
