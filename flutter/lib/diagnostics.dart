import 'dart:io';

/// Redacts common credentials and identifiers before text reaches the UI,
/// clipboard, or a diagnostic report.
String redactDiagnostic(String input) {
  var text = input;
  text = text.replaceAllMapped(
    RegExp(
      r'\b(authorization\s*:\s*(?:bearer|basic)|bearer)\s+[^\s,;]+',
      caseSensitive: false,
    ),
    (m) => '${m.group(1)} [REDACTED]',
  );
  text = text.replaceAllMapped(
    RegExp(
      r'(password|passwd|token|secret|api[_-]?key|access[_-]?key)(\s*[=:]\s*)([^\s,;]+)',
      caseSensitive: false,
    ),
    (m) => '${m.group(1)}${m.group(2)}[REDACTED]',
  );
  text = text.replaceAllMapped(
    RegExp(r'(https?://)([^/@\s:]+):([^/@\s]+)@', caseSensitive: false),
    (m) => '${m.group(1)}[REDACTED]@',
  );
  text = text.replaceAllMapped(
    RegExp(
      r'([?&](?:token|key|secret|password)=)[^&#\s]+',
      caseSensitive: false,
    ),
    (m) => '${m.group(1)}[REDACTED]',
  );
  return text;
}

class DiagnosticLog {
  DiagnosticLog({this.maxLines = 500, this.maxLineLength = 2000});
  final int maxLines;
  final int maxLineLength;
  final List<String> _lines = [];

  List<String> get lines => List.unmodifiable(_lines);

  String add(String line) {
    var safe = redactDiagnostic(line.replaceAll('\u0000', ''));
    if (safe.length > maxLineLength) {
      safe = '${safe.substring(0, maxLineLength)}…';
    }
    _lines.add(safe);
    if (_lines.length > maxLines) {
      _lines.removeRange(0, _lines.length - maxLines);
    }
    return safe;
  }

  void clear() => _lines.clear();
}

String buildDiagnosticReport({
  required String connectionState,
  required String mode,
  required Iterable<String> lines,
  String? appVersion,
  DateTime? generatedAt,
}) => [
  'Aether local diagnostic report',
  'Generated: ${(generatedAt ?? DateTime.now()).toUtc().toIso8601String()}',
  'App version: ${redactDiagnostic(appVersion ?? 'unknown')}',
  'Connection state: ${redactDiagnostic(connectionState)}',
  'Mode: ${redactDiagnostic(mode)}',
  'Platform: ${Platform.operatingSystem}',
  '',
  'Recent activity (redacted):',
  ...lines.map(redactDiagnostic),
].join('\n');

Future<File> writeDiagnosticReport(String directory, String report) async {
  final file = File('$directory/aether-diagnostic.txt');
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(report, flush: true);
  if (await file.exists()) await file.delete();
  return temporary.rename(file.path);
}
