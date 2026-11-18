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
      version: 2,
      onCreate: (d, v) async {
        await d.execute(
            'CREATE TABLE habits(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, type INTEGER NOT NULL, frequency INTEGER NOT NULL, target REAL NOT NULL, unit TEXT NOT NULL, days TEXT NOT NULL, rem_type INTEGER NOT NULL DEFAULT 0, rem_hour INTEGER NOT NULL DEFAULT 8, rem_minute INTEGER NOT NULL DEFAULT 0, rem_interval INTEGER NOT NULL DEFAULT 25, rem_days TEXT NOT NULL DEFAULT \'\')');
        await d.execute(
            'CREATE TABLE entries(habit_id INTEGER NOT NULL, date TEXT NOT NULL, value REAL NOT NULL, PRIMARY KEY(habit_id, date))');
      },
      onUpgrade: (d, oldV, newV) async {
        if (oldV < 2) {
          await d.execute('ALTER TABLE habits ADD COLUMN rem_type INTEGER NOT NULL DEFAULT 0');
          await d.execute('ALTER TABLE habits ADD COLUMN rem_hour INTEGER NOT NULL DEFAULT 8');
          await d.execute('ALTER TABLE habits ADD COLUMN rem_minute INTEGER NOT NULL DEFAULT 0');
          await d.execute('ALTER TABLE habits ADD COLUMN rem_interval INTEGER NOT NULL DEFAULT 25');
          await d.execute("ALTER TABLE habits ADD COLUMN rem_days TEXT NOT NULL DEFAULT ''");
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
