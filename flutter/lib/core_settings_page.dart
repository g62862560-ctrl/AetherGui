import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'aether.dart';
import 'core_options.dart';

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
  String _help = 'Loading bundled core help...';
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
      if (mounted) setState(() => _help = 'Could not read bundled core help.');
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
              : 'Could not save settings.',
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
      title: const Text('Core settings'),
      actions: [
        TextButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
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
              const Text(
                'Expert options apply to every selected protocol. Choose a manual protocol for protocol-specific options. Flags override environment variables. Unsupported combinations are reported by the core.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Protocol, proxy ports and bundled helper paths are app-managed. SO_MARK needs root; external helper executables must be packaged for Android. File paths must be accessible to the app.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Settings are saved in app-private storage, not encrypted. Avoid saving tokens on shared devices. Direct routes bypass the tunnel; Gateway may log browsing. Debug/trace logs may contain sensitive data.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _arguments,
                minLines: 4,
                maxLines: 12,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Additional arguments (JSON array)',
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
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Environment (JSON object)',
                  helperText: 'Example: {"AETHER_ROUTE_SNIFF_MS": "600"}',
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _timeout,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Advanced startup timeout (seconds)',
                  helperText:
                      '30–3600; used when a country or extra arguments/environment are configured.',
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
                child: const Text('Reset fields to defaults'),
              ),
              const ExpansionTile(
                title: Text('Feature examples'),
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
                title: const Text('Bundled core: full help'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(_help),
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
