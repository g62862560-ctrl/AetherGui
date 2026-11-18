/// Common requests, not a live server inventory (same list as the C# GUI).
class PsiphonCountry {
  final String code;
  final String name;
  const PsiphonCountry(this.code, this.name);

  String get label => code.isEmpty
      ? '🌐 Automatic'
      : '${String.fromCharCodes(code.codeUnits.map((c) => 0x1F1E6 + c - 65))} $name ($code)';
}

const psiphonCountries = [
  PsiphonCountry('', 'Automatic'),
  PsiphonCountry('AT', 'Austria'),
  PsiphonCountry('BE', 'Belgium'),
  PsiphonCountry('CA', 'Canada'),
  PsiphonCountry('CH', 'Switzerland'),
  PsiphonCountry('CZ', 'Czechia'),
  PsiphonCountry('DE', 'Germany'),
  PsiphonCountry('DK', 'Denmark'),
  PsiphonCountry('ES', 'Spain'),
  PsiphonCountry('FI', 'Finland'),
  PsiphonCountry('FR', 'France'),
  PsiphonCountry('GB', 'United Kingdom'),
  PsiphonCountry('HU', 'Hungary'),
  PsiphonCountry('IE', 'Ireland'),
  PsiphonCountry('IN', 'India'),
  PsiphonCountry('IT', 'Italy'),
  PsiphonCountry('JP', 'Japan'),
  PsiphonCountry('NL', 'Netherlands'),
  PsiphonCountry('NO', 'Norway'),
  PsiphonCountry('PL', 'Poland'),
  PsiphonCountry('RO', 'Romania'),
  PsiphonCountry('RS', 'Serbia'),
  PsiphonCountry('SE', 'Sweden'),
  PsiphonCountry('SG', 'Singapore'),
  PsiphonCountry('SK', 'Slovakia'),
  PsiphonCountry('US', 'United States'),
];
