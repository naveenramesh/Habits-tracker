import 'package:flutter/material.dart';

import 'db.dart';
import 'models.dart';
import 'notifications.dart';

class HabitFormScreen extends StatefulWidget {
  final Habit? habit;
  const HabitFormScreen({super.key, this.habit});

  @override
  State<HabitFormScreen> createState() => _HabitFormScreenState();
}

class _HabitFormScreenState extends State<HabitFormScreen> {
  late final TextEditingController name;
  late final TextEditingController target;
  late final TextEditingController unit;
  late HabitType type;
  late Frequency freq;
  late Set<int> days;
  late ReminderType remType;
  late int remHour;
  late int remMinute;
  late Set<int> remDays;
  late final TextEditingController remInterval;
  late final TextEditingController remDay;

  @override
  void initState() {
    super.initState();
    final h = widget.habit;
    name = TextEditingController(text: h?.name ?? '');
    target = TextEditingController(text: h == null || (h.type == HabitType.yesNo && !h.isPeriod) ? '' : fmt(h.target));
    unit = TextEditingController(text: h?.unit ?? '');
    type = h?.type ?? HabitType.yesNo;
    freq = h?.frequency ?? Frequency.daily;
    days = {...?h?.days};
    remType = h?.remType ?? ReminderType.none;
    remHour = h?.remHour ?? 8;
    remMinute = h?.remMinute ?? 0;
    remDays = (h != null && h.remType == ReminderType.weekly) ? h.remDays.toSet() : <int>{};
    remInterval = TextEditingController(text: '${h?.remInterval ?? 25}');
    remDay = TextEditingController(
        text: (h != null && h.remType == ReminderType.monthly && h.remDays.isNotEmpty)
            ? '${h.remDays.first}'
            : '1');
  }

  @override
  void dispose() {
    name.dispose();
    target.dispose();
    unit.dispose();
    remInterval.dispose();
    remDay.dispose();
    super.dispose();
  }

  bool get _needsTarget => type != HabitType.yesNo || isPeriodFreq(freq);

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _save() async {
    final n = name.text.trim();
    if (n.isEmpty) return _snack('Enter a name');

    double t = 1;
    if (_needsTarget) {
      final parsed = double.tryParse(target.text.trim());
      if (parsed == null || parsed < 0 || (parsed == 0 && type != HabitType.limit)) {
        return _snack('Enter a valid target');
      }
      t = parsed;
    }

    final pickDays = freq == Frequency.weekdays || freq == Frequency.monthDays;
    if (pickDays && days.isEmpty) return _snack('Pick at least one day');

    var rDays = <int>[];
    var rInterval = 25;
    if (remType == ReminderType.weekly) {
      if (remDays.isEmpty) return _snack('Pick at least one reminder day');
      rDays = remDays.toList()..sort();
    } else if (remType == ReminderType.monthly) {
      final day = int.tryParse(remDay.text.trim());
      if (day == null || day < 1 || day > 28) return _snack('Reminder day must be 1-28');
      rDays = [day];
    } else if (remType == ReminderType.interval) {
      final m = int.tryParse(remInterval.text.trim());
      if (m == null || m < 1) return _snack('Interval must be at least 1 minute');
      rInterval = m;
    }

    final h = Habit(
      id: widget.habit?.id,
      name: n,
      type: type,
      frequency: freq,
      target: t,
      unit: type == HabitType.yesNo ? 'times' : unit.text.trim(),
      days: pickDays ? (days.toList()..sort()) : <int>[],
      remType: remType,
      remHour: remHour,
      remMinute: remMinute,
      remInterval: rInterval,
      remDays: rDays,
    );
    final id = await Db.instance.saveHabit(h);
    if (remType != ReminderType.none) {
      final ok = await Notifier.instance.requestPermission();
      if (!ok && mounted) _snack('Notifications are blocked. Enable them in Android settings.');
    }
    await Notifier.instance.scheduleFor(h.withId(id));
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete habit?'),
        content: const Text('This also deletes all its history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await Notifier.instance.cancelFor(widget.habit!.id!);
    await Db.instance.deleteHabit(widget.habit!.id!);
    if (mounted) Navigator.pop(context, true);
  }

  Widget _dropdown<T>(String label, T value, Map<T, String> names, ValueChanged<T> onChanged) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: value,
          items: [
            for (final e in names.entries) DropdownMenuItem<T>(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: remHour, minute: remMinute),
    );
    if (t != null) {
      setState(() {
        remHour = t.hour;
        remMinute = t.minute;
      });
    }
  }

  Widget _dayPicker() {
    if (freq == Frequency.weekdays) {
      return Wrap(
        spacing: 6,
        children: [
          for (var i = 1; i <= 7; i++)
            FilterChip(
              label: Text(weekdayNames[i - 1]),
              selected: days.contains(i),
              onSelected: (s) => setState(() => s ? days.add(i) : days.remove(i)),
            ),
        ],
      );
    }
    if (freq == Frequency.monthDays) {
      return Wrap(
        spacing: 6,
        children: [
          for (var i = 1; i <= 31; i++)
            FilterChip(
              label: Text('$i'),
              selected: days.contains(i),
              onSelected: (s) => setState(() => s ? days.add(i) : days.remove(i)),
            ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.habit != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit habit' : 'New habit'),
        actions: [
          if (editing) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          _dropdown<HabitType>('Type', type, typeNames, (v) => setState(() => type = v)),
          const SizedBox(height: 16),
          _dropdown<Frequency>('Frequency', freq, freqNames, (v) {
            setState(() {
              freq = v;
              days.clear();
            });
          }),
          const SizedBox(height: 16),
          _dayPicker(),
          if (_needsTarget) ...[
            const SizedBox(height: 16),
            TextField(
              controller: target,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: type == HabitType.yesNo
                    ? 'Times per period'
                    : (type == HabitType.target ? 'Target' : 'Limit'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          if (type != HabitType.yesNo) ...[
            const SizedBox(height: 16),
            TextField(
              controller: unit,
              decoration: const InputDecoration(
                labelText: 'Unit (steps, hours, litres...)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          _dropdown<ReminderType>('Reminder', remType, reminderNames, (v) => setState(() => remType = v)),
          if (remType == ReminderType.weekly) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: [
                for (var i = 1; i <= 7; i++)
                  FilterChip(
                    label: Text(weekdayNames[i - 1]),
                    selected: remDays.contains(i),
                    onSelected: (s) => setState(() => s ? remDays.add(i) : remDays.remove(i)),
                  ),
              ],
            ),
          ],
          if (remType == ReminderType.monthly) ...[
            const SizedBox(height: 12),
            TextField(
              controller: remDay,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Day of month (1-28)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          if (remType == ReminderType.interval) ...[
            const SizedBox(height: 12),
            TextField(
              controller: remInterval,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Every how many minutes?',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          if (remType == ReminderType.daily ||
              remType == ReminderType.weekly ||
              remType == ReminderType.monthly) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.access_time),
              label: Text('Time: ${TimeOfDay(hour: remHour, minute: remMinute).format(context)}'),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}
