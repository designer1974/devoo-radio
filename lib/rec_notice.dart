import 'package:flutter/material.dart' hide Text;
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n.dart';

/// Chiave del navigatore principale: serve per mostrare avvisi da fuori dalle pagine.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// Alla prima registrazione: a cosa serve e che è solo per uso personale.
Future<bool> recNoticeAccepted() async {
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('recNotice') == true) return true;
  } catch (_) {}
  final ctx = appNavigatorKey.currentContext;
  if (ctx == null) return true;
  final ok = await showDialog<bool>(
    context: ctx,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.fiber_manual_record, color: Color(0xFFFF4D4F)),
      title: Text(tr('Registra per riascoltare dopo')),
      content: Text(tr('Notizie, programmi e lezioni di lingua da ascoltare quando vuoi. '
          'Le registrazioni sono solo per uso personale: rispetta i diritti delle radio.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Annulla'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Ho capito, registra'))),
      ],
    ),
  );
  if (ok == true) {
    try {
      await prefs?.setBool('recNotice', true);
    } catch (_) {}
    return true;
  }
  return false;
}
