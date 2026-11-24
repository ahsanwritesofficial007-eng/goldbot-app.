import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const GoldBotApp());

class GoldBotApp extends StatelessWidget {
  const GoldBotApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Gold Bot',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.amber,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        home: const Gate(),
      );
}

// ------------------------------------------------------------------ API
class Api {
  final String base;
  final String key;
  Api(this.base, this.key);

  Map<String, String> get _h =>
      {'X-API-Key': key, 'Content-Type': 'application/json'};

  Uri _u(String path) =>
      Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}$path');

  dynamic _check(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) return jsonDecode(r.body);
    throw Exception('HTTP ${r.statusCode}: ${r.body}');
  }

  static const _t = Duration(seconds: 20);

  Future<Map<String, dynamic>> status() async => Map<String, dynamic>.from(
      _check(await http.get(_u('/status'), headers: _h).timeout(_t)));

  Future<void> post(String path) async =>
      _check(await http.post(_u(path), headers: _h).timeout(_t));

  Future<Map<String, dynamic>> getSettings() async =>
      Map<String, dynamic>.from(
          _check(await http.get(_u('/settings'), headers: _h).timeout(_t)));

  Future<void> putSettings(Map<String, dynamic> s) async => _check(
      await http.put(_u('/settings'), headers: _h, body: jsonEncode(s))
          .timeout(_t));
}

// ----------------------------------------------------------------- Gate
class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  Api? api;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final u = p.getString('url') ?? '';
    final k = p.getString('key') ?? '';
    setState(() {
      api = (u.isNotEmpty && k.isNotEmpty) ? Api(u, k) : null;
      loading = false;
    });
  }

  Future<void> _disconnect() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('key');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (api == null) return ConnectScreen(onSaved: _load);
    return Dashboard(api: api!, onDisconnect: _disconnect);
  }
}

// -------------------------------------------------------------- Connect
class ConnectScreen extends StatefulWidget {
  final VoidCallback onSaved;
  const ConnectScreen({super.key, required this.onSaved});
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final url = TextEditingController();
  final key = TextEditingController();

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('url', url.text.trim());
    await p.setString('key', key.text.trim());
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Connect to your bot')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            TextField(
              controller: url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                  labelText: 'Server URL (https://...)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: key,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'API key'),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ]),
        ),
      );
}
// ------------------------------------------------------------ Dashboard
class Dashboard extends StatefulWidget {
  final Api api;
  final VoidCallback onDisconnect;
  const Dashboard({super.key, required this.api, required this.onDisconnect});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  Map<String, dynamic>? s;
  String? error;
  Timer? timer;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final r = await widget.api.status();
      if (mounted) setState(() { s = r; error = null; });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _act(String path) async {
    setState(() => busy = true);
    try {
      await widget.api.post(path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
    await _refresh();
    if (mounted) setState(() => busy = false);
  }

  Future<void> _confirmCloseAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Stop bot and close all trades?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Close all')),
        ],
      ),
    );
    if (ok == true) _act('/close_all');
  }

  String _money(dynamic v) =>
      v == null ? '-' : (v as num).toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final running = s?['running'] == true;
    final positions = (s?['positions'] as List?) ?? [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gold Bot'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => SettingsScreen(api: widget.api))),
          ),
          IconButton(
              icon: const Icon(Icons.logout), onPressed: widget.onDisconnect),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (error != null)
            Card(
                color: Colors.red.shade900,
                child: Padding(
                    padding: const EdgeInsets.all(12), child: Text(error!))),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Equity: ${_money(s?['equity'])} ${s?['currency'] ?? ''}',
                        style: Theme.of(context).textTheme.headlineSmall),
                    Text('Balance: ${_money(s?['balance'])}'),
                    const SizedBox(height: 8),
                    Text(running ? 'Bot is RUNNING' : 'Bot is STOPPED',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: running ? Colors.greenAccent : Colors.orange)),
                    Text('Last: ${s?['last_event'] ?? '-'}'),
                  ]),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton(
                onPressed: busy ? null : () => _act(running ? '/stop' : '/start'),
                child: Text(running ? 'Stop' : 'Start'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : _confirmCloseAll,
                child: const Text('Close all'),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          Text('Open trades', style: Theme.of(context).textTheme.titleMedium),
          if (positions.isEmpty)
            const Padding(
                padding: EdgeInsets.all(12), child: Text('No open trades')),
          for (final p in positions)
            Card(
              child: ListTile(
                title: Text(
                    '${(p['type'] as String).replaceAll('POSITION_TYPE_', '')}  ${p['volume']} lots'),
                subtitle: Text('Open @ ${p['open_price']}'),
                trailing: Text(
                  _money(p['profit']),
                  style: TextStyle(
                      color: ((p['profit'] ?? 0) as num) >= 0
                          ? Colors.greenAccent
                          : Colors.redAccent),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------- Settings
class SettingsScreen extends StatefulWidget {
  final Api api;
  const SettingsScreen({super.key, required this.api});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? original;
  final ctrls = <String, TextEditingController>{};
  String? error;

  static const order = [
    'symbol', 'timeframe', 'risk_percent', 'max_daily_loss_pct', 'sl_atr',
    'tp_atr', 'max_spread', 'start_hour_utc', 'end_hour_utc', 'fast', 'slow',
    'trend', 'atr_period',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.getSettings();
      setState(() {
        original = r;
        for (final k in order) {
          if (r.containsKey(k)) ctrls[k] = TextEditingController(text: '${r[k]}');
        }
      });
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> _save() async {
    try {
      final out = <String, dynamic>{};
      for (final k in ctrls.keys) {
        final t = ctrls[k]!.text.trim();
        final o = original![k];
        out[k] = o is int ? int.parse(t) : (o is double ? double.parse(t) : t);
      }
      await widget.api.putSettings(out);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Not saved: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: error != null
            ? Center(child: Text(error!))
            : original == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(padding: const EdgeInsets.all(16), children: [
                    for (final k in ctrls.keys)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextField(
                          controller: ctrls[k],
                          decoration: InputDecoration(labelText: k),
                        ),
                      ),
                    FilledButton(onPressed: _save, child: const Text('Save')),
                  ]),
      );
}
