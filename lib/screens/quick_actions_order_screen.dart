import 'package:flutter/material.dart';
import '../models/quick_action_item.dart';
import '../widgets/app_title.dart';

class QuickActionsOrderScreen extends StatefulWidget {
  final List<QuickActionItem> items;

  const QuickActionsOrderScreen({super.key, required this.items});

  @override
  State<QuickActionsOrderScreen> createState() => _QuickActionsOrderScreenState();
}

class _QuickActionsOrderScreenState extends State<QuickActionsOrderScreen> {
  late List<QuickActionItem> _items;

  @override
  void initState() {
    super.initState();
    _items = List<QuickActionItem>.from(widget.items);
  }

  void _save() {
    final order = _items.map((e) => e.id).toList();
    Navigator.of(context).pop(order);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppTitle(subtitle: 'ترتيب الإجراءات السريعة'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('حفظ'),
          ),
        ],
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _items.length,
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (newIndex > oldIndex) newIndex -= 1;
            final item = _items.removeAt(oldIndex);
            _items.insert(newIndex, item);
          });
        },
        itemBuilder: (context, index) {
          final item = _items[index];
          return Card(
            key: ValueKey(item.id),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: item.color.withValues(alpha: 0.15),
                child: Icon(item.icon, color: item.color),
              ),
              title: Text(item.title),
              trailing: ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_handle),
              ),
            ),
          );
        },
      ),
    );
  }
}
