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
      version: 5,
      onCreate: (d, v) async {
        await d.execute(
            'CREATE TABLE habits(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, type INTEGER NOT NULL, frequency INTEGER NOT NULL, target REAL NOT NULL, unit TEXT NOT NULL, days TEXT NOT NULL, rem_type INTEGER NOT NULL DEFAULT 0, rem_hour INTEGER NOT NULL DEFAULT 8, rem_minute INTEGER NOT NULL DEFAULT 0, rem_interval INTEGER NOT NULL DEFAULT 25, rem_days TEXT NOT NULL DEFAULT \'\', rem_end_hour INTEGER NOT NULL DEFAULT 22, rem_end_minute INTEGER NOT NULL DEFAULT 0, color_index INTEGER NOT NULL DEFAULT -1, category_id INTEGER NOT NULL DEFAULT 1, custom_text TEXT NOT NULL DEFAULT \'\')');
        await d.execute(
            'CREATE TABLE entries(habit_id INTEGER NOT NULL, date TEXT NOT NULL, value REAL NOT NULL, note TEXT NOT NULL DEFAULT \'\', PRIMARY KEY(habit_id, date))');
        await d.execute('CREATE TABLE reminder_state(habit_id INTEGER PRIMARY KEY, paused_until TEXT NOT NULL)');
        await _createCategoryTables(d);
        await _seedCategories(d);
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
        if (oldV < 4) {
          await d.execute('ALTER TABLE habits ADD COLUMN color_index INTEGER NOT NULL DEFAULT -1');
          await d.execute('CREATE TABLE IF NOT EXISTS reminder_state(habit_id INTEGER PRIMARY KEY, paused_until TEXT NOT NULL)');
        }
        if (oldV < 5) {
          await _createCategoryTables(d);
          await d.execute('ALTER TABLE habits ADD COLUMN category_id INTEGER NOT NULL DEFAULT 1');
          await d.execute("ALTER TABLE habits ADD COLUMN custom_text TEXT NOT NULL DEFAULT ''");
          await _seedCategories(d);
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
    await d.delete('reminder_state', where: 'habit_id = ?', whereArgs: [id]);
    await d.delete('habit_group_links', where: 'habit_id = ?', whereArgs: [id]);
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

  Future<void> _createCategoryTables(DatabaseExecutor d) async {
    await d.execute(
        'CREATE TABLE categories(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, color_index INTEGER NOT NULL)');
    await d.execute(
        'CREATE TABLE habit_groups(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, category_id INTEGER NOT NULL)');
    await d.execute(
        'CREATE TABLE habit_group_links(habit_id INTEGER NOT NULL, group_id INTEGER NOT NULL, PRIMARY KEY(habit_id, group_id))');
  }

  /// Default categories. "Basic" gets id 1 and can't be deleted.
  Future<void> _seedCategories(DatabaseExecutor d) async {
    const names = ['Basic', 'Health', 'Wealth', 'Strategy'];
    const colors = [1, 0, 7, 3];
    for (var i = 0; i < names.length; i++) {
      await d.insert('categories', {'name': names[i], 'color_index': colors[i]});
    }
  }

  /// Loads all categories and refreshes [categoryRegistry].
  Future<List<Category>> loadCategories() async {
    final d = await db;
    final rows = await d.query('categories', orderBy: 'id');
    final list = rows.map(Category.fromMap).toList();
    categoryRegistry
      ..clear()
      ..addAll({for (final c in list) c.id!: c});
    return list;
  }

  Future<int> saveCategory(Category c) async {
    final d = await db;
    if (c.id == null) return d.insert('categories', c.toMap());
    await d.update('categories', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
    return c.id!;
  }

  /// Habits in a deleted category move to Basic (id 1).
  Future<void> deleteCategory(int id) async {
    if (id == 1) return;
    final d = await db;
    final rows = await d.query('habit_groups', columns: ['id'], where: 'category_id = ?', whereArgs: [id]);
    for (final r in rows) {
      await d.delete('habit_group_links', where: 'group_id = ?', whereArgs: [r['id']]);
    }
    await d.delete('habit_groups', where: 'category_id = ?', whereArgs: [id]);
    await d.update('habits', {'category_id': 1}, where: 'category_id = ?', whereArgs: [id]);
    await d.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<HabitGroup>> groups() async {
    final d = await db;
    final rows = await d.query('habit_groups', orderBy: 'category_id, name');
    return rows.map(HabitGroup.fromMap).toList();
  }

  Future<int> saveGroup(HabitGroup g) async {
    final d = await db;
    if (g.id == null) return d.insert('habit_groups', g.toMap());
    await d.update('habit_groups', g.toMap(), where: 'id = ?', whereArgs: [g.id]);
    return g.id!;
  }

  Future<void> deleteGroup(int id) async {
    final d = await db;
    await d.delete('habit_group_links', where: 'group_id = ?', whereArgs: [id]);
    await d.delete('habit_groups', where: 'id = ?', whereArgs: [id]);
  }

  Future<Set<int>> groupIdsFor(int habitId) async {
    final d = await db;
    final rows = await d.query('habit_group_links', where: 'habit_id = ?', whereArgs: [habitId]);
    return {for (final r in rows) r['group_id'] as int};
  }

  Future<void> setHabitGroups(int habitId, Iterable<int> groupIds) async {
    final d = await db;
    await d.delete('habit_group_links', where: 'habit_id = ?', whereArgs: [habitId]);
    for (final g in groupIds) {
      await d.insert('habit_group_links', {'habit_id': habitId, 'group_id': g},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// habit id -> ids of the groups it belongs to.
  Future<Map<int, Set<int>>> allLinks() async {
    final d = await db;
    final rows = await d.query('habit_group_links');
    final out = <int, Set<int>>{};
    for (final r in rows) {
      out.putIfAbsent(r['habit_id'] as int, () => <int>{}).add(r['group_id'] as int);
    }
    return out;
  }

  /// Reminders are paused until this day (set by the "Stop today" button).
  Future<DateTime?> pausedUntil(int habitId) async {
    final d = await db;
    final rows = await d.query('reminder_state', where: 'habit_id = ?', whereArgs: [habitId]);
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['paused_until'] as String);
  }

  Future<void> setPausedUntil(int habitId, DateTime day) async {
    final d = await db;
    await d.insert('reminder_state', {'habit_id': habitId, 'paused_until': dateKey(day)},
        conflictAlgorithm: ConflictAlgorithm.replace);
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
