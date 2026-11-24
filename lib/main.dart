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
