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

/// Handles taps on notification action buttons (Done / Log value).
Future<void> handleNotificationResponse(NotificationResponse r) async {
  final habitId = int.tryParse(r.payload ?? '');
  if (habitId == null) return;
  final today = dateOnly(DateTime.now());
  if (r.actionId == 'done') {
    await Db.instance.setEntry(habitId, today, 1);
  } else if (r.actionId == 'log') {
    final v = double.tryParse((r.input ?? '').trim().replaceAll(',', '.'));
    if (v == null) return;
    await Db.instance.setEntry(habitId, today, v);
  } else {
    return; // plain tap on the notification just opens the app
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

  NotificationDetails _detailsFor(Habit h) {
    final actions = <AndroidNotificationAction>[
      if (h.type == HabitType.yesNo)
        AndroidNotificationAction('done', 'Done', cancelNotification: true)
      else
        AndroidNotificationAction(
          'log',
          'Log value',
          cancelNotification: true,
          inputs: <AndroidNotificationActionInput>[
            AndroidNotificationActionInput(label: "Today's value"),
          ],
        ),
    ];
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

  // Notification ids: habitId * 10 + slot (slot 0, or weekday 1..7).
  Future<void> cancelFor(int habitId) async {
    await init();
    for (var s = 0; s <= 7; s++) {
      await _plugin.cancel(habitId * 10 + s);
    }
  }

  tz.TZDateTime _next(int hour, int minute, {int? weekday, int? day}) {
    final now = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (weekday != null) {
      while (t.weekday != weekday || !t.isAfter(now)) {
        t = t.add(const Duration(days: 1));
      }
    } else if (day != null) {
      t = tz.TZDateTime(tz.local, now.year, now.month, day, hour, minute);
      if (!t.isAfter(now)) {
        t = tz.TZDateTime(tz.local, now.year, now.month + 1, day, hour, minute);
      }
    } else if (!t.isAfter(now)) {
      t = t.add(const Duration(days: 1));
    }
    return t;
  }

  Future<void> scheduleFor(Habit h) async {
    await init();
    final id = h.id!;
    await cancelFor(id);
    const mode = AndroidScheduleMode.inexactAllowWhileIdle;
    const body = 'Time to check in';

    switch (h.remType) {
      case ReminderType.none:
        return;
      case ReminderType.daily:
        await _plugin.zonedSchedule(
          id * 10,
          h.name,
          body,
          _next(h.remHour, h.remMinute),
          _detailsFor(h),
          payload: '$id',
          androidScheduleMode: mode,
          matchDateTimeComponents: DateTimeComponents.time,
        );
        break;
      case ReminderType.weekly:
        for (final d in h.remDays) {
          await _plugin.zonedSchedule(
            id * 10 + d,
            h.name,
            body,
            _next(h.remHour, h.remMinute, weekday: d),
            _detailsFor(h),
            payload: '$id',
            androidScheduleMode: mode,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          );
        }
        break;
      case ReminderType.monthly:
        if (h.remDays.isEmpty) return;
        await _plugin.zonedSchedule(
          id * 10,
          h.name,
          body,
          _next(h.remHour, h.remMinute, day: h.remDays.first),
          _detailsFor(h),
          payload: '$id',
          androidScheduleMode: mode,
          matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
        );
        break;
      case ReminderType.interval:
        await _plugin.periodicallyShowWithDuration(
          id * 10,
          h.name,
          body,
          Duration(minutes: h.remInterval),
          _detailsFor(h),
          payload: '$id',
          androidScheduleMode: mode,
        );
        break;
    }
  }
}
