import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'striped.dart';
import 'widgets.dart';
import 'i18n.dart';

const _repo = 'designer1974/devoo-radio';
const _ch = MethodChannel('rr/recorder');

class UpdateInfo {
  final int build;
  final String url;
  final int size;
  const UpdateInfo(this.build, this.url, this.size);
}

/// Cerca su GitHub una versione Pro più nuova di quella installata.
Future<UpdateInfo?> findUpdate() async {
  try {
    // versione installata: quando è stata installata/aggiornata su questo telefono
    final installedMs = (await _ch.invokeMethod<num>('installedAt'))?.toInt() ?? 0;
    if (installedMs <= 0) return null;
    final installed = DateTime.fromMillisecondsSinceEpoch(installedMs);
    final r = await http.get(Uri.https('api.github.com', '/repos/$_repo/releases', {'per_page': '15'}),
        headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'DevooRadio'}).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return null;
    final list = jsonDecode(r.body);
    if (list is! List) return null;
    var is64 = true;
    try {
      is64 = await _ch.invokeMethod<bool>('is64') ?? true;
    } catch (_) {}
    final want = is64 ? 'DevooRadioPro.apk' : 'DevooRadioPro-telefoni-vecchi.apk';
    UpdateInfo? best;
    for (final rel in list) {
      if (rel is! Map) continue;
      final tag = '${rel['tag_name']}';
      if (!tag.startsWith('pro-build-')) continue;
      final n = int.tryParse(tag.substring('pro-build-'.length)) ?? 0;
      final pub = DateTime.tryParse('${rel['published_at']}');
      // più nuova = pubblicata dopo l'installazione di questa versione
      if (pub == null || !pub.isAfter(installed.add(const Duration(minutes: 2)))) continue;
      if (best != null && n <= best.build) continue;
      for (final a in (rel['assets'] as List? ?? const [])) {
        if (a is Map && a['name'] == want) {
          best = UpdateInfo(n, '${a['browser_download_url']}', (a['size'] as num?)?.toInt() ?? 0);
        }
      }
    }
    return best;
  } catch (_) {
    return null;
  }
}

/// All'avvio: se c'è una versione nuova, la propone (una volta per versione).
Future<void> checkForUpdate(BuildContext context) async {
  final u = await findUpdate();
  if (u == null || !context.mounted) return;
  try {
    final p = await SharedPreferences.getInstance();
    if (p.getInt('update_skipped') == u.build) return;
  } catch (_) {}
  if (!context.mounted) return;
  showModalBottomSheet(
    context: context,
    isDismissible: true,
    showDragHandle: true,
    builder: (_) => UpdateSheet(info: u),
  );
}

class UpdateSheet extends StatefulWidget {
  const UpdateSheet({super.key, required this.info});
  final UpdateInfo info;
  @override
  State<UpdateSheet> createState() => _UpdateSheetState();
}

enum _St { ready, downloading, installing, error }

class _UpdateSheetState extends State<UpdateSheet> {
  _St _st = _St.ready;
  double _p = 0;
  int _got = 0;
  String? _msg;
  http.Client? _client;

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }

  String _mb(int b) => (b / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',');

  Future<void> _go() async {
    setState(() {
      _st = _St.downloading;
      _p = 0;
      _got = 0;
      _msg = null;
    });
    final client = _client = http.Client();
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/DevooRadioPro-update.apk');
      final res = await client.send(http.Request('GET', Uri.parse(widget.info.url)))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final total = res.contentLength ?? widget.info.size;
      final sink = f.openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        _got += chunk.length;
        if (mounted && total > 0) setState(() => _p = _got / total);
      }
      await sink.close();
      if (!mounted) return;
      setState(() {
        _p = 1;
        _st = _St.installing;
      });
      final r = await _ch.invokeMethod<String>('installApk', {'path': f.path});
      if (!mounted) return;
      if (r != 'ok') throw Exception(r);
      Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _st = _St.error;
          _msg = 'Download non riuscito. Controlla internet e riprova.';
        });
      }
    }
  }

  Future<void> _later() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('update_skipped', widget.info.build);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = (_p * 100).clamp(0, 100).round();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.system_update, color: accent, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Nuova versione disponibile',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  Text('Devoo Radio Pro build ${widget.info.build} · ${_mb(widget.info.size)} MB',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ]),
              ),
            ]),
            const SizedBox(height: 22),
            if (_st == _St.ready || _st == _St.error) ...[
              if (_msg != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_msg!, style: const TextStyle(color: recRed)),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.download_rounded),
                  label: Text(_st == _St.error ? 'Riprova' : 'Aggiorna ora',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  onPressed: _go,
                ),
              ),
              const SizedBox(height: 6),
              Center(child: TextButton(onPressed: _later, child: const Text('Più tardi'))),
            ] else ...[
              Row(
                children: [
                  Text(_st == _St.installing ? 'Apro l\'installazione…' : 'Scarico l\'aggiornamento…',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('$pct%',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
                ],
              ),
              const SizedBox(height: 10),
              StripedBar(value: _st == _St.installing ? 1 : _p, height: 14),
              const SizedBox(height: 8),
              Text(
                _st == _St.installing
                    ? 'Tocca «Installa» nella finestra di Android. Le registrazioni restano dove sono.'
                    : '${_mb(_got)} di ${_mb(widget.info.size)} MB',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
