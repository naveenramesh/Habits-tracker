import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(); // pick up entries logged from notifications
  }

  Future<void> _load() async {
    final h = await Db.instance.habits();
    if (mounted) setState(() => habits = h);
  }

  Future<void> _open([Habit? h]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => HabitFormScreen(habit: h)),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = habits;
    return Scaffold(
      appBar: AppBar(title: const Text('Habits')),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? const Center(child: Text('No habits yet. Tap + to add one.'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  children: [
                    for (final h in list)
                      HabitCard(key: ObjectKey(h), habit: h, onEdit: () => _open(h)),
                  ],
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _open(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
