import 'package:flutter/material.dart';

import 'aether.dart';

typedef ProtocolOrderResult = ({List<int> order, int selected});

// Tap a protocol to select it, or drag its handle to reorder the main list.
class ProtocolOrderSheet extends StatefulWidget {
  const ProtocolOrderSheet({
    super.key,
    required this.order,
    required this.selected,
  });

  final List<int> order;
  final int selected; // -1 = Auto

  @override
  State<ProtocolOrderSheet> createState() => _ProtocolOrderSheetState();
}

class _ProtocolOrderSheetState extends State<ProtocolOrderSheet> {
  late final List<int> _order = [...widget.order];
  late int _selected = widget.selected;

  void _done() => Navigator.pop(context, (order: _order, selected: _selected));

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Protocol order',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(onPressed: _done, child: const Text('Done')),
              ],
            ),
          ),
          CheckboxListTile(
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Auto (order in Settings)'),
            value: _selected == -1,
            onChanged: (_) => setState(() => _selected = -1),
          ),
          const Divider(height: 1),
          Expanded(
            child: ReorderableListView.builder(
              padding: EdgeInsets.zero,
              buildDefaultDragHandles: false,
              itemCount: _order.length,
              onReorderItem: (from, to) =>
                  setState(() => _order.insert(to, _order.removeAt(from))),
              itemBuilder: (context, index) {
                final i = _order[index];
                final preset = Aether.presets[i];
                return CheckboxListTile(
                  key: ValueKey(i),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(preset.label),
                  value: i == _selected,
                  onChanged: (_) => setState(() => _selected = i),
                  secondary: ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle_rounded),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
