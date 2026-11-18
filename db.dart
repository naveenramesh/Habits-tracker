import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class Db {
  Db._();
  static final Db instance = Db._();

  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'habits.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: (d, v) async {
        await d.execute(
            'CREATE TABLE habits(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, type INTEGER NOT NULL, frequency INTEGER NOT NULL, target REAL NOT NULL, unit TEXT NOT NULL, days TEXT NOT NULL, rem_type INTEGER NOT NULL DEFAULT 0, rem_hour INTEGER NOT NULL DEFAULT 8, rem_minute INTEGER NOT NULL DEFAULT 0, rem_interval INTEGER NOT NULL DEFAULT 25, rem_days TEXT NOT NULL DEFAULT \'\', rem_end_hour INTEGER NOT NULL DEFAULT 22, rem_end_minute INTEGER NOT NULL DEFAULT 0)');
        await d.execute(
            'CREATE TABLE entries(habit_id INTEGER NOT NULL, date TEXT NOT NULL, value REAL NOT NULL, note TEXT NOT NULL DEFAULT \'\', PRIMARY KEY(habit_id, date))');
      },
      onUpgrade: (d, oldV, newV) async {
        if (oldV < 2) {
          await d.execute('ALTER TABLE habits ADD COLUMN rem_type INTEGER NOT NULL DEFAULT 0');
          await d.execute('ALTER TABLE habits ADD COLUMN rem_hour INTEGER NOT NULL DEFAULT 8');
          await d.execute('ALTER TABLE habits ADD COLUMN rem_minute INTEGER NOT NULL DEFAULT 0');
          await d.execute('ALTER TABLE habits ADD COLUMN rem_interval INTEGER NOT NULL DEFAULT 25');
          await d.execute("ALTER TABLE habits ADD COLUMN rem_days TEXT NOT NULL DEFAULT ''");
        }
        if (oldV < 3) {
          await d.execute('ALTER TABLE habits ADD COLUMN rem_end_hour INTEGER NOT NULL DEFAULT 22');
          await d.execute('ALTER TABLE habits ADD COLUMN rem_end_minute INTEGER NOT NULL DEFAULT 0');
          await d.execute("ALTER TABLE entries ADD COLUMN note TEXT NOT NULL DEFAULT ''");
        }
      },
    );
  }

  Future<List<Habit>> habits() async {
    final d = await db;
    final rows = await d.query('habits', orderBy: 'id');
    return rows.map(Habit.fromMap).toList();
  }

  /// Saves the habit and returns its id.
  Future<int> saveHabit(Habit h) async {
    final d = await db;
    if (h.id == null) {
      return d.insert('habits', h.toMap());
    }
    await d.update('habits', h.toMap(), where: 'id = ?', whereArgs: [h.id]);
    return h.id!;
  }

  Future<void> deleteHabit(int id) async {
    final d = await db;
    await d.delete('entries', where: 'habit_id = ?', whereArgs: [id]);
    await d.delete('habits', where: 'id = ?', whereArgs: [id]);
  }

  /// Returns date key (yyyy-MM-dd) -> logged value for the given range.
  Future<Map<String, double>> entries(int habitId, DateTime from, DateTime to) async {
    final d = await db;
    final rows = await d.query(
      'entries',
      where: 'habit_id = ? AND date >= ? AND date <= ?',
      whereArgs: [habitId, dateKey(from), dateKey(to)],
    );
    return {
      for (final r in rows) r['date'] as String: (r['value'] as num).toDouble()
    };
  }

  Future<Habit?> habit(int id) async {
    final d = await db;
    final rows = await d.query('habits', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Habit.fromMap(rows.first);
  }

  Future<double?> entryValue(int habitId, DateTime day) async {
    final d = await db;
    final rows = await d.query('entries',
        columns: ['value'],
        where: 'habit_id = ? AND date = ?',
        whereArgs: [habitId, dateKey(day)]);
    return rows.isEmpty ? null : (rows.first['value'] as num).toDouble();
  }

  /// Number habits: adds to the day's existing total.
  Future<void> addToEntry(int habitId, DateTime day, double delta) async {
    final cur = await entryValue(habitId, day) ?? 0;
    final sum = double.parse((cur + delta).toStringAsFixed(6));
    await setEntry(habitId, day, sum);
  }

  Future<String> noteFor(int habitId, DateTime day) async {
    final d = await db;
    final rows = await d.query('entries',
        columns: ['note'],
        where: 'habit_id = ? AND date = ?',
        whereArgs: [habitId, dateKey(day)]);
    return rows.isEmpty ? '' : ((rows.first['note'] as String?) ?? '');
  }

  /// Text habits: replaces the whole note (empty text clears the day).
  Future<void> setNote(int habitId, DateTime day, String note) async {
    final text = note.trim();
    if (text.isEmpty) {
      await setEntry(habitId, day, null);
      return;
    }
    final d = await db;
    final key = dateKey(day);
    final n = await d.update('entries', {'value': 1, 'note': text},
        where: 'habit_id = ? AND date = ?', whereArgs: [habitId, key]);
    if (n == 0) {
      await d.insert('entries', {'habit_id': habitId, 'date': key, 'value': 1, 'note': text});
    }
  }

  /// Text habits: appends a new line to the day's note.
  Future<void> appendNote(int habitId, DateTime day, String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final cur = await noteFor(habitId, day);
    await setNote(habitId, day, cur.isEmpty ? t : '$cur\n$t');
  }

  /// value == null clears the entry for that day.
  Future<void> setEntry(int habitId, DateTime day, double? value) async {
    final d = await db;
    final key = dateKey(day);
    if (value == null) {
      await d.delete('entries',
          where: 'habit_id = ? AND date = ?', whereArgs: [habitId, key]);
    } else {
      await d.insert(
        'entries',
        {'habit_id': habitId, 'date': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }
}
