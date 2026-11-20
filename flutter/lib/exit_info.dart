import 'psiphon_countries.dart';

/// One parsed aether core "exit:" line, describing the tunnel's exit hop.
///
/// Example line:
/// "[+] masque-in-masque exit: 104.28.214.161, IR via FRA, 448ms to cloudflare, warp on"
class ExitInfo {
  final String ip;
  final String countryCode;
  final String? colo;
  final int? latencyMs;
  final bool warp;

  const ExitInfo({
    required this.ip,
    required this.countryCode,
    this.colo,
    this.latencyMs,
    this.warp = false,
  });
}

/// Parses a core output line into [ExitInfo], or returns null for any other line.
ExitInfo? parseExit(String line) {
  final marker = line.indexOf(' exit: ');
  if (marker < 0) return null;

  final parts = line.substring(marker + 7).split(', ');
  if (parts.length < 2) return null;

  final ip = parts[0].trim();
  if (!_isDottedIpv4(ip)) return null;

  final countryParts = parts[1].trim().split(RegExp(r'\s+'));
  final code = countryParts.first.toUpperCase();
  if (code.length != 2 || !_isAsciiLetters(code)) return null;
  final colo = countryParts.length > 2 && countryParts[1].toLowerCase() == 'via'
      ? countryParts[2]
      : null;

  int? latencyMs;
  if (parts.length > 2) {
    final t = parts[2];
    final m = t.indexOf('ms');
    if (m > 0) latencyMs = int.tryParse(t.substring(0, m));
  }

  final warp = parts.length > 3 && parts[3].toLowerCase().contains('warp on');

  return ExitInfo(
    ip: ip,
    countryCode: code,
    colo: colo,
    latencyMs: latencyMs,
    warp: warp,
  );
}

bool _isDottedIpv4(String text) {
  final octets = text.split('.');
  if (octets.length != 4) return false;
  for (final octet in octets) {
    if (octet.isEmpty ||
        octet.length > 3 ||
        octet.codeUnits.any((c) => c < 0x30 || c > 0x39)) {
      return false;
    }
    final value = int.parse(octet);
    if (value > 255) return false;
  }
  return true;
}

bool _isAsciiLetters(String text) =>
    text.codeUnits.every((c) => (c >= 65 && c <= 90) || (c >= 97 && c <= 122));

/// Two-letter ISO code -> English name, falling back to the code when unknown.
String exitCountryName(String code) {
  for (final country in psiphonCountries) {
    if (country.code == code) return country.name;
  }
  return code;
}

/// Two-letter ISO code -> regional-indicator emoji flag.
String exitCountryFlag(String code) {
  final cc = code.toUpperCase();
  return String.fromCharCodes(cc.codeUnits.map((c) => 0x1F1E6 + c - 65));
}

/// Compact connected-state badge: only the country flag, never the exit IP.
String formatExitFlag(ExitInfo exit) => exitCountryFlag(exit.countryCode);

/// C# ShowExit's display string: "{flag} {country} · {ip}", then latency and WARP.
String formatExit(ExitInfo exit) {
  final text = StringBuffer(
    '${exitCountryFlag(exit.countryCode)} ${exitCountryName(exit.countryCode)} · ${exit.ip}',
  );
  if (exit.latencyMs != null) text.write(' · ${exit.latencyMs} ms');
  if (exit.warp) text.write(' · WARP');
  return text.toString();
}
