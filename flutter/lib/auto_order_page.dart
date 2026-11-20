import 'package:flutter/material.dart';

import 'aether.dart';
import 'localization.dart';

typedef AutoOrderResult = ({List<int> order, List<int> checked});

String _format(BuildContext context, String key, String name, Object value) =>
    context.l10n.text(key).replaceAll('{$name}', '$value');

String _ago(BuildContext context, int epochSeconds) {
  final s = DateTime.now().millisecondsSinceEpoch ~/ 1000 - epochSeconds;
  if (s < 60) return context.l10n.text('justNow');
  if (s < 3600) return _format(context, 'minutesAgo', 'count', s ~/ 60);
  if (s < 86400) return _format(context, 'hoursAgo', 'count', s ~/ 3600);
  return _format(context, 'daysAgo', 'count', s ~/ 86400);
}

// Verdict first (the answer), then the numbers behind it; used in this list and on Home once connected.
Widget protocolStatLine(ProtocolStat st, {double fontSize = 12}) => Builder(
  builder: (context) {
    final (verdict, color) = switch (st.verdict) {
      'good' => (context.l10n.text('worksForYou'), const Color(0xFF4ADE80)),
      'bad' => (context.l10n.text('oftenFails'), const Color(0xFFF87171)),
      'maybe' => (context.l10n.text('tooFewTries'), const Color(0xFFFBBF24)),
      _ => (context.l10n.text('notTriedYet'), Colors.grey),
    };
    const green = Color(0xFF4ADE80),
        red = Color(0xFFF87171),
        amber = Color(0xFFFBBF24),
        muted = Color(0xFFA9A4B8);
    // Each number carries its own meaning color: ok green, failures red, success rate and speed by thresholds.
    TextSpan part(String text, Color c) => TextSpan(
      text: text,
      style: TextStyle(color: c, fontWeight: FontWeight.w600),
    );
    const dot = TextSpan(
      text: ' · ',
      style: TextStyle(color: muted),
    );
    final rate = st.tries == 0 ? 0 : st.ok * 100 ~/ st.tries;
    final avg = st.avgMs / 1000;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: verdict,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
          if (st.tries > 0) ...[
            const TextSpan(text: '\n'),
            part(
              _format(context, 'okCount', 'count', st.ok),
              st.ok > 0 ? green : muted,
            ),
            dot,
            part(
              _format(context, 'failedCount', 'count', st.fail),
              st.fail > 0 ? red : muted,
            ),
            dot,
            part(
              _format(context, 'successRate', 'rate', rate),
              rate >= 60
                  ? green
                  : rate >= 30
                  ? amber
                  : red,
            ),
            if (st.ok > 0) ...[
              dot,
              part(
                _format(
                  context,
                  'averageSeconds',
                  'seconds',
                  avg.toStringAsFixed(1),
                ),
                avg < 5
                    ? green
                    : avg < 15
                    ? amber
                    : red,
              ),
            ],
            if (st.lastOk > 0)
              TextSpan(
                text:
                    ' · ${_format(context, 'lastOk', 'ago', _ago(context, st.lastOk))}',
                style: const TextStyle(color: muted),
              ),
          ],
        ],
      ),
      style: TextStyle(fontSize: fontSize),
    );
  },
);

// Which protocols Auto tries, top first. The app keeps this order current after each connect;
// the user may drag or uncheck any of them. Pops the full list order and checked indexes on Save.
class AutoOrderPage extends StatefulWidget {
  const AutoOrderPage({
    super.key,
    required this.order,
    required this.checked,
    required this.ranking,
    this.stats = const {},
    this.onChanged,
  });
  // Called on every edit so the main list follows at once, not only on Save.
  final void Function(AutoOrderResult)? onChanged;
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

  List<int> get _checked => [
    for (final i in _items)
      if (_on.contains(i)) i,
  ];

  void _notify() {
    final checked = _checked;
    if (checked.isNotEmpty) {
      widget.onChanged?.call((order: [..._items], checked: checked));
    }
  }

  void _save() {
    final checked = _checked;
    if (checked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('autoOrderEmpty'))),
      );
      return;
    }
    Navigator.pop(context, (order: _items, checked: checked));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.l10n.text('autoOrder')),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            _reset();
            _notify();
          }),
          child: Text(context.l10n.text('reset')),
        ),
        TextButton(onPressed: _save, child: Text(context.l10n.text('save'))),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Text(
            context.l10n.text('autoOrderHelp'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        Expanded(
          child: ReorderableListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) => setState(() {
              _items.insert(to, _items.removeAt(from));
              _notify();
            }),
            children: [
              for (final (index, i) in _items.indexed)
                CheckboxListTile(
                  key: ValueKey(i),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(Aether.presets[i].label),
                  subtitle: protocolStatLine(widget.stats[i] ?? ProtocolStat()),
                  value: _on.contains(i),
                  onChanged: (v) => setState(() {
                    v == true ? _on.add(i) : _on.remove(i);
                    _notify();
                  }),
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
