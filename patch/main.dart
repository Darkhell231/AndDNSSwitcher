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

class Res {
  final bool ok;
  final int? ms;
  final String msg;
  Res(this.ok, this.ms, this.msg);
}

Future<Res> probe(String host) async {
  const t = Duration(seconds: 4);
  List<InternetAddress> addrs;
  try {
    addrs = await InternetAddress.lookup(host).timeout(t);
    if (addrs.isEmpty) return Res(false, null, 'не резолвится');
  } catch (_) {
    return Res(false, null, 'не резолвится');
  }
  Socket sock;
  final sw = Stopwatch()..start();
  try {
    sock = await Socket.connect(addrs.first, 853, timeout: t);
  } catch (_) {
    return Res(false, null, 'нет DoT');
  }
  final ms = sw.elapsedMilliseconds;
  try {
    final s = await SecureSocket.secure(sock, host: host).timeout(t);
    s.destroy();
    return Res(true, ms, 'ok');
  } catch (_) {
    sock.destroy();
    return Res(false, ms, 'нет TLS');
  }
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
  final Map<String, Res> results = {};
  final Set<String> checking = {};

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
    checkAll();
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

  Future<void> check(String h) async {
    if (checking.contains(h)) return;
    setState(() => checking.add(h));
    final r = await probe(h);
    if (!mounted) return;
    setState(() {
      results[h] = r;
      checking.remove(h);
    });
  }

  Future<void> checkAll() async {
    await Future.wait(items.map((e) => check(e['host']!)));
  }

  Future<void> call(String method, [String? h]) async {
    try {
      await ch.invokeMethod(method, {'host': h});
      if (method == 'set') {
        SystemNavigator.pop();
        return;
      }
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
      final h = addr.text.trim();
      items.add({
        'name': name.text.trim().isEmpty ? h : name.text.trim(),
        'host': h,
      });
      await save();
      setState(() {});
      check(h);
    }
  }

  Widget statusWidget(String h) {
    if (checking.contains(h)) {
      return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2));
    }
    final r = results[h];
    if (r == null) return const Text('—');
    if (r.ok) {
      final ms = r.ms ?? 0;
      final color = ms < 100
          ? Colors.greenAccent
          : ms < 250
              ? Colors.orangeAccent
              : Colors.redAccent;
      return Text('$ms мс',
          style: TextStyle(color: color, fontWeight: FontWeight.w600));
    }
    return Text(r.msg, style: const TextStyle(color: Colors.redAccent));
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
          IconButton(
              onPressed: checkAll,
              icon: const Icon(Icons.refresh),
              tooltip: 'Проверить все'),
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
      body: RefreshIndicator(
        onRefresh: checkAll,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: items.length,
          itemBuilder: (c, i) {
            final it = items[i];
            final h = it['host']!;
            final active = mode == 'hostname' && host == h;
            return Dismissible(
              key: ValueKey('$h$i'),
              background: Container(color: Colors.red),
              onDismissed: (_) async {
                items.removeAt(i);
                results.remove(h);
                await save();
                setState(() {});
              },
              child: ListTile(
                title: Text(it['name']!),
                subtitle: Text(h),
                onTap: () => check(h),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    statusWidget(h),
                    const SizedBox(width: 12),
                    IconButton.filled(
                      isSelected: active,
                      icon: Icon(active ? Icons.check : Icons.play_arrow),
                      onPressed: () => call('set', h),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
