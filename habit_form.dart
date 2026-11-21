import 'package:flutter/material.dart';

import 'categories_screen.dart';
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
  late int remEndHour;
  late int remEndMinute;
  late int categoryId;
  late Set<int> groupIds;
  late final TextEditingController customText;
  List<Category> categories = [Category(id: 1, name: 'Basic', colorIndex: 1)];
  List<HabitGroup> allGroups = [];
  bool metaReady = false;
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
    remEndHour = h?.remEndHour ?? 22;
    remEndMinute = h?.remEndMinute ?? 0;
    categoryId = h?.categoryId ?? 1;
    groupIds = <int>{};
    customText = TextEditingController(text: h?.customText ?? '');
    _loadMeta();
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
    customText.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    try {
      final cats = await Db.instance.loadCategories();
      final grps = await Db.instance.groups();
      final h = widget.habit;
      final linked = (h == null || metaReady) ? null : await Db.instance.groupIdsFor(h.id!);
      if (!mounted) return;
      setState(() {
        if (cats.isNotEmpty) categories = cats;
        allGroups = grps;
        if (linked != null) groupIds = linked;
        if (!categories.any((c) => c.id == categoryId)) categoryId = categories.first.id!;
        groupIds.removeWhere((id) => !grps.any((g) => g.id == id));
        metaReady = true;
      });
    } catch (_) {
      if (mounted) setState(() => metaReady = true);
    }
  }

  Future<void> _manageCategories() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesScreen()));
    await _loadMeta();
  }

  /// Creates a group inside the currently selected category and selects it.
  Future<void> _newGroup() async {
    final ctl = TextEditingController();
    final catName =
        categories.firstWhere((c) => c.id == categoryId, orElse: () => categories.first).name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('New group in $catName'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Group name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    final name = ctl.text.trim();
    if (ok != true || name.isEmpty) return;
    final gid = await Db.instance.saveGroup(HabitGroup(name: name, categoryId: categoryId));
    await _loadMeta();
    if (mounted) setState(() => groupIds.add(gid));
  }

  bool get _needsTarget =>
      (type != HabitType.yesNo && type != HabitType.text) || isPeriodFreq(freq);

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
      if (remDays.isEmpty) return _snack('Pick at least one notification day');
      rDays = remDays.toList()..sort();
    } else if (remType == ReminderType.monthly) {
      final day = int.tryParse(remDay.text.trim());
      if (day == null || day < 1 || day > 28) return _snack('Notification day must be 1-28');
      rDays = [day];
    } else if (remType == ReminderType.interval) {
      final m = int.tryParse(remInterval.text.trim());
      if (m == null || m < 1) return _snack('Interval must be at least 1 minute');
      final startMin = remHour * 60 + remMinute;
      final endMin = remEndHour * 60 + remEndMinute;
      if (endMin <= startMin) return _snack('"Until" must be later than "From"');
      if ((endMin - startMin) ~/ m + 1 > 120) {
        return _snack('Too many notifications in that window. Use a longer interval or a shorter window.');
      }
      rInterval = m;
    }

    final h = Habit(
      id: widget.habit?.id,
      name: n,
      type: type,
      frequency: freq,
      target: t,
      unit: (type == HabitType.yesNo || type == HabitType.text) ? 'times' : unit.text.trim(),
      days: pickDays ? (days.toList()..sort()) : <int>[],
      remType: remType,
      remHour: remHour,
      remMinute: remMinute,
      remEndHour: remEndHour,
      remEndMinute: remEndMinute,
      categoryId: categoryId,
      customText: customText.text.trim(),
      remInterval: rInterval,
      remDays: rDays,
    );
    final id = await Db.instance.saveHabit(h);
    await Db.instance.setHabitGroups(id, groupIds);
    if (remType != ReminderType.none) {
      final ok = await Notifier.instance.requestPermission();
      if (!ok && mounted) _snack('Notifications are blocked. Enable them in Android settings.');
    }
    await Notifier.instance.syncReminders(h.withId(id));
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

  Future<void> _pickTime({bool end = false}) async {
    final t = await showTimePicker(
      context: context,
      initialTime: end
          ? TimeOfDay(hour: remEndHour, minute: remEndMinute)
          : TimeOfDay(hour: remHour, minute: remMinute),
    );
    if (t != null) {
      setState(() {
        if (end) {
          remEndHour = t.hour;
          remEndMinute = t.minute;
        } else {
          remHour = t.hour;
          remMinute = t.minute;
        }
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
          _dropdown<int>('Category', categoryId, {for (final c in categories) c.id!: c.name},
              (v) => setState(() => categoryId = v)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _manageCategories,
              icon: const Icon(Icons.palette_outlined, size: 18),
              label: const Text('Manage categories and colours'),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          const Text('Groups'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final g in allGroups)
                FilterChip(
                  label: Text(
                      '${categories.firstWhere((c) => c.id == g.categoryId, orElse: () => categories.first).name} > ${g.name}'),
                  selected: groupIds.contains(g.id),
                  onSelected: (sel) => setState(() => sel ? groupIds.add(g.id!) : groupIds.remove(g.id!)),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('New group'),
                onPressed: _newGroup,
              ),
            ],
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
                labelText: (type == HabitType.yesNo || type == HabitType.text)
                    ? 'Times per period'
                    : (type == HabitType.target ? 'Target (number)' : 'Limit (number)'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          if (type == HabitType.target || type == HabitType.limit) ...[
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
          _dropdown<ReminderType>(
              'Notifications setup', remType, reminderNames, (v) => setState(() => remType = v)),
          if (remType != ReminderType.none) ...[
            const SizedBox(height: 12),
            TextField(
              controller: customText,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Custom message (optional)',
                hintText: 'e.g. Rock on, steps counter!',
                border: OutlineInputBorder(),
              ),
            ),
          ],
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickTime(),
                    icon: const Icon(Icons.access_time),
                    label: Text('From ${TimeOfDay(hour: remHour, minute: remMinute).format(context)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickTime(end: true),
                    icon: const Icon(Icons.access_time),
                    label: Text('Until ${TimeOfDay(hour: remEndHour, minute: remEndMinute).format(context)}'),
                  ),
                ),
              ],
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
