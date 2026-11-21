import 'package:flutter/material.dart';

import 'categories_screen.dart';
import 'db.dart';
import 'habit_card.dart';
import 'habit_form.dart';
import 'models.dart';
import 'notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Notifier.instance.init();
  } catch (_) {}
  runApp(const HabitApp());
}

class HabitApp extends StatelessWidget {
  const HabitApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Habits',
        theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
        home: const HomeScreen(),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<Habit>? habits;
  List<Category> categories = [];
  List<HabitGroup> groups = [];
  Map<int, Set<int>> links = {};
  int? groupFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load(resync: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(resync: true); // pick up entries logged from notifications
  }

  Future<void> _load({bool resync = false, bool force = false}) async {
    final cats = await Db.instance.loadCategories(); // fills the colour lookup before cards are built
    final grps = await Db.instance.groups();
    final lnk = await Db.instance.allLinks();
    final h = await Db.instance.habits();
    if (mounted) {
      setState(() {
        categories = cats;
        groups = grps;
        links = lnk;
        habits = h;
        if (groupFilter != null && !grps.any((g) => g.id == groupFilter)) groupFilter = null;
      });
    }
    if (resync) {
      try {
        await Notifier.instance.syncAll(h, force: force); // keeps notifications current, paused if goal met
      } catch (_) {}
    }
  }

  Future<void> _open([Habit? h]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => HabitFormScreen(habit: h)),
    );
    if (changed == true) _load();
  }

  Future<void> _manage() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesScreen()));
    _load(resync: true, force: true); // category names appear in notification titles
  }

  Widget _groupChips() {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: const Text('All'),
              selected: groupFilter == null,
              onSelected: (_) => setState(() => groupFilter = null),
            ),
          ),
          for (final g in groups)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(g.name),
                selected: groupFilter == g.id,
                onSelected: (_) => setState(() => groupFilter = groupFilter == g.id ? null : g.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body(List<Habit> all) {
    final shown = groupFilter == null
        ? all
        : all.where((h) => links[h.id]?.contains(groupFilter) ?? false).toList();
    final known = categories.map((c) => c.id).toSet();
    final children = <Widget>[];

    for (final c in categories) {
      final inCat = shown.where((h) => h.categoryId == c.id).toList();
      if (inCat.isEmpty) continue;
      children.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: c.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(c.name, style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
      ));
      for (final h in inCat) {
        children.add(HabitCard(key: ObjectKey(h), habit: h, onEdit: () => _open(h)));
      }
    }
    for (final h in shown.where((h) => !known.contains(h.categoryId))) {
      children.add(HabitCard(key: ObjectKey(h), habit: h, onEdit: () => _open(h)));
    }

    return Column(
      children: [
        if (groups.isNotEmpty) _groupChips(),
        Expanded(
          child: children.isEmpty
              ? const Center(child: Text('No habits in this group.'))
              : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 88), children: children),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = habits;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Habits'),
        actions: [
          IconButton(
            icon: const Icon(Icons.category_outlined),
            tooltip: 'Categories and groups',
            onPressed: _manage,
          ),
        ],
      ),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? const Center(child: Text('No habits yet. Tap + to add one.'))
              : _body(list),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _open(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
