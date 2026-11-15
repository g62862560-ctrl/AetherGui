import 'package:flutter/material.dart';

import 'aether.dart';

enum PhoneBrand { samsung, xiaomi, huawei, oppo, vivo, stock }

class GuideStep {
  const GuideStep(this.title, this.body, {this.setting, this.button});
  final String title;
  final String body;
  final String? setting; // Aether.openSetting kind, null = nothing to open
  final String? button;
}

// Redmi, POCO, Honor, Realme, OnePlus and iQOO share their parent's settings layout.
PhoneBrand brandOf(String manufacturer, String brand) {
  final m = '$manufacturer $brand'.toLowerCase();
  bool has(List<String> names) => names.any(m.contains);
  if (has(['samsung'])) return PhoneBrand.samsung;
  if (has(['xiaomi', 'redmi', 'poco', 'blackshark'])) return PhoneBrand.xiaomi;
  if (has(['huawei', 'honor'])) return PhoneBrand.huawei;
  if (has(['oppo', 'realme', 'oneplus'])) return PhoneBrand.oppo;
  if (has(['vivo', 'iqoo'])) return PhoneBrand.vivo;
  return PhoneBrand.stock;
}

// Steps for this phone. The battery step is left out when Android says it is already done;
// everything else cannot be read back, so it is always listed.
List<GuideStep> guideFor(
  PhoneBrand brand,
  int sdk, {
  bool batteryDone = false,
}) {
  final unrestricted = sdk >= 31
      ? 'Unrestricted'
      : "Don't optimize / No restrictions";
  return [
    if (!batteryDone && sdk >= 23)
      const GuideStep(
        'Battery optimization',
        'Find Aether in the list (choose "All apps" if needed) and set it to "Don\'t optimize".',
        setting: 'battery',
        button: 'Open battery optimization',
      ),
    GuideStep(
      'App battery usage',
      'Open App info > Battery (or "App battery usage") and choose "$unrestricted".',
      setting: 'app',
      button: 'Open App info',
    ),
    ...switch (brand) {
      PhoneBrand.samsung => const [
        GuideStep(
          'Never sleeping apps',
          'Settings > Battery > Background usage limits: take Aether out of "Sleeping apps" and "Deep sleeping apps", '
              'and turn off "Put unused apps to sleep". Add Aether to "Never sleeping apps".',
          setting: 'oem',
          button: 'Open Samsung battery',
        ),
      ],
      PhoneBrand.xiaomi => const [
        GuideStep(
          'Autostart',
          'Turn on Autostart for Aether.',
          setting: 'oem',
          button: 'Open Autostart',
        ),
        GuideStep(
          'Battery saver',
          'In App info > Battery saver (or "Battery usage") choose "No restrictions". '
              'Also open Recent apps, long-press the Aether card and tap the lock icon.',
        ),
      ],
      PhoneBrand.huawei => const [
        GuideStep(
          'App launch',
          'Settings > Apps > App launch: set Aether to "Manage manually" and turn on '
              '"Auto-launch", "Secondary launch" and "Run in background".',
          setting: 'oem',
          button: 'Open App launch',
        ),
      ],
      PhoneBrand.oppo => const [
        GuideStep(
          'Auto-launch',
          'Allow Aether to auto-launch (Settings > Apps > Auto launch, or App info > "Allow auto launch").',
          setting: 'oem',
          button: 'Open Auto-launch',
        ),
        GuideStep(
          'Background activity',
          'In App info > Battery usage turn on "Allow background activity". '
              'Lock Aether in Recent apps if your phone offers it.',
        ),
      ],
      PhoneBrand.vivo => const [
        GuideStep(
          'Autostart',
          'i Manager > Apps > Autostart (or Settings > Apps > Autostart): turn on Aether.',
          setting: 'oem',
          button: 'Open Autostart',
        ),
        GuideStep(
          'Background power use',
          'Settings > Battery > Background power consumption: allow Aether to run with high consumption.',
        ),
      ],
      PhoneBrand.stock => const [
        GuideStep(
          'Adaptive battery',
          'If the VPN still drops, check Settings > Battery for Battery Saver and turn it off while connected.',
          setting: 'saver',
          button: 'Open Battery Saver',
        ),
      ],
    },
  ];
}

class BatteryGuidePage extends StatefulWidget {
  const BatteryGuidePage({super.key});
  @override
  State<BatteryGuidePage> createState() => _BatteryGuidePageState();
}

class _BatteryGuidePageState extends State<BatteryGuidePage>
    with WidgetsBindingObserver {
  List<String> _info = const [];
  bool _ignored = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from a system screen: re-check what Android lets us read.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final info = await Aether.deviceInfo();
    final ignored = await Aether.batteryIgnored();
    if (mounted) {
      setState(() {
        _info = info;
        _ignored = ignored;
        _loaded = true;
      });
    }
  }

  Future<void> _open(String kind) async {
    if (await Aether.openSetting(kind)) return;
    // No such screen on this phone: App info is the closest thing that always exists.
    final ok = kind != 'app' && await Aether.openSetting('app');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open it here. Search Settings for the name.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sdk = int.tryParse(_info.length > 2 ? _info[2] : '') ?? 0;
    final brand = _info.length > 1
        ? brandOf(_info[0], _info[1])
        : PhoneBrand.stock;
    final steps = guideFor(brand, sdk, batteryDone: _ignored);
    final name = _info.length > 3
        ? '${_info[0]} · Android ${_info[3]}'
        : 'this phone';
    return Scaffold(
      appBar: AppBar(title: const Text('Background running')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              children: [
                Text('Steps for $name'),
                if (_ignored)
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.check_circle_rounded,
                      color: Colors.green,
                    ),
                    title: Text(
                      'Battery optimization is already off for Aether',
                    ),
                  ),
                for (final (i, s) in steps.indexed)
                  Card(
                    margin: const EdgeInsets.only(top: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${i + 1}. ${s.title}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Text(s.body),
                          if (s.setting != null)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => _open(s.setting!),
                                child: Text(s.button ?? 'Open'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'Only the battery optimization step can be checked by the app; the others cannot be '
                  'detected, so they are always shown. Menu names differ between phone models and '
                  'versions. These settings help, but Android or your phone maker may still stop '
                  'apps in the background, so a stable connection is not guaranteed.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
    );
  }
}
