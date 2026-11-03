import 'package:flutter/material.dart';

import 'aether.dart';

// Every checked item steps one place up (-1) or down (+1) past an unchecked neighbour;
// checked ones keep their own order.
void moveChecked(List<int> items, Set<int> on, int delta) {
  final n = items.length;
  for (var k = 0; k < n; k++) {
    final i = delta < 0 ? k : n - 1 - k, j = i + delta;
    if (j < 0 || j >= n || !on.contains(items[i]) || on.contains(items[j])) {
      continue;
    }
    items.insert(j, items.removeAt(i));
  }
}

// Which protocols Auto tries, top first. The app keeps this order current after each connect;
// the user may drag or uncheck any of them. Pops the checked preset indexes on Save.
class AutoOrderPage extends StatefulWidget {
  const AutoOrderPage({super.key, required this.order, required this.ranking});
  final List<int> order; // what Auto uses now
  final List<int> ranking; // the plain speed ranking, for Reset
  @override
  State<AutoOrderPage> createState() => _AutoOrderPageState();
}

class _AutoOrderPageState extends State<AutoOrderPage> {
  late List<int> _items;
  late Set<int> _on;

  @override
  void initState() {
    super.initState();
    _fill(widget.order);
  }

  // The given order checked, then every other preset unchecked (fast ones first).
  void _fill(List<int> first) {
    _on = {...first};
    _items = [
      ...first,
      for (final manualOnly in [false, true])
        for (final (i, p) in Aether.presets.indexed)
          if (p.manualOnly == manualOnly && !_on.contains(i)) i,
    ];
  }

  void _save() {
    final order = [
      for (final i in _items)
        if (_on.contains(i)) i,
    ];
    if (order.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check at least one protocol for Auto.')),
      );
      return;
    }
    Navigator.pop(context, order);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Auto order'),
      actions: [
        IconButton(
          tooltip: 'Move checked up',
          icon: const Icon(Icons.arrow_upward_rounded),
          onPressed: () => setState(() => moveChecked(_items, _on, -1)),
        ),
        IconButton(
          tooltip: 'Move checked down',
          icon: const Icon(Icons.arrow_downward_rounded),
          onPressed: () => setState(() => moveChecked(_items, _on, 1)),
        ),
        TextButton(
          onPressed: () => setState(() => _fill(widget.ranking)),
          child: const Text('Reset'),
        ),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    ),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Text(
            'Auto tries the checked protocols from the top. After each try the app moves that '
            'protocol by its speed (to the bottom if it failed); your own moves stay otherwise. '
            'Drag the handle to reorder, or use the arrows to move all checked protocols one step. '
            'Reset restores the speed ranking.',
            style: TextStyle(fontSize: 13),
          ),
        ),
        Expanded(
          child: ReorderableListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            onReorderItem: (from, to) =>
                setState(() => _items.insert(to, _items.removeAt(from))),
            children: [
              for (final i in _items)
                CheckboxListTile(
                  key: ValueKey(i),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(Aether.presets[i].label),
                  value: _on.contains(i),
                  onChanged: (v) =>
                      setState(() => v == true ? _on.add(i) : _on.remove(i)),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
