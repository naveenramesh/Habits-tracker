import 'package:flutter/material.dart';

import 'db.dart';
import 'models.dart';
import 'notifications.dart';

Color scoreColor(double? s) {
  if (s == null) return Colors.grey.shade100;
  if (s <= 0) return Colors.grey.shade300;
  if (s < 50) return Colors.green.shade100;
  if (s < 100) return Colors.green.shade300;
  if (s < 100.0001) return Colors.green.shade600;
  return Colors.green.shade900; // above 100%
}

class HabitCard extends StatefulWidget {
  final Habit habit;
  final VoidCallback onEdit;

  const HabitCard({super.key, required this.habit, required this.onEdit});

  @override
  State<HabitCard> createState() => _HabitCardState();
}

class _HabitCardState extends State<HabitCard> {
  static const weeks = 15;
  Map<String, double> entries = {};
  bool expanded = false;

  DateTime get gridStart {
    final t = dateOnly(DateTime.now());
    final monday = DateTime(t.year, t.month, t.day - (t.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day - 7 * (weeks - 1));
  }

  @override
  void initState() {
    super.initState();
    dataChanged.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    dataChanged.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final h = widget.habit;
    final now = dateOnly(DateTime.now());
    final from = h.isPeriod ? h.periodStart(now) : gridStart;
    final to = h.isPeriod ? h.periodEnd(now) : now;
    final e = await Db.instance.entries(h.id!, from, to);
    if (mounted) setState(() => entries = e);
  }

  Future<void> _log(DateTime day) async {
    final h = widget.habit;
    final cur = entries[dateKey(day)];
    if (h.type == HabitType.yesNo) {
      await Db.instance.setEntry(h.id!, day, cur == null ? 1 : null);
    } else {
      final ctl = TextEditingController(text: cur == null ? '' : fmt(cur));
      final res = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('${h.name} · ${dateKey(day)}'),
          content: TextField(
            controller: ctl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(suffixText: h.unit),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, ''), child: const Text('Clear')),
            TextButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('Save')),
          ],
        ),
      );
      if (res == null) return;
      await Db.instance.setEntry(h.id!, day, double.tryParse(res.trim()));
    }
    await _load();
  }

  Widget _cell(Color color) => Container(
        width: 16,
        height: 16,
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      );

  Widget _heatmap() {
    final h = widget.habit;
    final today = dateOnly(DateTime.now());
    final start = gridStart;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        children: List.generate(weeks, (w) {
          return Column(
            children: List.generate(7, (r) {
              final d = DateTime(start.year, start.month, start.day + w * 7 + r);
              if (d.isAfter(today)) return _cell(Colors.transparent);
              final score = h.dayScore(d, entries[dateKey(d)]);
              return GestureDetector(
                onTap: () => _log(d),
                child: _cell(scoreColor(score)),
              );
            }),
          );
        }),
      ),
    );
  }

  Widget _progress() {
    final h = widget.habit;
    final total = entries.values.fold<double>(0, (a, b) => a + b);
    final pct = h.target <= 0 ? 0.0 : total / h.target;
    final over = h.type == HabitType.limit && total > h.target;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: pct.clamp(0.0, 1.0).toDouble(),
          minHeight: 10,
          color: over ? Colors.red : Colors.green,
        ),
        const SizedBox(height: 4),
        Text('${fmt(total)} / ${fmt(h.target)} ${h.unit}  (${(pct * 100).round()}%)  ·  ${h.periodLabel}'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.habit;
    final today = dateOnly(DateTime.now());
    final doneToday = entries.containsKey(dateKey(today));
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: h.isPeriod ? null : () => setState(() => expanded = !expanded),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(child: Text(h.name, style: Theme.of(context).textTheme.titleMedium)),
                            if (!h.isPeriod)
                              Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 20),
                          ],
                        ),
                        Text(h.summary, style: Theme.of(context).textTheme.bodySmall),
                        if (h.remType != ReminderType.none)
                          Text('🔔 ${h.reminderText}', style: Theme.of(context).textTheme.bodySmall),
                        if (!h.isPeriod && h.type != HabitType.yesNo)
                          Text(
                            'Today: ${entries[dateKey(today)] == null ? '-' : fmt(entries[dateKey(today)]!)} ${h.unit}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(icon: const Icon(Icons.edit_outlined), onPressed: widget.onEdit),
                IconButton(
                  icon: Icon(h.type == HabitType.yesNo
                      ? (doneToday ? Icons.check_circle : Icons.radio_button_unchecked)
                      : Icons.add_circle_outline),
                  onPressed: () => _log(today),
                ),
              ],
            ),
            if (h.isPeriod || expanded) const SizedBox(height: 12),
            if (h.isPeriod) _progress() else if (expanded) _heatmap(),
          ],
        ),
      ),
    );
  }
}
