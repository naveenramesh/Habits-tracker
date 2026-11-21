import 'package:flutter/material.dart';

import 'db.dart';
import 'models.dart';

/// Create, edit and delete categories (name + colour) and the groups inside them.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  List<Category> categories = [];
  List<HabitGroup> groups = [];
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await Db.instance.loadCategories();
    final g = await Db.instance.groups();
    if (mounted) {
      setState(() {
        categories = c;
        groups = g;
        loaded = true;
      });
    }
  }

  Future<bool> _confirm(String title, String text) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _editCategory([Category? c]) async {
    final nameCtl = TextEditingController(text: c?.name ?? '');
    var colorIndex = c?.colorIndex ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(c == null ? 'New category' : 'Edit category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < habitPalette.length; i++)
                    GestureDetector(
                      onTap: () => setLocal(() => colorIndex = i),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: habitPalette[i],
                        child: colorIndex == i
                            ? const Icon(Icons.check, size: 18, color: Colors.white)
                            : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    final name = nameCtl.text.trim();
    if (ok != true || name.isEmpty) return;
    await Db.instance.saveCategory(Category(id: c?.id, name: name, colorIndex: colorIndex));
    await _load();
  }

  Future<void> _deleteCategory(Category c) async {
    final ok = await _confirm('Delete "${c.name}"?',
        'Its habits move to Basic and its groups are removed. Habit history is kept.');
    if (!ok) return;
    await Db.instance.deleteCategory(c.id!);
    await _load();
  }

  Future<void> _editGroup(Category c, [HabitGroup? g]) async {
    final nameCtl = TextEditingController(text: g?.name ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(g == null ? 'New group in ${c.name}' : 'Rename group'),
        content: TextField(
          controller: nameCtl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Group name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    final name = nameCtl.text.trim();
    if (ok != true || name.isEmpty) return;
    await Db.instance.saveGroup(HabitGroup(id: g?.id, name: name, categoryId: c.id!));
    await _load();
  }

  Future<void> _deleteGroup(HabitGroup g) async {
    final ok = await _confirm('Delete group "${g.name}"?', 'Habits stay; they just leave this group.');
    if (!ok) return;
    await Db.instance.deleteGroup(g.id!);
    await _load();
  }

  Widget _categoryCard(Category c) {
    final mine = groups.where((g) => g.categoryId == c.id).toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 8, backgroundColor: c.color),
                const SizedBox(width: 10),
                Expanded(child: Text(c.name, style: Theme.of(context).textTheme.titleMedium)),
                IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _editCategory(c)),
                if (c.id != 1)
                  IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _deleteCategory(c)),
              ],
            ),
            if (mine.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final g in mine)
                    InputChip(
                      label: Text(g.name),
                      onPressed: () => _editGroup(c, g),
                      onDeleted: () => _deleteGroup(g),
                    ),
                ],
              ),
            TextButton.icon(
              onPressed: () => _editGroup(c),
              icon: const Icon(Icons.add),
              label: const Text('Add group'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categories and groups')),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              children: [for (final c in categories) _categoryCard(c)],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editCategory(),
        icon: const Icon(Icons.add),
        label: const Text('Category'),
      ),
    );
  }
}
