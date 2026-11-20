import 'package:flutter/material.dart';

import 'aether.dart';
import 'localization.dart';

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
  AppLocalizations l10n = const AppLocalizations(AppLocales.english),
}) {
  String t(String key) => l10n.text(key);
  final unrestricted = sdk >= 31
      ? 'Unrestricted'
      : "Don't optimize / No restrictions";
  final steps = <GuideStep>[
    if (!batteryDone && sdk >= 23)
      GuideStep(
        t('batteryOptimization'),
        t('batteryOptimizationBody'),
        setting: 'battery',
        button: t('openBatteryOptimization'),
      ),
    GuideStep(
      t('appBatteryUsage'),
      t('appBatteryUsageBody').replaceAll('{mode}', unrestricted),
      setting: 'app',
      button: t('openAppInfo'),
    ),
  ];
  switch (brand) {
    case PhoneBrand.samsung:
      steps.add(
        GuideStep(
          t('neverSleepingApps'),
          t('samsungBatteryBody'),
          setting: 'oem',
          button: t('openSamsungBattery'),
        ),
      );
    case PhoneBrand.xiaomi:
      steps.addAll([
        GuideStep(
          t('autostart'),
          t('autostartBody'),
          setting: 'oem',
          button: t('openAutostart'),
        ),
        GuideStep(t('batterySaver'), t('xiaomiBatteryBody')),
      ]);
    case PhoneBrand.huawei:
      steps.add(
        GuideStep(
          t('appLaunch'),
          t('huaweiLaunchBody'),
          setting: 'oem',
          button: t('openAppLaunch'),
        ),
      );
    case PhoneBrand.oppo:
      steps.addAll([
        GuideStep(
          t('autoLaunch'),
          t('oppoLaunchBody'),
          setting: 'oem',
          button: t('openAutoLaunch'),
        ),
        GuideStep(t('backgroundActivity'), t('oppoBackgroundBody')),
      ]);
    case PhoneBrand.vivo:
      steps.add(
        GuideStep(
          t('backgroundActivity'),
          t('vivoBackgroundBody'),
          setting: 'oem',
        ),
      );
    case PhoneBrand.stock:
      break;
  }
  return steps;
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
        SnackBar(content: Text(context.l10n.text('settingOpenFailed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sdk = int.tryParse(_info.length > 2 ? _info[2] : '') ?? 0;
    final brand = _info.length > 1
        ? brandOf(_info[0], _info[1])
        : PhoneBrand.stock;
    final steps = guideFor(
      brand,
      sdk,
      batteryDone: _ignored,
      l10n: context.l10n,
    );
    final name = _info.length > 3
        ? '${_info[0]} · Android ${_info[3]}'
        : context.l10n.text('thisPhone');
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.text('batteryGuideTitle'))),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              children: [
                Text(
                  context.l10n.text('stepsFor').replaceAll('{device}', name),
                ),
                if (_ignored)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.check_circle_rounded,
                      color: Colors.green,
                    ),
                    title: Text(context.l10n.text('batteryAlreadyOff')),
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
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton(
                                onPressed: () => _open(s.setting!),
                                child: Text(
                                  s.button ?? context.l10n.text('open'),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  context.l10n.text('batteryGuideNote'),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
    );
  }
}
