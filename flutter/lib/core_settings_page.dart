import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'aether.dart';
import 'core_options.dart';
import 'localization.dart';

class CoreSettingsPage extends StatefulWidget {
  final CoreOptions options;
  const CoreSettingsPage({super.key, required this.options});
  @override
  State<CoreSettingsPage> createState() => _CoreSettingsPageState();
}

class _CoreSettingsPageState extends State<CoreSettingsPage> {
  late final _arguments = TextEditingController(
    text: widget.options.argumentsJson,
  );
  late final _environment = TextEditingController(
    text: widget.options.environmentJson,
  );
  late final _timeout = TextEditingController(
    text: '${widget.options.startupSeconds}',
  );
  String? _error;
  String? _help;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadHelp();
  }

  Future<void> _loadHelp() async {
    Process? process;
    try {
      process = await Process.start(
        Aether.exe,
        ['--help'],
        workingDirectory: Aether.dir,
        environment: {'HOME': Aether.dir},
      );
      final output = await Future.wait([
        process.stdout.transform(utf8.decoder).join(),
        process.stderr.transform(utf8.decoder).join(),
      ]).timeout(const Duration(seconds: 10));
      if (mounted) setState(() => _help = output.join('\n'));
    } catch (_) {
      if (mounted) setState(() => _help = '');
    } finally {
      process?.kill();
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final options = CoreOptions.parse(
        _arguments.text,
        _environment.text,
        _timeout.text,
      );
      final saved = options.saveAdvanced(Aether.dir);
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is FormatException
              ? e.message
              : context.l10n.text('saveSettingsFailed'),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _arguments.dispose();
    _environment.dispose();
    _timeout.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.l10n.text('coreSettings')),
      actions: [
        TextButton(
          onPressed: _saving ? null : _save,
          child: Text(context.l10n.text('save')),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(context.l10n.text('coreExpertIntro')),
              const SizedBox(height: 12),
              Text(context.l10n.text('coreManagedIntro')),
              const SizedBox(height: 12),
              Text(context.l10n.text('coreSensitiveWarning')),
              const SizedBox(height: 16),
              TextField(
                controller: _arguments,
                minLines: 4,
                maxLines: 12,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: context.l10n.text('additionalArguments'),
                  helperText:
                      'Example: ["--scan", "balanced", "--noize", "gfw", "--stats"]',
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _environment,
                minLines: 3,
                maxLines: 10,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: context.l10n.text('environmentJson'),
                  helperText: 'Example: {"AETHER_ROUTE_SNIFF_MS": "600"}',
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _timeout,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: context.l10n.text('startupTimeout'),
                  helperText: context.l10n.text('startupTimeoutHelp'),
                  helperMaxLines: 3,
                ),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _saving
                    ? null
                    : () {
                        _arguments.text = '[]';
                        _environment.text = '{}';
                        _timeout.text = '300';
                      },
                child: Text(context.l10n.text('resetFields')),
              ),
              ExpansionTile(
                title: Text(context.l10n.text('featureExamples')),
                children: [
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: SelectableText(
                      'Scan/noise: --scan balanced, --noize gfw\n'
                      'MASQUE: --h2, --fragment, --ech auto\n'
                      'Peers: --peer, --wiw-outer, --wiw-inner, --mim-outer, --mim-inner\n'
                      'Network: --dual, --dns, --upstream, --route-block, --route-direct\n'
                      'Tor: --tor-bridges, --tor-bridge, --tor-relays\n'
                      'Psiphon: --psiphon-mode, --psiphon-region, --psiphon-cdn-ips\n'
                      'Zero Trust: --team with --access-token, --access-id/--access-secret, or --access-email\n'
                      'Send emailed codes via Core input on the home page.\n'
                      'Tuning: --keepalive, --startup-secs, --reconnect-secs, --perf, --log-level\n'
                      'Check bundled help: flags vary by version. IP flags select core endpoints, not Android VPN address families.',
                    ),
                  ),
                ],
              ),
              ExpansionTile(
                title: Text(context.l10n.text('bundledCoreHelp')),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      _help == null
                          ? context.l10n.text('loadingCoreHelp')
                          : _help!.isEmpty
                          ? context.l10n.text('coreHelpFailed')
                          : _help!,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
