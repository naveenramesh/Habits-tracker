import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
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

  // Close the notification straight away; everything else happens behind the scenes.
  final n = Notifier.instance;
  await n._initPlugin();
  final shownId = r.id;
  if (shownId != null) await n._plugin.cancel(shownId);

  final h = await Db.instance.habit(habitId);
  if (h == null) return;
  await n.init();
  await Db.instance.loadCategories();

  final today = dateOnly(DateTime.now());
  final stop = action == 'stop';
  final repostId = shownId ?? (habitId * 1000 + 999);

  if (action == 'done') {
    await Db.instance.setEntry(habitId, today, 1);
  } else if (action == 'add') {
    final raw = (r.input ?? '').trim();
    final v = double.tryParse(raw.replaceAll(',', '.'));
    if (v == null) {
      // Nothing saved: show the notification again with a hint.
      await n.repost(
          h, repostId, raw.isEmpty ? 'Enter a number to add.' : '"$raw" is not a number. Use digits only.');
      return;
    }
    await Db.instance.addToEntry(habitId, today, v);
  } else if (action == 'note') {
    final text = (r.input ?? '').trim();
    if (text.isEmpty) {
      await n.repost(h, repostId, 'Type a note first.');
      return;
    }
    await Db.instance.appendNote(habitId, today, text);
  } else if (stop) {
    await Db.instance.setPausedUntil(habitId, DateTime(today.year, today.month, today.day + 1));
  } else {
    return;
  }

  if (stop || await isGoalMet(h)) {
    await n.syncReminders(h); // pauses the remaining notifications for today / the period
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
        color: h.color,
      ),
    );
  }

  bool _pluginReady = false;

  /// Quick part of the setup: enough to cancel or show notifications.
  Future<void> _initPlugin() async {
    if (_pluginReady) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );
    _pluginReady = true;
  }

  Future<void> init() async {
    if (_ready) return;
    await _initPlugin();
    tz.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Falls back to UTC; notification times may be off if this fails.
    }
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

  /// Notification title: category first, then the habit name.
  String _title(Habit h) => h.categoryName.isEmpty ? h.name : '${h.categoryName} · ${h.name}';

  /// Short confirmation that disappears by itself after a few seconds.
  Future<void> feedback(Habit h, String msg, {int? replaceId}) async {
    await init();
    await _plugin.show(replaceId ?? (h.id! * 1000 + 999), _title(h), msg, _feedbackDetails,
        payload: '${h.id}');
  }

  /// Shows the reminder again (with buttons) with a hint, e.g. after bad input.
  Future<void> repost(Habit h, int id, String body) async {
    await init();
    await _plugin.show(id, _title(h), body, _detailsFor(h), payload: '${h.id}');
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

  static const int _maxAlarms = 100;
  DateTime? _lastSyncAll;

  static const NotificationDetails _noticeDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'habit_reminders',
      'Habit reminders',
      channelDescription: 'Reminders for your habits',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  /// Minutes after midnight at which the habit reminds on a matching day.
  List<int> _minutesOfDay(Habit h) {
    final start = h.remHour * 60 + h.remMinute;
    if (h.remType != ReminderType.interval) return [start];
    final end = h.remEndHour * 60 + h.remEndMinute;
    final step = h.remInterval < 1 ? 1 : h.remInterval;
    final out = <int>[];
    for (var m = start; m <= end && out.length < _maxAlarms; m += step) {
      out.add(m);
    }
    return out;
  }

  bool _matchesDay(Habit h, DateTime d) {
    switch (h.remType) {
      case ReminderType.weekly:
        return h.remDays.contains(d.weekday);
      case ReminderType.monthly:
        return h.remDays.isNotEmpty && d.day == h.remDays.first;
      default:
        return true;
    }
  }

  /// Schedules the habit's upcoming reminders as individual one-time alarms
  /// (the plugin's repeating alarms ignore the start date, so they can't be
  /// paused). [resumeOn] skips every day before it. The list is refreshed
  /// whenever the app opens or you log something; if nothing refreshes it, a
  /// last notification asks you to open the app.
  Future<void> scheduleFor(Habit h, {DateTime? resumeOn}) async {
    await init();
    await Db.instance.loadCategories();
    final id = h.id!;
    await cancelFor(id);
    if (h.remType == ReminderType.none) return;

    final now = tz.TZDateTime.now(tz.local);
    var firstDay = tz.TZDateTime(tz.local, now.year, now.month, now.day);
    if (resumeOn != null) {
      final r = tz.TZDateTime(tz.local, resumeOn.year, resumeOn.month, resumeOn.day);
      if (r.isAfter(firstDay)) firstDay = r;
    }
    final horizonDays = h.remType == ReminderType.monthly
        ? 366
        : (h.remType == ReminderType.weekly ? 70 : (h.remType == ReminderType.daily ? 30 : 14));
    final times = _minutesOfDay(h);
    // Exact alarms keep notifications on time. If Android refuses them, fall back to inexact ones.
    var mode = AndroidScheduleMode.exactAllowWhileIdle;
    final title = _title(h);
    final body = h.customText.isEmpty ? 'Time to check in' : h.customText;

    Future<void> put(int notifId, String ttl, String text, tz.TZDateTime when, NotificationDetails details) async {
      try {
        await _plugin.zonedSchedule(notifId, ttl, text, when, details,
            payload: '$id', androidScheduleMode: mode);
      } on PlatformException {
        mode = AndroidScheduleMode.inexactAllowWhileIdle;
        await _plugin.zonedSchedule(notifId, ttl, text, when, details,
            payload: '$id', androidScheduleMode: mode);
      }
    }

    final base = id * 1000;
    var slot = 0;
    tz.TZDateTime? last;

    for (var i = 0; i < horizonDays && slot < _maxAlarms; i++) {
      final day = tz.TZDateTime(tz.local, firstDay.year, firstDay.month, firstDay.day + i);
      if (!_matchesDay(h, day)) continue;
      for (final m in times) {
        if (slot >= _maxAlarms) break;
        final t = tz.TZDateTime(tz.local, day.year, day.month, day.day, m ~/ 60, m % 60);
        if (!t.isAfter(now)) continue;
        await put(base + slot, title, body, t, _detailsFor(h));
        slot++;
        last = t;
      }
    }

    if (last != null) {
      await put(
        base + 998,
        'Habits',
        'Open the app to keep "${h.name}" notifications going.',
        last.add(const Duration(minutes: 1)),
        _noticeDetails,
      );
    }
  }

  /// Re-schedules one habit, honouring "Stop today" and a reached goal.
  Future<void> syncReminders(Habit h) async {
    final id = h.id!;
    if (h.remType == ReminderType.none) {
      await cancelFor(id);
      return;
    }
    DateTime? resume = (await isGoalMet(h)) ? resumeDate(h) : null;
    final paused = await Db.instance.pausedUntil(id);
    if (paused != null && (resume == null || paused.isAfter(resume))) resume = paused;
    await scheduleFor(h, resumeOn: resume);
  }

  Future<void> syncAll(List<Habit> habits, {bool force = false}) async {
    final last = _lastSyncAll;
    if (!force && last != null && DateTime.now().difference(last).inMinutes < 10) return;
    _lastSyncAll = DateTime.now();
    for (final h in habits) {
      await syncReminders(h);
    }
  }
}
