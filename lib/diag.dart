import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'i18n.dart';

/// Registro degli errori: se l'app si blocca o si chiude, alla prossima apertura si vede il motivo.
class Diag {
  static const _ch = MethodChannel('rr/recorder');
  static final List<String> _mem = [];
  static File? _file;

  static Future<void> init() async {
    try {
      final d = await getApplicationSupportDirectory();
      _file = File('${d.path}/errori.txt');
      for (final l in _mem) {
        await _file!.writeAsString('$l\n', mode: FileMode.append);
      }
    } catch (_) {}
  }

  static void log(Object error, [StackTrace? stack]) {
    final s = '${DateTime.now().toIso8601String().substring(0, 19)} $error\n'
        '${(stack ?? StackTrace.current).toString().split('\n').take(12).join('\n')}';
    debugPrint(s);
    _mem.add(s);
    try {
      _file?.writeAsStringSync('$s\n', mode: FileMode.append);
    } catch (_) {}
  }

  /// Mostra gli errori della volta scorsa (e li cancella).
  static Future<void> showIfAny(BuildContext context) async {
    String text = '';
    try {
      final native = await _ch.invokeMethod<String>('lastCrash');
      if (native != null && native.isNotEmpty) text += 'ANDROID:\n$native\n\n';
    } catch (_) {}
    try {
      final f = _file;
      if (f != null && await f.exists()) {
        final t = await f.readAsString();
        await f.delete();
        if (t.trim().isNotEmpty) text += 'APP:\n${t.length > 5000 ? t.substring(t.length - 5000) : t}';
      }
    } catch (_) {}
    if (text.isEmpty || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Rapporto errori')),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: SelectableText(text, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: text)),
            child: Text(tr('Copia')),
          ),
          FilledButton(onPressed: () => Navigator.pop(c), child: Text(tr('Chiudi'))),
        ],
      ),
    );
  }
}
