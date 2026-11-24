import 'aether.dart';

String notesForVersion(String notes, List<int> version) {
  final heading = '## ${version.join('.')}';
  final lines = <String>[];
  var matching = false;
  for (final line in notes.split(RegExp(r'\r?\n'))) {
    if (line.startsWith('## ')) {
      if (matching) break;
      matching = line == heading;
    } else if (matching) {
      lines.add(line);
    }
  }
  return lines.join('\n').trim();
}

bool shouldShowReleaseNotes(
  List<int> current,
  String? lastSeen,
  bool hadSettings,
) {
  final previous = Aether.parseVersion(lastSeen);
  return previous == null ? hadSettings : Aether.isNewer(current, previous);
}
