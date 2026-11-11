import 'package:flutter/material.dart';

import 'aether.dart';

typedef AutoOrderResult = ({List<int> order, List<int> checked});

// Which protocols Auto tries, top first. The app keeps this order current after each connect;
// the user may drag or uncheck any of them. Pops the full list order and checked indexes on Save.
class AutoOrderPage extends StatefulWidget {
  const AutoOrderPage({
    super.key,
    required this.order,
    required this.checked,
    required this.ranking,
    this.stats = const {},
  });
  final Map<int, ProtocolStat> stats; // how each protocol did on this device
  final List<int> order; // full main-list order
  final List<int> checked; // what Auto uses now
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
    _fill(widget.order, widget.checked);
  }

  void _fill(List<int> order, List<int> checked) {
    _on = {...checked};
    final items = <int>[];
    for (final i in order) {
      if (i >= 0 && i < Aether.presets.length && !items.contains(i)) {
        items.add(i);
      }
    }
    items.addAll(Aether.menuPresetIndexes.where((i) => !items.contains(i)));
    _items = items;
  }

  void _reset() {
    final auto = [...widget.ranking];
    _fill([
      ...auto,
      ...Aether.menuPresetIndexes.where((i) => !auto.contains(i)),
    ], auto);
  }

  void _save() {
    final checked = [
      for (final i in _items)
        if (_on.contains(i)) i,
    ];
    if (checked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check at least one protocol for Auto.')),
      );
      return;
    }
    Navigator.pop(context, (order: _items, checked: checked));
  }

  static String _ago(int epochSeconds) {
    final s = DateTime.now().millisecondsSinceEpoch ~/ 1000 - epochSeconds;
    if (s < 3600) return '${(s ~/ 60).clamp(1, 59)}m ago';
    if (s < 86400) return '${s ~/ 3600}h ago';
    return '${s ~/ 86400}d ago';
  }

  // Verdict first (the answer), then the numbers behind it.
  Widget _statLine(ProtocolStat st) {
    final (verdict, color) = switch (st.verdict) {
      'good' => ('Works for you', const Color(0xFF4ADE80)),
      'bad' => ('Often fails', const Color(0xFFF87171)),
      'maybe' => ('Too few tries', const Color(0xFFFBBF24)),
      _ => ('Not tried yet', Colors.grey),
    };
    final details = st.tries == 0
        ? ''
        : '${st.ok} ok · ${st.fail} failed'
              '${st.ok > 0 ? ' · avg ${(st.avgMs / 1000).toStringAsFixed(1)}s' : ''}'
              '${st.lastOk > 0 ? ' · last ok ${_ago(st.lastOk)}' : ''}';
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: verdict,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
          if (details.isNotEmpty) TextSpan(text: '\n$details'),
        ],
      ),
      style: const TextStyle(fontSize: 12),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Auto order'),
      actions: [
        TextButton(
          onPressed: () => setState(_reset),
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
            'Drag the handle to reorder. Reset restores the speed ranking.',
            style: TextStyle(fontSize: 13),
          ),
        ),
        Expanded(
          child: ReorderableListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) =>
                setState(() => _items.insert(to, _items.removeAt(from))),
            children: [
              for (final (index, i) in _items.indexed)
                CheckboxListTile(
                  key: ValueKey(i),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(Aether.presets[i].label),
                  subtitle: _statLine(widget.stats[i] ?? ProtocolStat()),
                  value: _on.contains(i),
                  onChanged: (v) =>
                      setState(() => v == true ? _on.add(i) : _on.remove(i)),
                  secondary: ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle_rounded),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
