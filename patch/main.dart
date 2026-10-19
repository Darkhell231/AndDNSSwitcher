import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'DNS Switch',
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
        ),
        home: const Home(),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  static const ch = MethodChannel('dns');
  List<Map<String, String>> items = [];
  String mode = '';
  String? host;
  File? file;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    file = File('${dir.path}/dns_items.json');
    try {
      if (await file!.exists()) {
        items = (jsonDecode(await file!.readAsString()) as List)
            .map((e) => Map<String, String>.from(e))
            .toList();
      }
    } catch (_) {}
    await refresh();
  }

  Future<void> save() async {
    try {
      await file!.writeAsString(jsonEncode(items), flush: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Не удалось сохранить: $e')));
    }
  }

  Future<void> refresh() async {
    try {
      final Map r = await ch.invokeMethod('get');
      mode = (r['mode'] ?? '') as String;
      host = r['host'] as String?;
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> call(String method, [String? h]) async {
    try {
      await ch.invokeMethod(method, {'host': h});
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Нет разрешения WRITE_SECURE_SETTINGS (выдай через Shizuku/adb)'),
      ));
    }
    await refresh();
  }

  Future<void> addDialog() async {
    final name = TextEditingController();
    final addr = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Новый DNS'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Название')),
          TextField(
              controller: addr,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                  labelText: 'Адрес', hintText: 'xbox-dns.ru')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Добавить')),
        ],
      ),
    );
    if (ok == true && addr.text.trim().isNotEmpty) {
      items.add({
        'name': name.text.trim().isEmpty ? addr.text.trim() : name.text.trim(),
        'host': addr.text.trim(),
      });
      await save();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = mode == 'hostname'
        ? 'Сейчас: $host'
        : mode == 'off'
            ? 'Частный DNS: выключен'
            : 'Частный DNS: автоматически';
    return Scaffold(
      appBar: AppBar(
        title: const Text('DNS Switch'),
        actions: [
          TextButton(onPressed: () => call('off'), child: const Text('Выкл')),
          TextButton(onPressed: () => call('auto'), child: const Text('Авто')),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(status),
          ),
        ),
      ),
      floatingActionButton:
          FloatingActionButton(onPressed: addDialog, child: const Icon(Icons.add)),
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (c, i) {
          final it = items[i];
          final active = mode == 'hostname' && host == it['host'];
          return Dismissible(
            key: ValueKey('${it['host']}$i'),
            background: Container(color: Colors.red),
            onDismissed: (_) async {
              items.removeAt(i);
              await save();
              setState(() {});
            },
            child: ListTile(
              title: Text(it['name']!),
              subtitle: Text(it['host']!),
              trailing: IconButton.filled(
                isSelected: active,
                icon: Icon(active ? Icons.check : Icons.play_arrow),
                onPressed: () => call('set', it['host']),
              ),
            ),
          );
        },
      ),
    );
  }
}
